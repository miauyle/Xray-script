"""Regression tests for Xray release selection and verified, non-destructive upgrades."""
import hashlib
import json
import re
import shlex
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HANDLER = (ROOT / "core" / "handler.sh").read_text(encoding="utf-8")


def production_function(name):
    match = re.search(
        r"(?ms)^function " + re.escape(name) + r"\(\) \{.*?^\}",
        HANDLER,
    )
    if match is None:
        raise AssertionError(f"Missing production function: {name}")
    return match.group(0)


FUNCTIONS = "\n".join(
    production_function(name)
    for name in (
        "xray_resolve_version",
        "xray_installed_version",
        "xray_install_verified",
        "handler_install",
    )
)


def run_bash(script, env=None):
    return subprocess.run(
        ["bash", "-c", script], text=True, capture_output=True,
        cwd=ROOT, timeout=30, env=env
    )


class XrayUpdateTests(unittest.TestCase):
    def test_latest_includes_prerelease_but_stable_does_not(self):
        releases = [
            {"tag_name": "v26.9.30", "published_at": "2026-09-30T00:00:00Z", "draft": False},
            {"tag_name": "v26.10.21", "published_at": "2026-10-21T00:00:00Z", "draft": False},
            {"tag_name": "v99.1.1", "published_at": "2026-10-22T00:00:00Z", "draft": True},
        ]
        script = "\n".join([
            "declare -A CONFIG_DATA=()",
            "curl() { if [[ \"$*\" == *'/releases/latest'* ]]; then printf '%s\\n' '{\"tag_name\":\"v26.3.27\"}'; else printf '%s\\n' " + shlex.quote(json.dumps(releases)) + "; fi; }",
            FUNCTIONS,
            "xray_resolve_version latest || exit 1",
            '[[ "@{CONFIG_DATA[version]}" == "v26.10.21" ]] || exit 2',
            "xray_resolve_version release || exit 3",
            '[[ "@{CONFIG_DATA[version]}" == "v26.3.27" ]] || exit 4',
        ]).replace("@{", "$" + "{")
        result = run_bash(script)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_api_failure_does_not_create_null_version(self):
        script = "\n".join([
            "declare -A CONFIG_DATA=()",
            "curl() { printf '%s\\n' '{\"message\":\"rate limit\"}'; }",
            FUNCTIONS,
            "if xray_resolve_version latest; then exit 20; fi",
            '[[ -z "@{CONFIG_DATA[version]:-}" ]] || exit 21',
        ]).replace("@{", "$" + "{")
        result = run_bash(script)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_failed_install_keeps_actual_installed_version(self):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / "xray"
            path.write_text('#!/bin/sh\necho "Xray 26.3.27"\n')
            path.chmod(0o755)
            cfg = json.dumps({"xray": {"version": "v26.10.21"}})
            script = "\n".join([
                "declare -A CONFIG_DATA=()",
                "XRAY_BINARY_PATH=" + shlex.quote(str(path)),
                "SCRIPT_CONFIG=" + shlex.quote(cfg),
                "persist_script_config() { :; }",
                "xray_install_verified() { return 1; }",
                FUNCTIONS.replace(production_function("xray_install_verified"), ""),
                "if handler_install v26.10.21 y; then exit 30; fi",
                '[[ "$(jq -r .xray.version <<<"$SCRIPT_CONFIG")" == "v26.3.27" ]] || exit 31',
                '[[ "$(xray_installed_version)" == "v26.3.27" ]] || exit 32',
            ])
            result = run_bash(script)
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_verified_archive_and_rollback_after_installer_failure(self):
        with tempfile.TemporaryDirectory() as d:
            tmp = Path(d)
            old = tmp / "xray"
            old.write_text('#!/bin/sh\necho "Xray 26.3.27"\n')
            old.chmod(0o755)
            service_file = tmp / "xray.service"
            archive = tmp / "fixture.zip"
            archive.write_bytes(b"mock binary archive with safe test content")
            digest = tmp / "fixture.dgst"
            digest.write_text("SHA256= " + hashlib.sha256(archive.read_bytes()).hexdigest() + "\n")

            stubs = """
curl() {
    local target=''
    while (($#)); do
        if [[ "$1" == '-o' ]]; then target="$2"; shift 2; else shift; fi
    done
    case "$target" in
        *.zip) cp "$FIXTURE_ZIP" "$target" ;;
        *.dgst) cp "$FIXTURE_DIGEST" "$target" ;;
        */install-release.sh)
            # Faithful subset of upstream Xray-install argument parsing.
            # A real child shell executes this installer; unsupported -u root
            # must fail rather than being silently accepted by a Bash mock.
            cat > "$target" <<'INSTALLER'
#!/usr/bin/env bash
[[ "$1" == install && "$2" == --local && -s "$3" ]] || {
    echo 'unknown installer arguments' >&2
    exit 64
}
if [[ -f "$XRAY_SERVICE_FILE_PATH" ]]; then
    [[ "$#" -eq 4 && "$4" == --no-update-service ]] || exit 65
else
    [[ "$#" -eq 3 ]] || exit 66
fi
printf '#!/bin/sh\\necho "Xray 26.10.21"\\n' > "$XRAY_BINARY_PATH"
chmod +x "$XRAY_BINARY_PATH"
[[ "$MOCK_INSTALL_FAIL" != 1 ]]
INSTALLER
            ;;
        *) return 88 ;;
    esac
}
systemctl() { return 1; }
"""
            base = "\n".join([
                "declare -A CONFIG_DATA=()",
                "export XRAY_BINARY_PATH=" + shlex.quote(str(old)),
                "export XRAY_SERVICE_FILE_PATH=" + shlex.quote(str(service_file)),
                "FIXTURE_ZIP=" + shlex.quote(str(archive)),
                "FIXTURE_DIGEST=" + shlex.quote(str(digest)),
                stubs,
                FUNCTIONS,
            ])
            success = run_bash(base + '\nexport MOCK_INSTALL_FAIL=0\nxray_install_verified v26.10.21 || exit 40\n'
                                      '[[ "$(xray_installed_version)" == "v26.10.21" ]] || exit 41\n')
            self.assertEqual(success.returncode, 0, success.stderr)

            # A second successful upgrade with an existing service must pass
            # --no-update-service (never overwrite hand-tuned systemd units).
            service_file.write_text("[Service]\\nUser=root\\n")
            old.write_text('#!/bin/sh\necho "Xray 26.3.27"\n')
            old.chmod(0o755)
            with_service = run_bash(base + '\nexport MOCK_INSTALL_FAIL=0\n'
                                           'xray_install_verified v26.10.21 || exit 44\n')
            self.assertEqual(with_service.returncode, 0, with_service.stderr)

            old.write_text('#!/bin/sh\necho "Xray 26.3.27"\n')
            old.chmod(0o755)
            failed = run_bash(base + '\nexport MOCK_INSTALL_FAIL=1\n'
                                     'if xray_install_verified v26.10.21; then exit 42; fi\n'
                                     '[[ "$(xray_installed_version)" == "v26.3.27" ]] || exit 43\n')
            self.assertEqual(failed.returncode, 0, failed.stderr)

    def test_bad_checksum_aborts_before_installation(self):
        with tempfile.TemporaryDirectory() as d:
            tmp = Path(d)
            binary = tmp / "xray"
            zip_path = tmp / "fixture.zip"
            zip_path.write_bytes(b"abc")
            bad_digest = tmp / "wrong.dgst"
            bad_digest.write_text("SHA256= " + "0" * 64 + "\n")
            script = "\n".join([
                "XRAY_BINARY_PATH=" + shlex.quote(str(binary)),
                "FIXTURE_ZIP=" + shlex.quote(str(zip_path)),
                "FIXTURE_DIGEST=" + shlex.quote(str(bad_digest)),
                """curl() {
                    local out=''
                    while (($#)); do
                      if [[ "$1" == '-o' ]]; then out="$2"; shift 2; else shift; fi
                    done
                    case "$out" in
                      *.zip) cp "$FIXTURE_ZIP" "$out";;
                      *.dgst) cp "$FIXTURE_DIGEST" "$out";;
                      *) printf 'installer stub\\n' > "$out";;
                    esac
                }""",
                "bash() { exit 90; }",
                "systemctl() { return 1; }",
                FUNCTIONS,
                "if xray_install_verified v26.10.21; then exit 51; fi",
                '[[ ! -f "$XRAY_BINARY_PATH" ]] || exit 52',
            ])
            result = run_bash(script)
            self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
