#!/usr/bin/env bash
# One optional aggregation center; all other VPSs publish standalone Providers.
# Sourced by core/clash.sh. No peer-to-peer topology or provider-token rotation.
readonly MULTI_CONFIG_PATH="${CLASH_DIR}/multi-server.json"
readonly MULTI_YAML_PATH="${CLASH_DIR}/multi_clash.yaml"
readonly PROVIDER_YAML_PATH="${CLASH_DIR}/proxies.yaml"
readonly MULTI_TOKEN_PATH="${CLASH_DIR}/multi_subscription.token"
# Legacy credentials remain readable so old center references do not break on
# upgrade. Newly configured leaf VPSs use their existing single subscription token.
readonly PROVIDER_TOKEN_PATH="${CLASH_DIR}/provider.token"
readonly PROVIDER_NEXT_TOKEN_PATH="${CLASH_DIR}/provider.token.next"
readonly MULTI_HELPER="${CUR_DIR}/clash_multi.py"
readonly SSH_CONFIG_PATH="${CLASH_DIR}/ssh-peers.json"
readonly SSH_CACHE_DIR="${CLASH_DIR}/ssh-cache"
readonly SSH_HELPER="${CUR_DIR}/clash_ssh.py"
readonly SHADOWROCKET_HELPER="${CUR_DIR}/clash_shadowrocket.py"
readonly SHADOWROCKET_NODES_PATH="${CLASH_DIR}/multi_nodes.txt"
readonly SHADOWROCKET_CACHE_DIR="${CLASH_DIR}/provider-cache"
readonly SHADOWROCKET_REFRESH_SERVICE="/etc/systemd/system/xray-shadowrocket-refresh.service"
readonly SHADOWROCKET_REFRESH_TIMER="/etc/systemd/system/xray-shadowrocket-refresh.timer"

multi_ssh_enabled() {
    [[ -s "${SSH_CONFIG_PATH}" ]] && jq -e '.enabled == true' "${SSH_CONFIG_PATH}" >/dev/null 2>&1
}

multi_is_enabled() {
    multi_ssh_enabled && return 0
    [[ -s "${MULTI_CONFIG_PATH}" ]] &&
        jq -e '.enabled == true' "${MULTI_CONFIG_PATH}" >/dev/null 2>&1
}

multi_read_token() {
    [[ -s "$1" ]] && tr -d '[:space:]' <"$1"
}

multi_generate_token() {
    local token
    token="$(generate_token_value)" || return 1
    printf '%s\n' "$token" >"$1" || return 1
    chmod 600 "$1"
}

# Every VPS, including a leaf, creates a pure Mihomo Provider automatically.
# The same single subscription token authorizes both clash.yaml and proxies.yaml.
single_generate_provider() {
    python3 "${MULTI_HELPER}" provider \
        --single "${CLASH_CONFIG_PATH}" --provider "${PROVIDER_YAML_PATH}"
}

# Only the center generates aggregate client subscriptions.
multi_generate_files() {
    multi_is_enabled || return 0
    if multi_ssh_enabled; then
        python3 "${SSH_HELPER}" --config "${SSH_CONFIG_PATH}" --single "${CLASH_CONFIG_PATH}" \
            --local "${PROVIDER_YAML_PATH}" --cache-dir "${SSH_CACHE_DIR}" \
            --multi "${MULTI_YAML_PATH}" --shadowrocket "${SHADOWROCKET_NODES_PATH}" render
        return $?
    fi
    python3 "${MULTI_HELPER}" --config "${MULTI_CONFIG_PATH}" generate \
        --single "${CLASH_CONFIG_PATH}" --provider "${PROVIDER_YAML_PATH}" \
        --multi "${MULTI_YAML_PATH}" || return 1
    python3 "${SHADOWROCKET_HELPER}" --config "${MULTI_CONFIG_PATH}" \
        --local "${PROVIDER_YAML_PATH}" --cache-dir "${SHADOWROCKET_CACHE_DIR}" \
        --output "${SHADOWROCKET_NODES_PATH}"
}

shadowrocket_stop_refresh_timer() {
    if [[ -f "${SHADOWROCKET_REFRESH_TIMER}" ]]; then
        systemctl disable --now xray-shadowrocket-refresh.timer >/dev/null 2>&1 || true
        rm -f "${SHADOWROCKET_REFRESH_TIMER}"
    fi
    if [[ -f "${SHADOWROCKET_REFRESH_SERVICE}" ]]; then
        rm -f "${SHADOWROCKET_REFRESH_SERVICE}"
    fi
    systemctl daemon-reload >/dev/null 2>&1 || true
}

