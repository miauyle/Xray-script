#!/usr/bin/env bash
# Optional host-level tuning. Sourced by handler.sh and clash.sh.
# All mutations are opt-in; Ubuntu/OCI iptables, conntrack and swap are scoped.
HOST_FW_HOME="${HOST_FW_HOME:-/etc/xray-script}"
HOST_FW_PORTS="${HOST_FW_PORTS:-${HOST_FW_HOME}/firewall-ports.conf}"
HOST_FW_RESTORE="${HOST_FW_RESTORE:-${HOST_FW_HOME}/firewall-restore.sh}"
HOST_FW_UNIT="${HOST_FW_UNIT:-/etc/systemd/system/xray-script-firewall.service}"
HOST_CT_CONF="${HOST_CT_CONF:-/etc/sysctl.d/99-z-xray-script-conntrack.conf}"
HOST_CT_MODULE="${HOST_CT_MODULE:-/etc/modules-load.d/xray-script-conntrack.conf}"
HOST_CT_BACKUP="${HOST_CT_BACKUP:-${HOME}/.xray-script/network/conntrack-original}"
HOST_SWAP_FILE="${HOST_SWAP_FILE:-/var/lib/xray-script/swapfile}"
HOST_FSTAB="${HOST_FSTAB:-/etc/fstab}"
HOST_CT_SIGNATURE="# Xray-script nf_conntrack_max v1"
HOST_SWAP_MARKER="# xray-script-managed-swap"

host_message() { printf '%s\n' "$*" >&2; }
host_fail() { host_message "ERROR: $*"; return 1; }
host_root() { (( EUID == 0 )) || host_fail "Root access required."; }
host_is_port() { [[ "$1" =~ ^[0-9]{1,5}$ ]] && ((10#$1 > 0 && 10#$1 <= 65535)); }
host_is_proto() { [[ "$1" == tcp || "$1" == udp ]]; }
host_valid_rule() { host_is_port "$1" && host_is_proto "$2"; }

host_fw_backend() {
    if command -v ufw >/dev/null 2>&1 &&
            LC_ALL=C ufw status 2>/dev/null | grep -q '^Status: active'; then
        printf 'ufw'
    elif command -v iptables >/dev/null 2>&1 && iptables -S INPUT >/dev/null 2>&1; then
        printf 'iptables'
    else
        printf 'none'
    fi
}
host_fw_owned() {
    iptables -C INPUT -p "$2" --dport "$1" -m comment --comment XRAY-SCRIPT -j ACCEPT >/dev/null 2>&1
}
# Conservative INPUT-chain ordering check: an ACCEPT after a catch-all
# REJECT/DROP must never be treated as an open port (common on OCI images).
host_fw_rule_reachable() {
    local port="$1" proto="$2" rules="$3" line
    while IFS= read -r line; do
        [[ "$line" == '-A INPUT '* ]] || continue
        # Ignore rules that explicitly reference another port/protocol.
        if [[ "$line" == *" --dport "* && "$line" != *" --dport $port "* ]]; then
            continue
        fi
        if [[ "$line" == *" -p tcp "* && "$proto" != tcp ||
              "$line" == *" -p udp "* && "$proto" != udp ]]; then
            continue
        fi
        # A matching (or unconditional) drop/reject first wins.
        if [[ "$line" == *" -j REJECT"* || "$line" == *" -j DROP"* ]]; then
            return 1
        fi
        # Only unqualified port-specific ACCEPT is safely recognizable.
        if [[ "$line" == *" -p $proto "* && "$line" == *" --dport $port "* &&
              "$line" == *" -j ACCEPT"* ]]; then
            return 0
        fi
    done <<<"$rules"
    return 1
}

host_fw_status() {
    local port="$1" proto="${2:-tcp}" backend rules policy
    host_valid_rule "$port" "$proto" || { host_fail "Invalid port/protocol."; return 2; }
    backend="$(host_fw_backend)"
    case "$backend" in
    ufw)
        if LC_ALL=C ufw status 2>/dev/null | awk -v p="$port/$proto" '
            $1==p && $0~/ALLOW/ {found=1} END {exit !found}
        '; then
            host_message "Host UFW: allow rule exists for $port/$proto (not a remote connectivity test)."
            return 0
        fi
        host_message "Host UFW: no verified allow rule for $port/$proto."
        return 1 ;;
    iptables)
        rules="$(iptables -S INPUT 2>/dev/null)" || return 2
        # -C alone is insufficient: a rule appended after an OCI catch-all
        # REJECT is present but ineffective.
        if host_fw_rule_reachable "$port" "$proto" "$rules"; then
            host_message "Host iptables: early ACCEPT found for $port/$proto (cloud ingress still separate)."
            return 0
        fi
        policy="$(printf '%s\n' "$rules" | sed -n 's/^-P INPUT //p' | head -n1)"
        if [[ "$policy" == ACCEPT ]] &&
           ! printf '%s\n' "$rules" | grep -Eq -- ' -j (DROP|REJECT|[A-Z_-]*INPUT[A-Z_-]*|ufw-)| --jump (DROP|REJECT)' &&
           ! printf '%s\n' "$rules" | grep -Eq -- '^-A INPUT .* -j '; then
            host_message "Host iptables: INPUT policy ACCEPT without filtering rules."
            return 0
        fi
        host_message "Host iptables: $port/$proto is not verified open (may be blocked by INPUT rules)."
        return 1 ;;
    *)
        host_message "Host firewall: unsupported/undetectable backend (nft-only or no iptables). No auto changes."
        return 2 ;;
    esac
}

