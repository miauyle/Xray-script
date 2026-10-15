"""Regression test: successful Xray configuration must not return a false failure."""
import json
import re
import shlex
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HANDLER_TEXT = (ROOT / "core" / "handler.sh").read_text(encoding="utf-8")
CONFIG = {
    "xray": {
        "tag": "Vision",
        "port": 443,
        "uuid": "00000000-0000-4000-8000-000000000001",
        "fallback": "",
        "trojan": "",
        "kcp": "",
        "target": "example.org",
        "serverNames": ["example.org"],
        "privateKey": "TEST_PRIVATE_KEY_ONLY",
        "shortIds": ["01234567"],
        "path": "/test",
        "rules": {"reset": 0, "bt": 0, "cn": 0, "ad": 0},
        "warp": 0,
        "direct_family": "auto",
        "warp_fallback": 0,
    },
    "rules": [],
}


def extract_function(name):
    # Extract the production implementation rather than copying its tail into
    # a fake function (which would not catch the original false exit status).
    match = re.search(
        r"(?ms)^function " + re.escape(name) + r"\(\) \{.*?^\}\s*$",
        HANDLER_TEXT,
    )
    if match is None:
        raise AssertionError("Missing shell function: " + name)
    return match.group(0)


class HandlerXrayReturnTests(unittest.TestCase):
    def run_case(self, pending):
        with tempfile.TemporaryDirectory() as directory:
            temp = Path(directory)
            pending_file = temp / "pending.json"
            if pending:
                pending_file.write_text("{}\n", encoding="utf-8")
            # Mock only side effects. Execute the actual Xray config generator
            # with Vision.json, jq transforms, and the production function tail.
            script = "\n".join([
                'set -u',
                'GREEN=""',
                'NC=""',
                'CUR_FILE=handler',
                'I18N_DATA=' + shlex.quote(json.dumps({
                    "title": {"config": "Config"},
                    "handler": {"xray": {"config_update": "Updating Xray config"}},
                })),
                'SCRIPT_CONFIG=' + shlex.quote(json.dumps(CONFIG)),
                'SCRIPT_XRAY_DIR=' + shlex.quote(str(ROOT / "config" / "xray")),
                'SCRIPT_CONFIG_PENDING_PATH=' + shlex.quote(str(pending_file)),
                'apply_xray_config() { [[ "$1" == "xray:regenerate" && "$2" == "restart" ]]; }',
                'persist_script_config() { return 0; }',
                extract_function("handler_xray_config"),
                'handler_xray_config restart',
                'status=$?',
                '[[ "$status" == 0 ]] || exit "$status"',
                '[[ "$(echo "$XRAY_CONFIG" | jq -r ".inbounds[1].streamSettings.realitySettings.target")" == "example.org:443" ]] || exit 22',
                '[[ "$(echo "$XRAY_CONFIG" | jq -r ".inbounds[1].settings.clients[0].id")" == "00000000-0000-4000-8000-000000000001" ]] || exit 23',
                '[[ -z "$(trap -p EXIT)" ]] || exit 24',
            ])
            return subprocess.run(
                ["bash", "-c", script],
                text=True, capture_output=True, timeout=20, cwd=ROOT
            )

    def test_fresh_setup_returns_success(self):
        result = self.run_case(pending=False)
        self.assertEqual(result.returncode, 0, result.stderr + "\n" + result.stdout)

    def test_existing_pending_snapshot_returns_success(self):
        result = self.run_case(pending=True)
        self.assertEqual(result.returncode, 0, result.stderr + "\n" + result.stdout)

    def test_reality_private_key_not_emailed_to_terminal(self):
        # Prior versions echoed the secret to stderr during installation.
        key_function = extract_function("handler_x25519_config")
        self.assertNotRegex(key_function, r"echo[^\n]*PRIVATE_KEY")
        self.assertIn(".xray.privateKey", key_function)


if __name__ == "__main__":
    unittest.main()