shadowrocket_configure_refresh_timer() {
    if ! multi_is_enabled; then
        shadowrocket_stop_refresh_timer
        return 0
    fi
    local python_bin
    python_bin="$(command -v python3)" || return 1
    cat >"${SHADOWROCKET_REFRESH_SERVICE}" <<EOF_SERVICE
[Unit]
Description=Refresh center Shadowrocket subscription
[Service]
Type=oneshot
ExecStart=${python_bin} ${SHADOWROCKET_HELPER} --config ${MULTI_CONFIG_PATH} --local ${PROVIDER_YAML_PATH} --cache-dir ${SHADOWROCKET_CACHE_DIR} --output ${SHADOWROCKET_NODES_PATH}
NoNewPrivileges=true
PrivateTmp=true
EOF_SERVICE
    cat >"${SHADOWROCKET_REFRESH_TIMER}" <<'EOF_TIMER'
[Unit]
Description=Refresh center Shadowrocket subscription every five minutes
[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
Persistent=true
Unit=xray-shadowrocket-refresh.service
[Install]
WantedBy=timers.target
EOF_TIMER
    systemctl daemon-reload || return 1
    systemctl enable --now xray-shadowrocket-refresh.timer >/dev/null 2>&1
}

multi_refresh_publication() {
    # Static SSH center subscriptions are served by the independent HTTPS unit.
    # No periodic fetching, no restart of the old single-server publisher.
    multi_ssh_enabled && return 0
    local backend port
    backend="$(state_value backend 2>/dev/null || true)"
    [[ -n "$backend" ]] || return 1
    case "$backend" in
    nginx)
        publish_nginx_subscription "$(current_token)" || return 1
        shadowrocket_configure_refresh_timer || return 1
        ;;
    http)
        port="$(state_value port)"
        [[ -n "$port" ]] || return 1
        write_http_service "$port" || return 1
        systemctl daemon-reload || return 1
        systemctl restart xray-clash-subscription || return 1
        systemctl -q is-active xray-clash-subscription || return 1
        shadowrocket_stop_refresh_timer
        ;;
    *) return 1 ;;
    esac
}

multi_enable() {
    command -v python3 >/dev/null 2>&1 || fail "Python 3 required."
    mkdir -p "${CLASH_DIR}" && chmod 700 "${CLASH_DIR}"
    python3 "${SSH_HELPER}" --config "${SSH_CONFIG_PATH}" enable ||
        fail "Could not enable SSH aggregation."
    [[ -s "${CLASH_CONFIG_PATH}" && -s "${PROVIDER_YAML_PATH}" ]] || generate_yaml
    multi_generate_files || fail "Center static publication failed."
    [[ -s "${MULTI_TOKEN_PATH}" ]] ||
        multi_generate_token "${MULTI_TOKEN_PATH}" || fail "Center token creation failed."
    shadowrocket_stop_refresh_timer
    info "SSH aggregation enabled; no provider HTTP polling or background SSH synchronization."
    info "Existing legacy public subscriptions are unchanged until explicitly retired."
    multi_show
}

multi_add() {
    multi_ssh_enabled || fail "Enable SSH aggregation on the center first."
    local name host port user remote key known
    printf 'Node label (e.g. Tokyo): ' >&2; read -r name
    printf 'SSH host/IP: ' >&2; read -r host
    printf 'SSH username (prefer read-only sync account): ' >&2; read -r user
    printf 'SSH port [22]: ' >&2; read -r port
    port="${port:-22}"
    printf 'Remote proxies.yaml absolute path [/root/.xray-script/clash/proxies.yaml]: ' >&2; read -r remote
    remote="${remote:-/root/.xray-script/clash/proxies.yaml}"
    printf 'Center private SSH key absolute path: ' >&2; read -r key
    printf 'Pinned known_hosts file absolute path: ' >&2; read -r known
    python3 "${SSH_HELPER}" --config "${SSH_CONFIG_PATH}" add \
        "$name" "$host" "$user" "$remote" "$key" "$known" --port "$port" ||
        fail "Could not save node; verify key/known_hosts permissions."
    info "Saved. Run Test SSH and Sync to import the peer. Existing subscriptions retained."
}

multi_remove() {
    multi_ssh_enabled || fail "SSH center not enabled."
    local name
    printf 'Node label to delete: ' >&2; read -r name
    python3 "${SSH_HELPER}" --config "${SSH_CONFIG_PATH}" remove "$name" ||
        fail "Node does not exist."
    multi_generate_files || fail "Could not regenerate after removal."
    info "Removed from aggregate. Remote Xray untouched."
}

multi_url() {
    local token="$1" filename="$2" backend host port
    [[ -n "$token" ]] || return 1
    backend="$(state_value backend 2>/dev/null || true)"
    host="$(state_value host 2>/dev/null || true)"
    port="$(state_value port 2>/dev/null || true)"
    [[ -n "$backend" && -n "$host" ]] || return 1
    if [[ "$backend" == nginx ]]; then
        printf 'https://%s/sub/%s/%s' "$host" "$token" "$filename"
    elif [[ "$backend" == http ]]; then
        if [[ "$port" == 80 ]]; then
            printf 'http://%s/sub/%s/%s' "$host" "$token" "$filename"
        else
            printf 'http://%s:%s/sub/%s/%s' "$host" "$port" "$token" "$filename"
        fi
    fi
}

# Display configured remote Provider addresses only on explicit operator request.
multi_list() {
    if multi_ssh_enabled; then
        python3 "${SSH_HELPER}" --config "${SSH_CONFIG_PATH}" --cache-dir "${SSH_CACHE_DIR}" list
    else
        python3 "${MULTI_HELPER}" --config "${MULTI_CONFIG_PATH}" list
    fi
}

