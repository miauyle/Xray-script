"""Regression tests for Xray log policy, validation diagnostics, and safe upgrades."""
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


def shell_function(name):
    match = re.search(
        r"(?ms)^function " + re.escape(name) + r"\(\) \{.*?^\}",
        HANDLER,
    )
    assert match, "Missing production function: " + name
    return match.group(0)


def run_shell(script):
    return subprocess.run(["bash", "-c", script], cwd=ROOT,
                          capture_output=True, text=True, timeout=30)


class XrayReliabilityTests(unittest.TestCase):
    def test_every_generated_template_has_persistent_file_logs(self):
        # Preserve the user's access/error logs for future diagnosis.
        for path in (ROOT / "config" / "xray").glob("*.json"):
            with self.subTest(template=path.name):
                data = json.loads(path.read_text(encoding="utf-8"))
                self.assertEqual(data["log"].get("loglevel"), "warning")
                self.assertEqual(data["log"]["access"], "/var/log/xray/access.log")
                self.assertEqual(data["log"]["error"], "/var/log/xray/error.log")

    def test_invalid_candidate_preserves_original_and_prints_real_error(self):
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / "config.json"
            p.write_text('{"existing":true}\n', encoding="utf-8")
            script = "\n".join([
                "XRAY_CONFIG_PATH=" + shlex.quote(str(p)),
                "XRAY_CONFIG='{\"new\":true}'",
                "GREEN='' YELLOW='' NC=''",
                "_error() { echo \"ERROR: $*\" >&2; exit 1; }",
                "xray() { echo 'failed to build inbound: incompatible REALITY option' >&2; return 23; }",
                "restore_pending_script_config() { return 0; }",
                shell_function("apply_xray_config"),
                "apply_xray_config xray:regenerate restart",
            ])
            result = run_shell(script)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("incompatible REALITY option", result.stderr)
            self.assertIn("original config was kept", result.stderr)
            self.assertEqual(json.loads(p.read_text()), {"existing": True})

    def test_apply_uses_json_suffixed_temporary_file_and_keeps_candidate(self):
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "config.json"
            candidate = '{"log":{"loglevel":"warning"}}'
            script = "\n".join([
                "XRAY_CONFIG_PATH=" + shlex.quote(str(path)),
                "XRAY_CONFIG=" + shlex.quote(candidate),
                "_error() { echo \"$*\" >&2; exit 90; }",
                "xray() {",
                '  local candidate="${@: -1}"',
                '  [[ "$candidate" == *.json ]] || { echo "unsupported config file extension" >&2; return 23; }',
                '  jq empty "$candidate"',
                "}",
                "xray_prepare_log_files() { return 0; }",
                "backup_xray_config() { :; }",
                shell_function("apply_xray_config"),
                "apply_xray_config ci:fresh-install",
                '[[ -s "$XRAY_CONFIG_PATH" ]] || exit 91',
                '[[ "$(jq -c . "$XRAY_CONFIG_PATH")" == ' + shlex.quote(candidate) + ' ]] || exit 92',
            ])
            result = run_shell(script)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads(path.read_text()), json.loads(candidate))

    def test_rollback_staged_file_uses_json_extension(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            installed = root / "config.json"
            backup = root / "backup.json"
            installed.write_text('{"value":"new"}')
            backup.write_text('{"value":"old"}')
            script = "\n".join([
                "XRAY_CONFIG_PATH=" + shlex.quote(str(installed)),
                "SCRIPT_CONFIG_PENDING_PATH=" + shlex.quote(str(root / "none")),
                "xray() {",
                '  local candidate="${@: -1}"',
                '  [[ "$candidate" == *.json ]] || { echo "unsupported config file extension" >&2; return 23; }',
                '  jq empty "$candidate"',
                "}",
                "clear_pending_script_config() { :; }",
                "restart_xray_service_checked() { return 0; }",
                shell_function("rollback_xray_config"),
                "rollback_xray_config " + shlex.quote(str(backup)) + " ci:rollback",
            ])
            result = run_shell(script)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads(installed.read_text()), {"value": "old"})

    def test_fast_crashing_service_is_not_accepted_as_healthy(self):
        script = "\n".join([
            "CHECKS=0",
            "xray_prepare_log_files() { return 0; }",
            "systemctl() {",
            '  if [[ "$*" == *"is-active"* ]]; then',
            '    CHECKS=$((CHECKS+1))',
            '    [[ "$CHECKS" -le 2 ]]',
            '  else return 0; fi',
            "}",
            "sleep() { :; }",
            shell_function("restart_xray_service_checked"),
            "if restart_xray_service_checked; then exit 32; fi",
        ])
        result = run_shell(script)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_incompatible_core_restores_original_binary_before_success(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            binary = root / "xray"
            binary.write_text('#!/bin/sh\necho "Xray 26.3.27"\n', encoding="utf-8")
            binary.chmod(0o755)
            config = root / "config.json"
            config.write_text('{"log":{"loglevel":"warning"}}\n', encoding="utf-8")
            archive = root / "release.zip"
            archive.write_bytes(b"test release payload")
            digest = root / "release.zip.dgst"
            digest.write_text("SHA256= " + hashlib.sha256(archive.read_bytes()).hexdigest() + "\n")
            script = "\n".join([
                "export XRAY_BINARY_PATH=" + shlex.quote(str(binary)),
                "XRAY_CONFIG_PATH=" + shlex.quote(str(config)),
                "XRAY_SERVICE_FILE_PATH=" + shlex.quote(str(root / "no-service")),
                "FIXTURE_ZIP=" + shlex.quote(str(archive)),
                "FIXTURE_DIGEST=" + shlex.quote(str(digest)),
                "xray_prepare_log_files() { return 0; }",
                r"""curl() {
  local dest=''
  while (($#)); do
    if [[ "$1" == -o ]]; then dest="$2"; shift 2; else shift; fi
  done
  case "$dest" in
    *.zip) cp "$FIXTURE_ZIP" "$dest" ;;
    *.dgst) cp "$FIXTURE_DIGEST" "$dest" ;;
    */install-release.sh)
      cat > "$dest" <<'INSTALLER'
#!/usr/bin/env bash
[[ "$1" == install && "$2" == --local && -s "$3" && "$#" -eq 3 ]] || exit 64
cat > "$XRAY_BINARY_PATH" <<'XRAY'
#!/bin/sh
if [ "$1" = version ]; then
  echo "Xray 26.10.21"
else
  echo "incompatible live configuration" >&2
  exit 23
fi
XRAY
chmod 755 "$XRAY_BINARY_PATH"
INSTALLER
      ;;
    *) return 42 ;;
  esac
}
systemctl() { return 1; }""",
                shell_function("xray_installed_version"),
                shell_function("xray_install_verified"),
                'if xray_install_verified v26.10.21; then exit 41; fi',
                '[[ "$(xray_installed_version)" == v26.3.27 ]] || exit 42',
            ])
            result = run_shell(script)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("incompatible live configuration", result.stderr)
            self.assertIn("restoring the previous Xray binary", result.stderr)


if __name__ == "__main__":
    unittest.main()
