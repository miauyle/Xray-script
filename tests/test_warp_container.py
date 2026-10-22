"""Regression tests for WARP container IP discovery and failure cleanup."""
import os
import re
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DOCKER_TEXT = (ROOT / "service" / "docker.sh").read_text(encoding="utf-8")
HANDLER_TEXT = (ROOT / "core" / "handler.sh").read_text(encoding="utf-8")


def extract_function(source, name):
    match = re.search(
        r"(?ms)^function " + re.escape(name) + r"\(\) \{.*?^\}",
        source,
    )
    if not match:
        raise AssertionError("Missing shell function " + name)
    return match.group(0)


class WarpEnableTests(unittest.TestCase):
    def run_warp(self, scenario, ip="172.17.0.2"):
        with tempfile.TemporaryDirectory() as directory:
            command_log = Path(directory) / "docker-calls.txt"
            shell = r"""
set -u
WARP_DIR=/tmp/test-only-warp-directory
I18N_DATA='{"docker":{"warp":{"enable":{"start":"starting","success":"IP ${container_ip}"},"build":{"fail":"build failed"}}}}'
print_info() { :; }
print_error() { printf '%s\n' "$*" >&2; exit 1; }
mkdir() { :; }
sleep() { :; }
docker() {
    printf '%s\n' "$1" >> "$MOCK_COMMAND_LOG"
    case "$1" in
        container)
            [[ "$2" == inspect ]] || return 3
            [[ "$MOCK_SCENARIO" != new ]]
            ;;
        inspect)
            case "$2" in
                *State.Status*) printf '%s\n' "${MOCK_STATUS:-running}" ;;
                *State.Running*) printf 'true\n' ;;
                *NetworkSettings.Networks*) printf '%s\n' "$MOCK_IP" ;;
                *) return 3 ;;
            esac
            ;;
        start) MOCK_STATUS=running ;;
        run) : ;;
        logs) printf '%s\n' 'mock Docker diagnostic' ;;
        *) return 4 ;;
    esac
}
"""
            shell += "\n" + extract_function(DOCKER_TEXT, "get_container_ip")
            shell += "\n" + extract_function(DOCKER_TEXT, "enable_warp")
            shell += "\nenable_warp\n"
            result = subprocess.run(
                ["bash", "-c", shell],
                capture_output=True,
                text=True,
                env={
                    **os.environ,
                    "MOCK_SCENARIO": scenario,
                    "MOCK_STATUS": "exited" if scenario == "stopped" else "running",
                    "MOCK_IP": ip,
                    "MOCK_COMMAND_LOG": str(command_log),
                },
                timeout=10,
            )
            calls = command_log.read_text().splitlines() if command_log.exists() else []
            return result, calls

    def test_running_container_returns_ip_without_recreating(self):
        result, calls = self.run_warp("running")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "172.17.0.2")
        self.assertNotIn("run", calls)
        self.assertNotIn("start", calls)

    def test_new_container_returns_ip(self):
        result, calls = self.run_warp("new")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "172.17.0.2")
        self.assertIn("run", calls)

    def test_stopped_container_is_restarted_not_recreated(self):
        result, calls = self.run_warp("stopped")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "172.17.0.2")
        self.assertIn("start", calls)
        self.assertNotIn("run", calls)

    def test_missing_container_ip_is_actionable_error(self):
        result, calls = self.run_warp("running", ip="")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(result.stdout.strip())
        self.assertIn("no running IPv4 address", result.stderr)
        self.assertIn("mock Docker diagnostic", result.stderr)
        self.assertNotIn("run", calls)

    def test_invalid_network_address_does_not_enter_xray_config(self):
        result, _ = self.run_warp("running", ip="172.17.0.2fd00::2")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(result.stdout.strip())

    def test_failure_cleanup_must_not_delete_existing_registration(self):
        fn = extract_function(HANDLER_TEXT, "handler_warp")
        self.assertIn("if ! docker container inspect xray-script-warp", fn)
        self.assertIn("trap 'docker rm -f xray-script-warp", fn)
        self.assertNotIn("trap 'bash \"${DOCKER_PATH}\" --disable-warp", fn)


if __name__ == "__main__":
    unittest.main()
