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
readonly SHADOWROCKET_HELPER="${CUR_DIR}/clash_shadowrocket.py"
readonly SHADOWROCKET_NODES_PATH="${CLASH_DIR}/multi_nodes.txt"
readonly SHADOWROCKET_CACHE_DIR="${CLASH_DIR}/provider-cache"
readonly SHADOWROCKET_REFRESH_SERVICE="/etc/systemd/system/xray-shadowrocket-refresh.service"
readonly SHADOWROCKET_REFRESH_TIMER="/etc/systemd/system/xray-shadowrocket-refresh.timer"

multi_is_enabled() {
    [[ -s "${MULTI_CONFIG_PATH}" ]] &&
        jq -e '.enabled == true' "${MULTI_CONFIG_PATH}" >/dev/null 2>&1
}

multi_read_token() {
    [[ -s "$1" ]] && tr -d '[:space:]' <"$1"
}

multi_generate_token() {
    local token
    token="$(openssl rand -base64 32 2>/dev/null | tr '+/' '-_' | tr -d '=[:space:]')" || return 1
    [[ -n "$token" ]] || return 1
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
    [[ -n "$(state_value backend 2>/dev/null || true)" ]] ||
        fail "First enable this VPS's standalone remote subscription."
    command -v python3 >/dev/null 2>&1 || fail "Python 3 required."
    mkdir -p "${CLASH_DIR}" && chmod 700 "${CLASH_DIR}"
    python3 "${MULTI_HELPER}" --config "${MULTI_CONFIG_PATH}" enable ||
        fail "Could not enable center configuration"
    generate_yaml
    [[ -s "${MULTI_TOKEN_PATH}" ]] ||
        multi_generate_token "${MULTI_TOKEN_PATH}" || fail "Center token creation failed"
    multi_refresh_publication || fail "Could not publish center subscriptions."
    info "This VPS is the aggregation center. Other VPSs only need their standalone subscriptions."
    multi_show
}

multi_add() {
    multi_is_enabled || fail "Only the center can manage remote VPS subscriptions. Enable the center here first."
    local name="${1:-}" url="${2:-}"
    if [[ -z "$name" ]]; then
        printf 'VPS label (e.g. Tokyo): ' >&2
        read -r name
    fi
    if [[ -z "$url" ]]; then
        printf 'Remote VPS single Provider URL (/sub/TOKEN/proxies.yaml): ' >&2
        read -r url
    fi
    python3 "${MULTI_HELPER}" --config "${MULTI_CONFIG_PATH}" add "$name" "$url" ||
        fail "Could not add VPS."
    generate_yaml
    info "Added VPS to THIS center only. No changes required on the remote VPS."
}

multi_remove() {
    multi_is_enabled || fail "Center subscriptions are not enabled on this VPS."
    local name="${1:-}"
    if [[ -z "$name" ]]; then
        printf 'VPS label to remove: ' >&2
        read -r name
    fi
    python3 "${MULTI_HELPER}" --config "${MULTI_CONFIG_PATH}" remove "$name" ||
        fail "VPS not found."
    generate_yaml
    info "Removed VPS from center; its own standalone subscription is untouched."
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

multi_doctor() {
    multi_is_enabled || fail "Center not enabled here; this VPS is a standalone node."
    python3 "${SHADOWROCKET_HELPER}" \
        --config "${MULTI_CONFIG_PATH}" --local "${PROVIDER_YAML_PATH}" \
        --cache-dir "${SHADOWROCKET_CACHE_DIR}" \
        --single "${CLASH_CONFIG_PATH}" \
        --xray "${XRAY_CONFIG_PATH}" --script "${SCRIPT_CONFIG_PATH}" --diagnose
}

multi_show() {
    local token
    if ! multi_is_enabled; then
        info "Standalone VPS (not aggregation center)."
        token="$(current_token)"
        [[ -n "$token" ]] &&
            printf 'Standalone Provider URL: %s\n' "$(multi_url "$token" proxies.yaml)"
        return 0
    fi
    python3 "${MULTI_HELPER}" --config "${MULTI_CONFIG_PATH}" show || return 1
    token="$(multi_read_token "${MULTI_TOKEN_PATH}")"
    [[ -n "$token" ]] && printf 'Center Mihomo subscription: %s\n' "$(multi_url "$token" multi_clash.yaml)"
    [[ -n "$token" ]] && printf 'Center Shadowrocket subscription: %s\n' "$(multi_url "$token" multi_nodes.txt)"
    token="$(current_token)"
    [[ -n "$token" ]] && printf 'This VPS standalone Provider: %s\n' "$(multi_url "$token" proxies.yaml)"
    if [[ "$(state_value backend 2>/dev/null)" == http ]]; then
        warn "Plain HTTP exposes subscription credentials."
    fi
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
    multi_is_enabled || { info "No center is enabled on this VPS."; return 0; }
    python3 "${MULTI_HELPER}" --config "${MULTI_CONFIG_PATH}" disable ||
        fail "Could not disable center."
    if ! multi_refresh_publication; then
        python3 "${MULTI_HELPER}" --config "${MULTI_CONFIG_PATH}" enable >/dev/null || true
        fail "Center publication update failed; center configuration was restored."
    fi
    rm -f "${MULTI_TOKEN_PATH}" "${MULTI_YAML_PATH}" "${SHADOWROCKET_NODES_PATH}"
    # The standalone subscription and proxies.yaml are deliberately retained.
    # Previous dedicated Provider tokens are also left intact during migration
    # so other centers do not unexpectedly lose access.
    info "Center disabled; standalone subscriptions remain available."
}