multi_doctor() {
    if multi_ssh_enabled; then
        python3 "${SSH_HELPER}" --config "${SSH_CONFIG_PATH}" --cache-dir "${SSH_CACHE_DIR}" list
        [[ -s "${MULTI_YAML_PATH}" && -s "${SHADOWROCKET_NODES_PATH}" ]] ||
            fail "Static center subscriptions not generated."
        info "Check HTTPS via the certificate/service menu; run manual sync to refresh peers."
    else
        python3 "${SHADOWROCKET_HELPER}" \
            --config "${MULTI_CONFIG_PATH}" --local "${PROVIDER_YAML_PATH}" \
            --cache-dir "${SHADOWROCKET_CACHE_DIR}" \
            --single "${CLASH_CONFIG_PATH}" \
            --xray "${XRAY_CONFIG_PATH}" --script "${SCRIPT_CONFIG_PATH}" --diagnose
    fi
}

multi_show() {
    local token
    if multi_ssh_enabled; then
        info "Static SSH center enabled (no automatic peer polling)."
        python3 "${SSH_HELPER}" --config "${SSH_CONFIG_PATH}" --cache-dir "${SSH_CACHE_DIR}" list || return 1
        token="$(multi_read_token "${MULTI_TOKEN_PATH}")"
        if [[ -n "$token" ]] && systemctl -q is-active xray-center-https 2>/dev/null; then
            printf 'Center Mihomo: %s\n' "$(multi_https_url "$token" multi_clash.yaml)"
            printf 'Center Shadowrocket: %s\n' "$(multi_https_url "$token" multi_nodes.txt)"
        else
            warn "HTTPS publication not active. Configure certificate and HTTPS before sharing URLs."
        fi
        return 0
    fi
    if ! multi_is_enabled; then
        info "Standalone VPS (not aggregation center)."
        return 0
    fi
    python3 "${MULTI_HELPER}" --config "${MULTI_CONFIG_PATH}" show || return 1
    token="$(multi_read_token "${MULTI_TOKEN_PATH}")"
    [[ -n "$token" ]] && printf 'Center Mihomo subscription: %s\n' "$(multi_url "$token" multi_clash.yaml)"
    [[ -n "$token" ]] && printf 'Center Shadowrocket subscription: %s\n' "$(multi_url "$token" multi_nodes.txt)"
}

# Rotate the aggregation CENTER token only. Leaf providers use the usual
# single subscription Token rotation. Pre-existing legacy provider tokens
# remain served for backwards compatibility until explicitly retired.
multi_rotate() {
    [[ "${1:-multi}" == multi ]] || fail "Legacy peer-to-peer Provider token rotation was removed; use standalone subscription Token rotation."
    multi_is_enabled || fail "Center is not enabled."
    local old tmp
    old="$(multi_read_token "${MULTI_TOKEN_PATH}")"
    tmp="$(mktemp "${CLASH_DIR}/center-token.XXXXXX")" || return 1
    cp "${MULTI_TOKEN_PATH}" "$tmp" || { rm -f "$tmp"; return 1; }
    multi_generate_token "${MULTI_TOKEN_PATH}" || { rm -f "$tmp"; return 1; }
    if ! multi_refresh_publication; then
        mv "$tmp" "${MULTI_TOKEN_PATH}"
        multi_refresh_publication || true
        fail "Center Token update failed; previous Token restored."
    fi
    rm -f "$tmp"
    multi_show
}

multi_disable() {
    if multi_ssh_enabled; then
        python3 "${SSH_HELPER}" --config "${SSH_CONFIG_PATH}" disable ||
            fail "Unable to disable center."
        systemctl disable --now xray-center-https 2>/dev/null || true
        info "SSH center disabled. Existing standalone Xray and tokens retained."
        return 0
    fi
    info "No SSH center enabled. Legacy center configuration was not modified."
}

# Manual-only remote refresh, failures keep last valid cache and static publication.
multi_sync() {
    multi_ssh_enabled || fail "Enable SSH center first."
    local name="${1:-}"
    if [[ -z "$name" ]]; then
        printf 'Peer label or all [all]: ' >&2; read -r name
    fi
    name="${name:-all}"
    python3 "${SSH_HELPER}" --config "${SSH_CONFIG_PATH}" --single "${CLASH_CONFIG_PATH}" \
        --local "${PROVIDER_YAML_PATH}" --cache-dir "${SSH_CACHE_DIR}" \
        --multi "${MULTI_YAML_PATH}" --shadowrocket "${SHADOWROCKET_NODES_PATH}" \
        sync "$name" || warn "Some peers failed; last validated snapshots remain in place."
}
multi_ssh_test() {
    multi_ssh_enabled || fail "Enable SSH center first."
    local name
    printf 'Peer label to test: ' >&2; read -r name
    python3 "${SSH_HELPER}" --config "${SSH_CONFIG_PATH}" --cache-dir "${SSH_CACHE_DIR}" test "$name"
}