# Persist only Xray-script-created ACCEPT rules. Never replace /etc/iptables/rules.v4
# or flush INPUT, which could break the SSH session on an OCI VPS.
host_fw_persist() {
    local port="$1" proto="$2" tmp
    mkdir -p "$HOST_FW_HOME" || return 1
    chmod 700 "$HOST_FW_HOME" || return 1
    touch "$HOST_FW_PORTS" || return 1
    chmod 600 "$HOST_FW_PORTS" || return 1
    if ! grep -qx "$proto:$port" "$HOST_FW_PORTS"; then
        printf '%s:%s\n' "$proto" "$port" >>"$HOST_FW_PORTS" || return 1
    fi
    cat >"$HOST_FW_RESTORE" <<'EOF_HOST_FIREWALL'
#!/usr/bin/env bash
set -e
export PATH=/usr/sbin:/sbin:/usr/bin:/bin
while IFS=: read -r proto port; do
    [[ "$proto" == tcp || "$proto" == udp ]] || continue
    [[ "$port" =~ ^[0-9]{1,5}$ ]] || continue
    ((10#$port >= 1 && 10#$port <= 65535)) || continue
    iptables -w 5 -C INPUT -p "$proto" --dport "$port" -m comment --comment XRAY-SCRIPT -j ACCEPT 2>/dev/null ||
        iptables -w 5 -I INPUT 1 -p "$proto" --dport "$port" -m comment --comment XRAY-SCRIPT -j ACCEPT
done <"${HOST_FW_PORTS:-/etc/xray-script/firewall-ports.conf}"
EOF_HOST_FIREWALL
    chmod 700 "$HOST_FW_RESTORE" || return 1
    cat >"$HOST_FW_UNIT" <<'EOF_HOST_FW_SERVICE'
[Unit]
Description=Reapply explicit Xray-script host firewall port approvals
After=netfilter-persistent.service ufw.service
Before=xray.service xray-clash-subscription.service

[Service]
Type=oneshot
ExecStart=/bin/bash /etc/xray-script/firewall-restore.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF_HOST_FW_SERVICE
    systemctl daemon-reload && systemctl enable xray-script-firewall.service >/dev/null
}

host_fw_open() {
    local port="$1" proto="${2:-tcp}" backend
    host_root || return 1
    host_valid_rule "$port" "$proto" || return 1
    backend="$(host_fw_backend)"
    if [[ "$backend" == ufw ]]; then
        if ! ufw allow "$port/$proto" comment 'Xray-script' >/dev/null; then
            host_fail "UFW could not add rule"; return 1
        fi
        host_fw_status "$port" "$proto"
        return $?
    elif [[ "$backend" == iptables ]]; then
        # Reposition only our own rule if a preceding REJECT/DROP masks it.
        # Never touch unrelated system or SSH rules.
        if host_fw_owned "$port" "$proto"; then
            if ! host_fw_rule_reachable "$port" "$proto" "$(iptables -S INPUT)"; then
                iptables -w 5 -D INPUT -p "$proto" --dport "$port" -m comment --comment XRAY-SCRIPT -j ACCEPT ||
                    return 1
                iptables -w 5 -I INPUT 1 -p "$proto" --dport "$port" -m comment --comment XRAY-SCRIPT -j ACCEPT ||
                    return 1
            fi
        else
            iptables -w 5 -I INPUT 1 -p "$proto" --dport "$port" -m comment --comment XRAY-SCRIPT -j ACCEPT ||
                return 1
        fi
        if ! host_fw_persist "$port" "$proto"; then
            host_fail "Firewall rule added now but persistence FAILED; inspect systemd/iptables settings."
            return 1
        fi
        host_fw_owned "$port" "$proto" || { host_fail "iptables verification failed"; return 1; }
        host_message "Host iptables: $port/$proto ACCEPT is active and configured to restore on reboot."
        return 0
    fi
    host_fail "Unsupported firewall; no changes made."
}
host_fw_offer() {
    local port="$1" proto="${2:-tcp}" reply="" rc=0
    host_fw_status "$port" "$proto" || rc=$?
    [[ "$rc" -eq 0 ]] && return 0
    if [[ "$rc" -ne 1 ]]; then
        host_message "Please configure your host firewall manually; OCI Security List/NSG is separate."
        return 0
    fi
    host_message "About to listen on $port/$proto. The local firewall has no verified allow rule."
    host_message "This opens the port to ALL IPv4 sources. Oracle Cloud Security List/NSG still needs an ingress rule."
    if [[ -r /dev/tty ]]; then
        printf 'Open host firewall for %s/%s? [y/N] ' "$port" "$proto" >/dev/tty
        IFS= read -r reply </dev/tty || reply=""
    else
        host_message "No interactive TTY; leaving the firewall unchanged."
    fi
    if [[ "$reply" == [yY] || "$reply" == [yY][eE][sS] ]]; then
        host_fw_open "$port" "$proto" ||
            host_message "WARNING: Could not automatically open/persist the port. Check firewall manually."
    else
        host_message "Declined; local firewall unchanged. External connections may fail."
    fi
    return 0
}
host_fw_offer_xray() {
    local port proto
    # Only candidate non-loopback IP listening sockets, never UDS or API.
    while read -r port proto; do
        [[ -n "$port" ]] || continue
        host_fw_offer "$port" "$proto"
    done < <(printf '%s\n' "$XRAY_CONFIG" | jq -r '
        .inbounds[]? |
        select(.port | type == "number") |
        select((.listen // "0.0.0.0") != "127.0.0.1" and
               (.listen // "0.0.0.0") != "::1") |
        [(.port|tostring), (if .streamSettings.network == "kcp" or
                                .streamSettings.network == "quic" then "udp"
                            else "tcp" end)] | join(" ")
    ' 2>/dev/null | sort -u)
}

host_ct_status() {
    local max count
    max="$(sysctl -n net.netfilter.nf_conntrack_max 2>/dev/null)" || {
        host_message "nf_conntrack_max not available (try modprobe nf_conntrack)."; return 1;
    }
    count="$(sysctl -n net.netfilter.nf_conntrack_count 2>/dev/null || echo unknown)"
    host_message "nf_conntrack_count=$count  nf_conntrack_max=$max"
    if [[ -f "$HOST_CT_CONF" ]]; then
        host_message "Xray-script persistent setting: $(sed -n 's/^net.netfilter.nf_conntrack_max = //p' "$HOST_CT_CONF")"
    else
        host_message "Xray-script persistence: not configured"
    fi
}
host_ct_set() {
    local value="$1" previous count state_dir conf_dir staged
    host_root || return 1
    [[ "$value" =~ ^[0-9]{4,7}$ ]] && ((10#$value >= 1024 && 10#$value <= 1048576)) ||
        { host_fail "Expected conntrack_max between 1024 and 1048576."; return 1; }
    if ! sysctl -n net.netfilter.nf_conntrack_max >/dev/null 2>&1; then
        command -v modprobe >/dev/null && modprobe nf_conntrack >/dev/null 2>&1 || true
    fi
    previous="$(sysctl -n net.netfilter.nf_conntrack_max 2>/dev/null)" ||
        { host_fail "Kernel does not expose nf_conntrack_max."; return 1; }
    count="$(sysctl -n net.netfilter.nf_conntrack_count 2>/dev/null || echo 0)"
    [[ "$count" =~ ^[0-9]+$ ]] || count=0
    ((10#$value >= count)) || { host_fail "Requested max is below active conntrack_count."; return 1; }
    if [[ -e "$HOST_CT_CONF" ]] &&
       [[ "$(head -n1 "$HOST_CT_CONF")" != "$HOST_CT_SIGNATURE" ]]; then
        host_fail "Refusing to overwrite an unmanaged conntrack sysctl file."; return 1
    fi
    if [[ ! -e "$HOST_CT_BACKUP" ]]; then
        state_dir="$(dirname "$HOST_CT_BACKUP")"
        mkdir -p "$state_dir" || return 1
        chmod 700 "$state_dir" || return 1
        printf '%s\n' "$previous" >"$HOST_CT_BACKUP" || return 1
        chmod 600 "$HOST_CT_BACKUP" || return 1
    fi
    if [[ -e "$HOST_CT_MODULE" ]] &&
       [[ "$(head -n1 "$HOST_CT_MODULE")" != '# Xray-script nf_conntrack module' ]]; then
        host_fail "Unmanaged module-load configuration at $HOST_CT_MODULE."; return 1
    fi
    if ! sysctl -w "net.netfilter.nf_conntrack_max=$value" >/dev/null 2>&1 ||
        [[ "$(sysctl -n net.netfilter.nf_conntrack_max 2>/dev/null)" != "$value" ]]; then
        sysctl -w "net.netfilter.nf_conntrack_max=$previous" >/dev/null 2>&1 || true
        host_fail "Kernel rejected conntrack_max; runtime restored if possible."
        return 1
    fi
    conf_dir="$(dirname "$HOST_CT_CONF")"
    mkdir -p "$conf_dir" || return 1
    staged="$(mktemp "$conf_dir/.xray-conntrack.XXXXXXXX")" || return 1
    printf '%s\nnet.netfilter.nf_conntrack_max = %s\n' "$HOST_CT_SIGNATURE" "$value" >"$staged"
    chmod 644 "$staged" && mv -f "$staged" "$HOST_CT_CONF" || return 1
    printf '# Xray-script nf_conntrack module\nnf_conntrack\n' >"$HOST_CT_MODULE" || return 1
    chmod 644 "$HOST_CT_MODULE" || return 1
    host_message "conntrack_max=$value applied and persisted. Check after reboot: sysctl net.netfilter.nf_conntrack_max"
    host_ct_status
}
host_ct_restore() {
    local previous count
    host_root || return 1
    [[ -f "$HOST_CT_CONF" ]] &&
        [[ "$(head -n1 "$HOST_CT_CONF")" == "$HOST_CT_SIGNATURE" ]] &&
        [[ -f "$HOST_CT_BACKUP" ]] || { host_fail "No complete Xray-script conntrack backup."; return 1; }
    previous="$(cat "$HOST_CT_BACKUP")"
    [[ "$previous" =~ ^[0-9]+$ ]] || return 1
    count="$(sysctl -n net.netfilter.nf_conntrack_count 2>/dev/null || echo 0)"
    ((previous >= count)) || { host_fail "Original max below active conntrack_count."; return 1; }
    sysctl -w "net.netfilter.nf_conntrack_max=$previous" >/dev/null 2>&1 || return 1
    [[ "$(sysctl -n net.netfilter.nf_conntrack_max)" == "$previous" ]] || return 1
    rm -f "$HOST_CT_CONF" "$HOST_CT_BACKUP"
    if [[ -f "$HOST_CT_MODULE" &&
          "$(head -n1 "$HOST_CT_MODULE")" == '# Xray-script nf_conntrack module' ]]; then
        rm -f "$HOST_CT_MODULE"
    fi
    host_ct_status
}

host_swap_active() {
    awk -v file="$HOST_SWAP_FILE" 'NR>1 && $1==file {found=1} END {exit !found}' /proc/swaps
}
host_swap_status() {
    host_message "Memory / swap:"
    free -h >&2 || true
    swapon --show >&2 || true
    if [[ -e "$HOST_SWAP_FILE" ]]; then
        host_message "Xray-script swap file: $HOST_SWAP_FILE"
    else
        host_message "Xray-script swap file: none"
    fi
}
host_swap_add() {
    local gib="$1" bytes avail fstype dir tmp
    host_root || return 1
    [[ "$gib" =~ ^[1-9][0-9]?$ ]] && ((10#$gib <= 32)) ||
        { host_fail "Specify integer GiB from 1 to 32."; return 1; }
    [[ ! -e "$HOST_SWAP_FILE" && ! -L "$HOST_SWAP_FILE" ]] ||
        { host_fail "Managed swap target already exists; refusing to overwrite."; return 1; }
    dir="$(dirname "$HOST_SWAP_FILE")"
    mkdir -p "$dir" && chmod 700 "$dir" || return 1
    fstype="$(stat -f -c %T "$dir" 2>/dev/null || true)"
    [[ "$fstype" != btrfs ]] ||
        { host_fail "Btrfs swapfiles require specific no-COW preparation; operation refused."; return 1; }
    bytes=$((gib * 1024 * 1024 * 1024))
    avail="$(df -B1 --output=avail "$dir" | tail -n1 | tr -d '[:space:]')"
    [[ "$avail" =~ ^[0-9]+$ ]] && ((avail > bytes + 268435456)) ||
        { host_fail "Not enough free disk space: need requested size plus 256 MiB."; return 1; }
    if grep -Fq "$HOST_SWAP_FILE" "$HOST_FSTAB"; then
        host_fail "Swap path already present in fstab; refusing to change."; return 1
    fi
    tmp="$(mktemp "$dir/.swap-new.XXXXXXXX")" || return 1
    chmod 600 "$tmp" || { rm -f "$tmp"; return 1; }
    if ! fallocate -l "$bytes" "$tmp" ||
       ! mkswap "$tmp" >/dev/null ||
       ! mv "$tmp" "$HOST_SWAP_FILE" ||
       ! swapon "$HOST_SWAP_FILE" ||
       ! host_swap_active; then
        swapoff "$HOST_SWAP_FILE" >/dev/null 2>&1 || true
        rm -f "$tmp" "$HOST_SWAP_FILE"
        host_fail "Swap allocation/activation failed; partial files removed."
        return 1
    fi
    if ! printf '%s none swap sw 0 0 %s\n' "$HOST_SWAP_FILE" "$HOST_SWAP_MARKER" >>"$HOST_FSTAB"; then
        swapoff "$HOST_SWAP_FILE" >/dev/null 2>&1 || true
        rm -f "$HOST_SWAP_FILE"
        host_fail "Could not persist swap in fstab."
        return 1
    fi
    host_message "Added $gib GiB swap and persisted in fstab at $HOST_SWAP_FILE."
    host_swap_status
}
host_swap_remove() {
    local tmp used available
    host_root || return 1
    [[ -f "$HOST_SWAP_FILE" && ! -L "$HOST_SWAP_FILE" ]] ||
        { host_fail "No Xray-script swapfile."; return 1; }
    grep -Fq "$HOST_SWAP_FILE none swap sw 0 0 $HOST_SWAP_MARKER" "$HOST_FSTAB" ||
        { host_fail "Missing managed fstab marker; refusing to remove."; return 1; }
    if host_swap_active; then
        used="$(awk -v file="$HOST_SWAP_FILE" 'NR>1 && $1==file {print $4*1024; exit}' /proc/swaps)"
        available="$(awk '/^MemAvailable:/{print $2*1024; exit}' /proc/meminfo)"
        if [[ "$used" =~ ^[0-9]+$ && "$available" =~ ^[0-9]+$ ]] && ((used > available)); then
            host_fail "Swap in use exceeds available RAM; refusing risky swapoff."
            return 1
        fi
        swapoff "$HOST_SWAP_FILE" || { host_fail "swapoff failed; swap is unchanged."; return 1; }
    fi
    tmp="$(mktemp "$(dirname "$HOST_FSTAB")/.xray-fstab.XXXXXXXX")" || return 1
    awk -v line="$HOST_SWAP_FILE none swap sw 0 0 $HOST_SWAP_MARKER" '$0 != line' "$HOST_FSTAB" >"$tmp" ||
        { rm -f "$tmp"; return 1; }
    chmod --reference="$HOST_FSTAB" "$tmp" 2>/dev/null || true
    chown --reference="$HOST_FSTAB" "$tmp" 2>/dev/null || true
    mv "$tmp" "$HOST_FSTAB" || return 1
    rm -f "$HOST_SWAP_FILE"
    host_message "Removed only Xray-script-managed swap. Existing system swap is untouched."
}

host_tuning_main() {
    local category="${1:-}" cmd="${2:-}" value="${3:-}"
    case "$category:$cmd" in
    firewall:status) host_fw_status "$value" "${4:-tcp}" ;;
    firewall:open) host_fw_offer "$value" "${4:-tcp}" ;;
    conntrack:status) host_ct_status ;;
    conntrack:set) host_ct_set "$value" ;;
    conntrack:restore) host_ct_restore ;;
    swap:status) host_swap_status ;;
    swap:add) host_swap_add "$value" ;;
    swap:remove) host_swap_remove ;;
    *) host_fail "Usage: --host firewall [status|open] PORT [tcp|udp]; conntrack [status|set N|restore]; swap [status|add G|remove]" ;;
    esac
}
