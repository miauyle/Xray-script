#!/usr/bin/env bash
# Optional multi-server Mihomo subscriptions. Sourced by core/clash.sh.
readonly MULTI_CONFIG_PATH="${CLASH_DIR}/multi-server.json"
readonly MULTI_YAML_PATH="${CLASH_DIR}/multi_clash.yaml"
readonly PROVIDER_YAML_PATH="${CLASH_DIR}/proxies.yaml"
readonly MULTI_TOKEN_PATH="${CLASH_DIR}/multi_subscription.token"
readonly PROVIDER_TOKEN_PATH="${CLASH_DIR}/provider.token"
readonly PROVIDER_NEXT_TOKEN_PATH="${CLASH_DIR}/provider.token.next"
readonly MULTI_HELPER="${CUR_DIR}/clash_multi.py"

function multi_is_enabled() {
    [[ -s "${MULTI_CONFIG_PATH}" ]] && jq -e '.enabled == true' "${MULTI_CONFIG_PATH}" >/dev/null 2>&1
}

function multi_read_token() {
    [[ -s "$1" ]] && tr -d '[:space:]' <"$1"
}

function multi_generate_token() {
    local token
    token="$(openssl rand -base64 32 2>/dev/null | tr '+/' '-_' | tr -d '=[:space:]')" || return 1
    [[ -n "$token" ]] || return 1
    printf '%s\n' "$token" >"$1" || return 1
    chmod 600 "$1"
}

function multi_generate_files() {
    command -v python3 >/dev/null 2>&1 || return 1
    python3 "${MULTI_HELPER}" --config "${MULTI_CONFIG_PATH}" generate \
        --single "${CLASH_CONFIG_PATH}" --provider "${PROVIDER_YAML_PATH}" \
        --multi "${MULTI_YAML_PATH}"
}

function multi_refresh_publication() {
    local backend port
    backend="$(state_value backend 2>/dev/null || true)"
    [[ -n "$backend" ]] || return 1
    case "$backend" in
    nginx)
        publish_nginx_subscription "$(current_token)" || return 1
        ;;
    http)
        port="$(state_value port)"
        [[ -n "$port" ]] || return 1
        write_http_service "$port" || return 1
        systemctl daemon-reload || return 1
        systemctl restart xray-clash-subscription || return 1
        systemctl -q is-active xray-clash-subscription || return 1
        ;;
    *) return 1 ;;
    esac
}

function multi_enable() {
    local backend
    backend="$(state_value backend 2>/dev/null || true)"
    [[ -n "$backend" ]] || fail "Enable the existing single-server remote subscription first."
    command -v python3 >/dev/null 2>&1 || fail "Python 3 is required."
    mkdir -p "${CLASH_DIR}" && chmod 700 "${CLASH_DIR}"
    python3 "${MULTI_HELPER}" --config "${MULTI_CONFIG_PATH}" enable || fail "Invalid multi-server configuration"
    generate_yaml
    [[ -s "${MULTI_TOKEN_PATH}" ]] || multi_generate_token "${MULTI_TOKEN_PATH}" || fail "Multi token creation failed"
    [[ -s "${PROVIDER_TOKEN_PATH}" ]] || multi_generate_token "${PROVIDER_TOKEN_PATH}" || fail "Provider token creation failed"
    multi_refresh_publication || fail "Failed publishing multi-server endpoints; existing single subscription was preserved."
    multi_show
}

function multi_add() {
    local name="${1:-}" url="${2:-}"
    if [[ -z "$name" ]]; then
        printf 'Peer label (e.g. KR-Oracle): ' >&2
        read -r name
    fi
    if [[ -z "$url" ]]; then
        printf 'Peer Provider URL (/sub/TOKEN/proxies.yaml): ' >&2
        read -r url
    fi
    python3 "${MULTI_HELPER}" --config "${MULTI_CONFIG_PATH}" add "$name" "$url" || fail "Invalid peer"
    if multi_is_enabled; then generate_yaml; fi
    info "Peer registered. Configure this VPS as a peer on the other machines as well."
}

