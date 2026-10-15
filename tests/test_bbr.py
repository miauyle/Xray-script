"""Safe, unprivileged regression tests for Xray-script BBR management."""
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

HARNESS = r"""
set -u
source "CORE_BBR_SCRIPT"
bbr_require_root() { return 0; }
MOCK_CC="cubic"
MOCK_QDISC="fq_codel"
MOCK_AVAILABLE="reno cubic"
MOCK_ALLOW_BBR=1
MOCK_FAIL_BBR=0
sysctl() {
    case "$1" in
    -n)
        case "$2" in
        net.ipv4.tcp_congestion_control) printf '%s\n' "$MOCK_CC" ;;
        net.core.default_qdisc) printf '%s\n' "$MOCK_QDISC" ;;
        net.ipv4.tcp_available_congestion_control) printf '%s\n' "$MOCK_AVAILABLE" ;;
        *) return 1 ;;
        esac ;;
    -w)
        case "$2" in
        net.ipv4.tcp_congestion_control=*)
            if [[ "$2" == *=bbr && "$MOCK_FAIL_BBR" == 1 ]]; then return 1; fi
            MOCK_CC="${2#*=}" ;;
        net.core.default_qdisc=*) MOCK_QDISC="${2#*=}" ;;
        *) return 1 ;;
        esac ;;
    *) return 1 ;;
    esac
}
modprobe() {
    if [[ "$MOCK_ALLOW_BBR" == 1 && "$1" == tcp_bbr ]]; then
        MOCK_AVAILABLE="reno cubic bbr"
        return 0
    fi
    return 1
}
"""


class BbrManagementTests(unittest.TestCase):
    def run_case(self, commands):
        with tempfile.TemporaryDirectory() as root:
            root = Path(root)
            conf_dir = root / "etc" / "sysctl.d"
            conf_dir.mkdir(parents=True)
            config = conf_dir / "99-xray-script-bbr.conf"
            state = root / "state" / "bbr-original.conf"
            harness = HARNESS.replace("CORE_BBR_SCRIPT", str(ROOT / "core" / "bbr.sh"))
            commands = commands.replace("@CONF@", str(config)).replace("@STATE@", str(state))
            env = dict(os.environ, BBR_CONF_PATH=str(config), BBR_STATE_PATH=str(state))
            return subprocess.run(
                ["bash", "-c", harness + "\n" + commands],
                cwd=ROOT, env=env, text=True, capture_output=True, timeout=12
            )

    def test_enable_idempotent_restore(self):
        result = self.run_case(r"""
bbr_enable || exit 10
[[ "$MOCK_CC" == bbr && "$MOCK_QDISC" == fq ]] || exit 11
[[ -f "@CONF@" && -f "@STATE@" ]] || exit 12
grep -qx 'cc=cubic' "@STATE@" || exit 13
grep -qx 'qdisc=fq_codel' "@STATE@" || exit 14
grep -qx 'net.ipv4.tcp_congestion_control = bbr' "@CONF@" || exit 15
[[ "$(stat -c %a "@STATE@")" == 600 ]] || exit 16
bbr_enable || exit 17
bbr_restore || exit 18
[[ "$MOCK_CC" == cubic && "$MOCK_QDISC" == fq_codel ]] || exit 19
[[ ! -e "@CONF@" && ! -e "@STATE@" ]] || exit 20
bbr_restore || exit 21
""")
        self.assertEqual(result.returncode, 0, result.stderr + "\n" + result.stdout)

    def test_unsupported_kernel_is_noop(self):
        result = self.run_case(r"""
MOCK_ALLOW_BBR=0
if bbr_enable; then exit 10; fi
[[ "$MOCK_CC" == cubic && "$MOCK_QDISC" == fq_codel ]] || exit 11
[[ ! -e "@CONF@" && ! -e "@STATE@" ]] || exit 12
""")
        self.assertEqual(result.returncode, 0, result.stderr + "\n" + result.stdout)

    def test_existing_file_not_overwritten(self):
        result = self.run_case(r"""
echo 'net.ipv4.tcp_congestion_control = reno' > "@CONF@"
if bbr_enable; then exit 10; fi
grep -qx 'net.ipv4.tcp_congestion_control = reno' "@CONF@" || exit 11
[[ ! -e "@STATE@" ]] || exit 12
if bbr_restore; then exit 13; fi
""")
        self.assertEqual(result.returncode, 0, result.stderr + "\n" + result.stdout)

    def test_failed_runtime_apply_rolls_back(self):
        result = self.run_case(r"""
MOCK_FAIL_BBR=1
if bbr_enable; then exit 10; fi
[[ "$MOCK_CC" == cubic && "$MOCK_QDISC" == fq_codel ]] || exit 11
[[ ! -e "@CONF@" && ! -e "@STATE@" ]] || exit 12
""")
        self.assertEqual(result.returncode, 0, result.stderr + "\n" + result.stdout)

    def test_orphaned_backup_blocks_changes(self):
        result = self.run_case(r"""
mkdir -p "$(dirname "@STATE@")"
printf '# Xray-script BBR original values v1\ncc=reno\nqdisc=fq_codel\n' > "@STATE@"
if bbr_enable; then exit 10; fi
[[ ! -e "@CONF@" ]] || exit 11
grep -qx 'cc=reno' "@STATE@" || exit 12
""")
        self.assertEqual(result.returncode, 0, result.stderr + "\n" + result.stdout)

    def test_missing_backup_blocks_restore(self):
        result = self.run_case(r"""
printf '# Managed by Xray-script: TCP BBR v1\nnet.core.default_qdisc = fq\n' > "@CONF@"
if bbr_restore; then exit 10; fi
[[ -f "@CONF@" && ! -f "@STATE@" ]] || exit 11
""")
        self.assertEqual(result.returncode, 0, result.stderr + "\n" + result.stdout)

    def test_status_read_only(self):
        result = self.run_case(r"""
bbr_status || exit 10
[[ "$MOCK_CC" == cubic && "$MOCK_QDISC" == fq_codel ]] || exit 11
[[ ! -e "@CONF@" && ! -e "@STATE@" ]] || exit 12
""")
        self.assertEqual(result.returncode, 0, result.stderr + "\n" + result.stdout)
        self.assertIn("TCP congestion control: cubic", result.stdout)


if __name__ == "__main__":
    unittest.main()
