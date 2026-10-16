"""Regression: Xray reconfiguration must refresh active subscriptions safely."""
import json
import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest

from test_xray_handler_exit import CONFIG, ROOT, extract_function


class XrayPublicationSyncTests(unittest.TestCase):
    def run_case(self, existing=True, failed_refresh=False, mode="restart"):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            (root / "clash").mkdir()
            if existing:
                (root / "clash" / "clash.yaml").write_text("existing subscription")
            refresh = root / "fake-refresh.sh"
            refresh.write_text(
                "#!/usr/bin/env bash\n"
                'echo "$1" >> "$SYNC_TEST_LOG"\n'
                + ("exit 17\n" if failed_refresh else "exit 0\n")
            )
            logfile = root / "refresh.log"
            script = "\n".join([
                "set -u",
                "GREEN=''","YELLOW=''","NC=''","CUR_FILE=handler",
                "SCRIPT_CONFIG_DIR=" + shlex.quote(str(root)),
                "CLASH_PATH=" + shlex.quote(str(refresh)),
                "SCRIPT_CONFIG_PENDING_PATH=" + shlex.quote(str(root / "pending")),
                "SCRIPT_XRAY_DIR=" + shlex.quote(str(ROOT / "config" / "xray")),
                "SCRIPT_CONFIG=" + shlex.quote(json.dumps(CONFIG)),
                "I18N_DATA=" + shlex.quote(json.dumps({
                    "title": {"config": "Config"},
                    "handler": {"xray": {"config_update": "Update Xray"}},
                })),
                'apply_xray_config() { return 0; }',
                'persist_script_config() { return 0; }',
                extract_function("handler_xray_config"),
                "handler_xray_config " + shlex.quote(mode),
            ])
            p = subprocess.run(
                ["bash", "-c", script], cwd=ROOT,
                env={**os.environ, "SYNC_TEST_LOG": str(logfile)},
                capture_output=True, text=True, timeout=15
            )
            return p, logfile.read_text() if logfile.exists() else ""

    def test_existing_subscription_refreshed_after_successful_apply(self):
        p, calls = self.run_case()
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertEqual(calls, "generate\n")

    def test_failed_refresh_does_not_turn_successful_xray_apply_into_failure(self):
        p, calls = self.run_case(failed_refresh=True)
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertEqual(calls, "generate\n")
        self.assertIn("subscription regeneration failed", p.stderr)

    def test_no_subscription_means_no_refresh(self):
        p, calls = self.run_case(existing=False)
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertEqual(calls, "")

    def test_deferred_xray_build_does_not_publish_premature_credentials(self):
        p, calls = self.run_case(mode="defer")
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertEqual(calls, "")


if __name__ == "__main__":
    unittest.main()