function multi_remove() {
    local name="${1:-}"
    if [[ -z "$name" ]]; then
        printf 'Peer label to remove: ' >&2
        read -r name
    fi
    python3 "${MULTI_HELPER}" --config "${MULTI_CONFIG_PATH}" remove "$name" || fail "Peer not removed"
    if multi_is_enabled; then generate_yaml; fi
    info "Peer removed."
}

function multi_url() {
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

function multi_show() {
    local token
    python3 "${MULTI_HELPER}" --config "${MULTI_CONFIG_PATH}" show || return 1
    if ! multi_is_enabled; then return 0; fi
    token="$(multi_read_token "${MULTI_TOKEN_PATH}")"
    [[ -n "$token" ]] && printf 'Multi subscription: %s\n' "$(multi_url "$token" multi_clash.yaml)"
    token="$(multi_read_token "${PROVIDER_TOKEN_PATH}")"
    [[ -n "$token" ]] && printf 'Provider URL (share with peers only): %s\n' "$(multi_url "$token" proxies.yaml)"
    token="$(multi_read_token "${PROVIDER_NEXT_TOKEN_PATH}")"
    [[ -n "$token" ]] && printf 'Pending Provider URL: %s\n' "$(multi_url "$token" proxies.yaml)"
    if [[ "$(state_value backend 2>/dev/null)" == http ]]; then
        warn "Plain HTTP exposes node credentials and Provider tokens in transit."
    fi
}

function multi_rotate() {
    local which="$1"
    multi_is_enabled || fail "Enable multi-server subscriptions first."
    case "$which" in
    multi)
        multi_generate_token "${MULTI_TOKEN_PATH}" || fail "Could not rotate multi token"
        ;;
    provider)
        [[ ! -s "${PROVIDER_NEXT_TOKEN_PATH}" ]] || fail "Pending Provider rotation exists; finalize it first"
        multi_generate_token "${PROVIDER_NEXT_TOKEN_PATH}" || fail "Could not stage Provider token"
        warn "Old Provider URL stays valid. Update peers to the Pending Provider URL, then finalize."
        ;;
    finalize)
        [[ -s "${PROVIDER_NEXT_TOKEN_PATH}" ]] || fail "No pending Provider token"
        ;;
    *) fail "Use: multi-rotate [multi|provider|finalize]" ;;
    esac

    # Nginx needs a new location; Python checks the token files on every GET.
    if [[ "$which" == finalize ]]; then
        local backup
        backup="$(mktemp "${CLASH_DIR}/provider-token.XXXXXX")" || fail "Backup failed"
        cp "${PROVIDER_TOKEN_PATH}" "$backup" || fail "Backup failed"
        mv "${PROVIDER_NEXT_TOKEN_PATH}" "${PROVIDER_TOKEN_PATH}" || fail "Token commit failed"
        if ! multi_refresh_publication; then
            mv "$backup" "${PROVIDER_TOKEN_PATH}"
            warn "Provider token finalize failed; old token restored. Re-stage a pending token."
            return 1
        fi
        rm -f "$backup"
    else
        multi_refresh_publication || fail "Subscription reload failed"
    fi
    multi_show
}

function multi_disable() {
    multi_is_enabled || { info "Multi-server subscription is already disabled."; return 0; }
    python3 "${MULTI_HELPER}" --config "${MULTI_CONFIG_PATH}" disable || fail "Could not disable multi-server mode"
    if ! multi_refresh_publication; then
        python3 "${MULTI_HELPER}" --config "${MULTI_CONFIG_PATH}" enable >/dev/null
        fail "Could not update subscription backend; previous configuration restored"
    fi
    rm -f "${MULTI_TOKEN_PATH}" "${PROVIDER_TOKEN_PATH}" "${PROVIDER_NEXT_TOKEN_PATH}"
    rm -f "${MULTI_YAML_PATH}" "${PROVIDER_YAML_PATH}"
    if [[ ! -s "${CLASH_TOKEN_PATH}" ]]; then
        case "$(state_value backend 2>/dev/null)" in
        http) disable_http_subscription ;;
        nginx) disable_nginx_subscription ;;
        esac
        rm -f "${CLASH_STATE_PATH}"
    fi
    info "Multi-server subscription disabled; single-server configuration left untouched."
}
