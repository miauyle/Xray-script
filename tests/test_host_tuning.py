"""Host tuning integration tests with mocked OS commands (never alter real kernel)."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "core" / "host_tuning.sh"

HARNESS = r'''
set -u
source "SOURCE_SCRIPT"
host_root() { return 0; }
MOCK_CT_NOW=7680
MOCK_CT_COUNT=212
MOCK_FW_RULE=""
MOCK_FW_OPEN_COUNT=0
MOCK_SWAPPED=0
sysctl() {
    case "$1" in
    -n)
        case "$2" in
        net.netfilter.nf_conntrack_max) echo "$MOCK_CT_NOW" ;;
        net.netfilter.nf_conntrack_count) echo "$MOCK_CT_COUNT" ;;
        *) return 1 ;;
        esac ;;
    -w)
        case "$2" in
        net.netfilter.nf_conntrack_max=*) MOCK_CT_NOW="@{2#*=}"; echo "$2" ;;
        *) return 1 ;;
        esac ;;
    *) return 1 ;;
    esac
}
iptables() {
    if [[ "$1" == -S && "$2" == INPUT ]]; then
        echo "-P INPUT DROP"
        echo "-A INPUT -j REJECT"
        return 0
    fi
    if [[ "$1" == -C ]]; then
        [[ "$MOCK_FW_RULE" == managed ]]
        return $?
    fi
    if [[ "$1" == -w && "$3" == -I ]]; then
        MOCK_FW_RULE=managed
        MOCK_FW_OPEN_COUNT=$((MOCK_FW_OPEN_COUNT+1))
        return 0
    fi
    return 1
}
systemctl() { return 0; }
modprobe() { return 0; }
mkswap() { return 0; }
fallocate() { printf 'mock-swap' >"@{@: -1}"; }
swapon() {
    if [[ "@{1:-}" == --show ]]; then echo "NAME TYPE SIZE USED PRIO"
    else MOCK_SWAPPED=1; fi
}
swapoff() { MOCK_SWAPPED=0; }
host_swap_active() { [[ "$MOCK_SWAPPED" == 1 ]]; }
free() { echo "Mock free"; }
'''

class HostTuningTests(unittest.TestCase):
    def run_case(self, commands):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            for name in ("systemd", "sysctl", "modules"):
                (root / name).mkdir()
            (root / "fstab").write_text("# fstab\nUUID=foo / ext4 defaults 0 1\n")
            env = dict(os.environ,
                HOST_FW_HOME=str(root / "fw"),
                HOST_FW_PORTS=str(root / "fw" / "ports"),
                HOST_FW_RESTORE=str(root / "fw" / "restore.sh"),
                HOST_FW_UNIT=str(root / "systemd" / "firewall.service"),
                HOST_CT_CONF=str(root / "sysctl" / "99-z-xray-script-conntrack.conf"),
                HOST_CT_MODULE=str(root / "modules" / "nf_conntrack.conf"),
                HOST_CT_BACKUP=str(root / "backup" / "previous"),
                HOST_SWAP_FILE=str(root / "swap" / "swapfile"),
                HOST_FSTAB=str(root / "fstab"),
            )
            script = HARNESS.replace("SOURCE_SCRIPT", str(SOURCE)).replace("@{", "$" + "{") + "\n" + commands
            return subprocess.run(["bash", "-c", script], text=True, capture_output=True,
                                  cwd=ROOT, env=env, timeout=20)

    def check(self, commands):
        r = self.run_case(commands)
        self.assertEqual(r.returncode, 0, r.stderr + "\n" + r.stdout)

    def test_conntrack_verify_persist_restore(self):
        self.check(r'''
host_ct_set 16384 || exit 10
[[ "$MOCK_CT_NOW" == 16384 ]] || exit 11
grep -qx 'net.netfilter.nf_conntrack_max = 16384' "$HOST_CT_CONF" || exit 12
grep -qx 'nf_conntrack' "$HOST_CT_MODULE" || exit 13
host_ct_set 32768 || exit 14
grep -qx '7680' "$HOST_CT_BACKUP" || exit 15
host_ct_restore || exit 16
[[ "$MOCK_CT_NOW" == 7680 ]] || exit 17
[[ ! -e "$HOST_CT_CONF" ]] || exit 18
''')

    def test_conntrack_refuses_unsafe_values_and_unmanaged_file(self):
        self.check(r'''
MOCK_CT_COUNT=9000
if host_ct_set 7680; then exit 10; fi
if host_ct_set '16384;rm -rf /'; then exit 11; fi
printf 'unmanaged\n' > "$HOST_CT_CONF"
if host_ct_set 16384; then exit 12; fi
grep -qx unmanaged "$HOST_CT_CONF" || exit 13
''')

    def test_iptables_check_write_idempotent_and_persistent(self):
        self.check(r'''
if host_fw_status 443 tcp; then exit 10; fi
[[ "$MOCK_FW_OPEN_COUNT" == 0 ]] || exit 11
host_fw_open 443 tcp || exit 12
[[ "$MOCK_FW_OPEN_COUNT" == 1 ]] || exit 13
host_fw_status 443 tcp || exit 14
grep -qx tcp:443 "$HOST_FW_PORTS" || exit 15
grep -q 'WantedBy=multi-user.target' "$HOST_FW_UNIT" || exit 16
host_fw_open 443 tcp || exit 17
[[ "$MOCK_FW_OPEN_COUNT" == 1 ]] || exit 18
[[ "$(grep -c '^tcp:443$' "$HOST_FW_PORTS")" == 1 ]] || exit 19
''')

    def test_firewall_denies_injection(self):
        self.check(r'''
for v in 0 65536 '-1' '443;iptables -F'; do
    if host_fw_open "$v" tcp; then exit 10; fi
done
if host_fw_open 443 'tcp;DROP'; then exit 11; fi
[[ "$MOCK_FW_OPEN_COUNT" == 0 ]] || exit 12
''')

    def test_xray_port_auto_detection_tcp_udp_ignores_loopback_and_uds(self):
        self.check(r'''
XRAY_CONFIG='{"inbounds":[
 {"listen":"127.0.0.1","port":32768},
 {"listen":"0.0.0.0","port":443,"streamSettings":{"network":"tcp"}},
 {"listen":"0.0.0.0","port":26700,"streamSettings":{"network":"kcp"}},
 {"listen":"@uds2xhttp.sock","streamSettings":{"network":"xhttp"}}
]}'
called=""
host_fw_offer() { called+="$1/$2 "; }
host_fw_offer_xray || exit 10
[[ "$called" == '26700/udp 443/tcp ' ]] || { echo "$called"; exit 11; }
''')

    def test_swap_create_one_gib_and_remove(self):
        self.check(r'''
host_swap_add 1 || exit 10
[[ "$MOCK_SWAPPED" == 1 && -f "$HOST_SWAP_FILE" ]] || exit 11
[[ "$(stat -c %a "$HOST_SWAP_FILE")" == 600 ]] || exit 12
grep -Fqx "$HOST_SWAP_FILE none swap sw 0 0 $HOST_SWAP_MARKER" "$HOST_FSTAB" || exit 13
host_swap_remove || exit 14
[[ "$MOCK_SWAPPED" == 0 && ! -e "$HOST_SWAP_FILE" ]] || exit 15
[[ "$(wc -l < "$HOST_FSTAB")" == 2 ]] || exit 16
''')

    def test_swap_rejects_unsafe_size_and_existing_path(self):
        self.check(r'''
for s in 0 -1 33 1.5 ';echo exploit'; do
    if host_swap_add "$s"; then exit 10; fi
done
mkdir -p "$(dirname "$HOST_SWAP_FILE")"
echo existing >"$HOST_SWAP_FILE"
if host_swap_add 2; then exit 11; fi
grep -qx existing "$HOST_SWAP_FILE" || exit 12
if host_swap_remove; then exit 13; fi
''')

if __name__ == "__main__":
    unittest.main()
