#!/usr/bin/env bash
# Optional, reversible Linux TCP BBR tuning. Sourced by core/handler.sh.
# Owns one sysctl drop-in only; never edits existing global sysctl configuration.
BBR_CONF_PATH="${BBR_CONF_PATH:-/etc/sysctl.d/99-xray-script-bbr.conf}"
BBR_STATE_PATH="${BBR_STATE_PATH:-${SCRIPT_CONFIG_DIR:-${HOME}/.xray-script}/network/bbr-original.conf}"
BBR_SIGNATURE="# Managed by Xray-script: TCP BBR v1"

function bbr_msg() {
    local result=""
    if [[ -n "${I18N_DATA:-}" ]] && command -v jq >/dev/null 2>&1; then
        result="$(jq -r --arg key "$1" '.bbr[$key] // empty' <<<"${I18N_DATA}" 2>/dev/null || true)"
    fi
    printf '%s' "${result:-$2}"
}
function bbr_error() { printf '%s\n' "$*" >&2; return 1; }
function bbr_require_root() {
    (( EUID == 0 )) || bbr_error "$(bbr_msg root_required 'Root privileges required.')"
}
function bbr_get() { sysctl -n "$1" 2>/dev/null; }
function bbr_valid_value() { [[ "$1" =~ ^[a-zA-Z0-9_-]+$ ]]; }
function bbr_managed() {
    local header
    [[ -f "$BBR_CONF_PATH" ]] || return 1
    IFS= read -r header <"$BBR_CONF_PATH" || return 1
    [[ "$header" == "$BBR_SIGNATURE" ]]
}
function bbr_load_original() {
    local header
    [[ -f "$BBR_STATE_PATH" ]] || return 1
    IFS= read -r header <"$BBR_STATE_PATH" || return 1
    [[ "$header" == "# Xray-script BBR original values v1" ]] || return 1
    BBR_PREV_CC="$(sed -n 's/^cc=//p' "$BBR_STATE_PATH" | head -n1)"
    BBR_PREV_QDISC="$(sed -n 's/^qdisc=//p' "$BBR_STATE_PATH" | head -n1)"
    bbr_valid_value "$BBR_PREV_CC" && bbr_valid_value "$BBR_PREV_QDISC"
}
function bbr_supported() {
    local available
    available="$(bbr_get net.ipv4.tcp_available_congestion_control)" || return 1
    [[ " $available " == *" bbr "* ]]
}
function bbr_ensure_supported() {
    bbr_supported && return 0
    if command -v modprobe >/dev/null 2>&1; then
        modprobe tcp_bbr >/dev/null 2>&1 || true
    fi
    bbr_supported || bbr_error "$(bbr_msg unsupported 'Kernel does not support TCP BBR.')"
}
function bbr_set_live() {
    local cc="$1" qdisc="$2"
    sysctl -w "net.core.default_qdisc=$qdisc" >/dev/null 2>&1 || return 1
    sysctl -w "net.ipv4.tcp_congestion_control=$cc" >/dev/null 2>&1 || return 1
    [[ "$(bbr_get net.core.default_qdisc)" == "$qdisc" &&
       "$(bbr_get net.ipv4.tcp_congestion_control)" == "$cc" ]]
}
function bbr_status() {
    local cc qdisc available managed="no"
    cc="$(bbr_get net.ipv4.tcp_congestion_control)" || return 1
    qdisc="$(bbr_get net.core.default_qdisc)" || return 1
    available="$(bbr_get net.ipv4.tcp_available_congestion_control || true)"
    if bbr_managed && bbr_load_original; then managed="yes"; fi
    printf '%s: %s\n' "$(bbr_msg cc 'TCP congestion control')" "$cc"
    printf '%s: %s\n' "$(bbr_msg qdisc 'Default qdisc')" "$qdisc"
    printf '%s: %s\n' "$(bbr_msg available 'Available congestion controls')" "$available"
    printf '%s: %s\n' "$(bbr_msg persistent 'Managed persistent BBR')" "$managed"
    if [[ "$cc" == bbr && "$qdisc" == fq ]]; then
        printf '%s\n' "$(bbr_msg active 'BBR + fq is active.')"
    else
        printf '%s\n' "$(bbr_msg inactive 'BBR + fq is not fully active.')"
    fi
}
function bbr_enable() {
    bbr_require_root || return 1
    local previous_cc previous_qdisc state_dir config_dir state_tmp config_tmp
    if [[ -e "$BBR_CONF_PATH" ]]; then
        if ! bbr_managed || ! bbr_load_original; then
            bbr_error "$(bbr_msg conflict 'Unrecognized managed file or missing backup; refusing to overwrite.')"
            return 1
        fi
        bbr_ensure_supported || return 1
        bbr_set_live bbr fq || { bbr_error "$(bbr_msg failed 'Failed to apply BBR and fq.')"; return 1; }
        printf '%s\n' "$(bbr_msg existing 'Existing BBR configuration verified.')"
        bbr_status
        return 0
    fi
    if [[ -e "$BBR_STATE_PATH" ]]; then
        bbr_error "$(bbr_msg orphaned 'Backup exists without a managed drop-in; refusing to overwrite.')"
        return 1
    fi
    previous_cc="$(bbr_get net.ipv4.tcp_congestion_control)" || return 1
    previous_qdisc="$(bbr_get net.core.default_qdisc)" || return 1
    bbr_valid_value "$previous_cc" && bbr_valid_value "$previous_qdisc" ||
        { bbr_error "$(bbr_msg invalid 'Invalid original sysctl values.')"; return 1; }
    bbr_ensure_supported || return 1

    state_dir="$(dirname -- "$BBR_STATE_PATH")"
    config_dir="$(dirname -- "$BBR_CONF_PATH")"
    [[ -d "$config_dir" ]] || { bbr_error "Missing sysctl.d directory: $config_dir"; return 1; }
    mkdir -p -- "$state_dir" || return 1
    chmod 700 "$state_dir" || return 1
    state_tmp="$(mktemp "$state_dir/.bbr-state.XXXXXXXX")" || return 1
    config_tmp="$(mktemp "$config_dir/.xray-bbr.XXXXXXXX")" || { rm -f "$state_tmp"; return 1; }
    printf '# Xray-script BBR original values v1\ncc=%s\nqdisc=%s\n' "$previous_cc" "$previous_qdisc" >"$state_tmp"
    printf '%s\nnet.core.default_qdisc = fq\nnet.ipv4.tcp_congestion_control = bbr\n' "$BBR_SIGNATURE" >"$config_tmp"
    chmod 600 "$state_tmp" && chmod 644 "$config_tmp" ||
        { rm -f "$state_tmp" "$config_tmp"; return 1; }

    if ! bbr_set_live bbr fq; then
        bbr_set_live "$previous_cc" "$previous_qdisc" || true
        rm -f "$state_tmp" "$config_tmp"
        bbr_error "$(bbr_msg failed 'Failed to apply BBR and fq.')"
        return 1
    fi
    if ! mv -- "$state_tmp" "$BBR_STATE_PATH"; then
        bbr_set_live "$previous_cc" "$previous_qdisc" || true
        rm -f "$state_tmp" "$config_tmp"
        return 1
    fi
    if ! mv -- "$config_tmp" "$BBR_CONF_PATH"; then
        bbr_set_live "$previous_cc" "$previous_qdisc" || true
        rm -f "$BBR_STATE_PATH" "$config_tmp"
        return 1
    fi
    printf '%s\n' "$(bbr_msg enabled 'BBR + fq enabled and persisted. No reboot required.')"
    bbr_status
}
function bbr_restore() {
    bbr_require_root || return 1
    if [[ ! -e "$BBR_CONF_PATH" && ! -e "$BBR_STATE_PATH" ]]; then
        printf '%s\n' "$(bbr_msg not_managed 'No Xray-script BBR configuration to restore.')"
        return 0
    fi
    if ! bbr_managed || ! bbr_load_original; then
        bbr_error "$(bbr_msg conflict 'Unrecognized managed file or missing backup; refusing to overwrite.')"
        return 1
    fi
    local current_cc current_qdisc backup
    current_cc="$(bbr_get net.ipv4.tcp_congestion_control)" || return 1
    current_qdisc="$(bbr_get net.core.default_qdisc)" || return 1
    backup="$(mktemp "$(dirname -- "$BBR_CONF_PATH")/.xray-bbr-restore.XXXXXXXX")" || return 1
    cp -- "$BBR_CONF_PATH" "$backup" || { rm -f "$backup"; return 1; }
    rm -- "$BBR_CONF_PATH" || { rm -f "$backup"; return 1; }
    if ! bbr_set_live "$BBR_PREV_CC" "$BBR_PREV_QDISC"; then
        cp -- "$backup" "$BBR_CONF_PATH" || true
        bbr_set_live "$current_cc" "$current_qdisc" || true
        rm -f "$backup"
        bbr_error "$(bbr_msg restore_failed 'Could not restore original network settings; BBR configuration reinstated.')"
        return 1
    fi
    rm -f "$backup" "$BBR_STATE_PATH"
    printf '%s\n' "$(bbr_msg restored 'Original TCP settings restored and BBR drop-in removed.')"
    bbr_status
}
function bbr_main() {
    case "${1:-status}" in
    status) bbr_status ;;
    enable) bbr_enable ;;
    restore) bbr_restore ;;
    *) bbr_error 'Usage: --bbr [status|enable|restore]' ;;
    esac
}
