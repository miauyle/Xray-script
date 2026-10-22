"""Tests for Cloudflare WARP container NET_ADMIN permission migration."""
import json, re, shlex, subprocess, tempfile, unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OPS = (ROOT / "core" / "operations.sh").read_text()
DOCKER = (ROOT / "service" / "docker.sh").read_text()

def func(name):
    found = re.search(r"(?ms)^function " + re.escape(name) + r"\(\) \{.*?^\}", OPS)
    assert found, name
    return found.group(0)

PROD = "\n".join(func(name) for name in (
    "ops_get_warp_container_ip", "ops_warp_has_net_admin",
    "ops_warp_netadmin_rollback", "handler_warp_netadmin_repair",
))

MOCK = r'''
SCRIPT_CONFIG='{"xray":{"warp":1}}'
_error() { echo "ERROR: $*" >&2; exit 1; }
docker() {
    printf 'docker %s\n' "$*" >>"$ACTION_LOG"
    local all="$*" mode=old
    [[ -f "$NEW_FLAG" ]] && mode=new
    if [[ "$all" == *".HostConfig.CapAdd"* ]]; then
        [[ "$mode" == new ]] && echo '["NET_ADMIN"]' || echo null
    elif [[ "$all" == *".State.Status"* ]]; then
        echo running
    elif [[ "$all" == *".Config.Image"* ]]; then
        echo xray-script-warp
    elif [[ "$all" == *".HostConfig.NetworkMode"* ]]; then
        echo default
    elif [[ "$all" == *".Mounts"* ]]; then
        echo "$SCRIPT_CONFIG_DIR/docker/cloudflare-warp"
    elif [[ "$all" == *".NetworkSettings.Networks"* ]]; then
        [[ "$mode" == new ]] && echo 172.17.0.3 || echo 172.17.0.2
    else
        return 0
    fi
}
exec_docker() {
    echo "exec_docker $*" >>"$ACTION_LOG"
    [[ "$FAIL_CREATE" != 1 ]] || return 1
    touch "$NEW_FLAG"
    echo 172.17.0.3
}
apply_xray_config() {
    echo "apply_xray_config $*" >>"$ACTION_LOG"
    printf '%s\n' "$XRAY_CONFIG" > "$XRAY_CONFIG_PATH"
}
handler_warp_status() { echo "status refreshed"; }
'''

def run_case(answer="yes\n", fail_create=False):
    with tempfile.TemporaryDirectory() as td:
        d = Path(td)
        path = d / "xray.json"
        path.write_text(json.dumps({"outbounds": [
            {"tag": "direct", "protocol": "freedom"},
            {"tag": "warp", "protocol": "socks",
             "settings": {"servers": [{"address": "172.17.0.2", "port": 40001}]}}
        ]}))
        log = d / "actions"
        code = "\n".join([
            "ACTION_LOG=" + shlex.quote(str(log)),
            "NEW_FLAG=" + shlex.quote(str(d / "new")),
            "SCRIPT_CONFIG_DIR=" + shlex.quote(str(d)),
            "XRAY_CONFIG_PATH=" + shlex.quote(str(path)),
            "FAIL_CREATE=" + ("1" if fail_create else "0"),
            MOCK, PROD, "handler_warp_netadmin_repair",
        ])
        result = subprocess.run(["bash", "-c", code], input=answer, text=True,
                                capture_output=True, cwd=ROOT, timeout=30)
        return result, log.read_text() if log.exists() else "", json.loads(path.read_text())

class WarpNetadminRepairTests(unittest.TestCase):
    def test_new_docker_run_grants_net_admin_not_privileged(self):
        line = next(x for x in DOCKER.splitlines() if "docker run -d" in x and "container_name" in x)
        self.assertIn("--cap-add=NET_ADMIN", line)
        self.assertNotIn("--privileged", line)

    def test_repair_cancelled_before_mutations(self):
        result, log, state = run_case("no\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Canceled", result.stdout)
        self.assertNotIn("docker stop ", log)
        self.assertEqual(state["outbounds"][1]["settings"]["servers"][0]["address"], "172.17.0.2")

    def test_repair_preserves_old_and_updates_xray_outbound(self):
        result, log, state = run_case()
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        for value in ("docker stop xray-script-warp",
                      "docker rename xray-script-warp xray-script-warp-before-netadmin-",
                      "docker update --restart=no",
                      "exec_docker --enable-warp",
                      "apply_xray_config warp:netadmin:repair restart"):
            self.assertIn(value, log)
        self.assertNotIn("docker rm -f", log)
        self.assertIn("Old backup is STOPPED", result.stdout)
        self.assertEqual(state["outbounds"][1]["settings"]["servers"][0]["address"], "172.17.0.3")

    def test_failed_creation_rolls_back_without_destroying_old(self):
        result, log, state = run_case(fail_create=True)
        self.assertNotEqual(result.returncode, 0)
        for value in ("docker rm -f xray-script-warp", "docker rename xray-script-warp-before-netadmin-",
                      "docker update --restart=always xray-script-warp",
                      "docker start xray-script-warp"):
            self.assertIn(value, log)
        self.assertEqual(state["outbounds"][1]["settings"]["servers"][0]["address"], "172.17.0.2")

if __name__ == "__main__":
    unittest.main()
