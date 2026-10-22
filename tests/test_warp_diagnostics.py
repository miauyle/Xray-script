"""Non-mutating WARP diagnosis and explicitly confirmed reconnect regressions."""
import re
import shlex
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OPS = (ROOT / "core" / "operations.sh").read_text(encoding="utf-8")


def func(name):
    match = re.search(r"(?ms)^function " + re.escape(name) + r"\(\) \{.*?^\}", OPS)
    assert match, "Missing WARP production function " + name
    return match.group(0)


DIAGNOSTIC = "\n".join(func(x) for x in (
    "ops_get_warp_container_ip", "ops_warp_tcp_listener",
    "ops_warp_trace", "ops_warp_client_snapshot", "ops_warp_client_status",
    "ops_warp_client_reason", "ops_warp_client_mode",
    "ops_warp_direct_fallback_state", "handler_warp_status",
))
RECONNECT = func("handler_warp_reconnect")

STUBS = r"""
SCRIPT_CONFIG='{"xray":{"warp":1,"warp_fallback":0}}'
docker() {
    case "$*" in
        *"inspect -f"*) echo running;;
        *"inspect --format"*) echo 172.17.0.2;;
        *"warp-cli"*"status"*) printf 'Status update: Connecting\nReason: Validating SOCKS proxy configuration\n';;
        *"warp-cli"*"settings"*) echo 'Mode: WarpProxy on port 40000';;
        *"warp-cli"*"disconnect"*) printf 'disconnect\n' >>"$ACTION_LOG";;
        *"warp-cli"*"connect"*) printf 'connect\n' >>"$ACTION_LOG";;
        *) return 23;;
    esac
}
ops_warp_tcp_listener() { return 0; }
sleep() { :; }
"""


def run(script):
    return subprocess.run(["bash", "-c", script], text=True, capture_output=True,
                          cwd=ROOT, timeout=30)


class WarpDiagnosticsTests(unittest.TestCase):
    def test_single_status_handler_no_shadowed_definition(self):
        self.assertEqual(len(re.findall(r"(?m)^function handler_warp_status\(\)", OPS)), 1)
        self.assertEqual(len(re.findall(r"(?m)^function handler_warp_reconnect\(\)", OPS)), 1)

    def test_failed_socks_handshake_reports_stage_without_mutation(self):
        with tempfile.TemporaryDirectory() as td:
            actions = Path(td) / "actions"
            script = "\n".join([
                "ACTION_LOG=" + shlex.quote(str(actions)),
                STUBS,
                r"""curl() { echo 'curl: (97) connection to proxy closed' >&2; return 97; }""",
                DIAGNOSTIC,
                "handler_warp_status",
            ])
            result = run(script)
            self.assertEqual(result.returncode, 0, result.stderr)
            for value in ("WARP client     : Connecting",
                          "Connection stage: Validating SOCKS proxy configuration",
                          "SOCKS TCP port  : reachable",
                          "SOCKS data path : failed (2 attempts)",
                          "curl: (97) connection to proxy closed",
                          "Direct fallback : disabled"):
                self.assertIn(value, result.stdout)
            self.assertFalse(actions.exists(), "Diagnostics must not restart WARP")

    def test_http_success_without_warp_is_not_healthy(self):
        with tempfile.TemporaryDirectory() as td:
            actions = Path(td) / "actions"
            script = "\n".join([
                "ACTION_LOG=" + shlex.quote(str(actions)),
                STUBS,
                r"""curl() { printf 'ip=198.51.100.23\nloc=KR\nwarp=off\n'; }""",
                DIAGNOSTIC,
                "handler_warp_status",
            ])
            result = run(script)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("SOCKS data path : HTTP request succeeded", result.stdout)
            self.assertIn("WARP data path  : FAILED (warp=off)", result.stdout)
            self.assertFalse(actions.exists())

    def test_reconnect_needs_literal_yes_and_preserves_container(self):
        with tempfile.TemporaryDirectory() as td:
            actions = Path(td) / "actions"
            base = "\n".join([
                "ACTION_LOG=" + shlex.quote(str(actions)),
                STUBS,
                DIAGNOSTIC,
                RECONNECT,
                "handler_warp_status() { echo 'diagnosis refreshed'; }",
            ])
            declined = run(base + "\nhandler_warp_reconnect <<<'no'\n")
            self.assertEqual(declined.returncode, 0, declined.stderr)
            self.assertFalse(actions.exists())
            self.assertIn("Canceled", declined.stdout)
            accepted = run(base + "\nhandler_warp_reconnect <<<'yes'\n")
            self.assertEqual(accepted.returncode, 0, accepted.stderr)
            self.assertEqual(actions.read_text(), "disconnect\nconnect\n")
            self.assertIn("diagnosis refreshed", accepted.stdout)
            self.assertNotIn("registration delete", RECONNECT)
            self.assertNotIn("docker rm", RECONNECT)
            self.assertNotIn("docker restart", RECONNECT)


if __name__ == "__main__":
    unittest.main()
