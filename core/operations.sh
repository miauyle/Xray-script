#!/usr/bin/env bash
#
# Xray-script operations / diagnostics helpers.
# Sourced by core/handler.sh; relies on handler.sh globals and helper functions.

function ops_info() {
    echo -e "${GREEN}[$(echo "$I18N_DATA" | jq -r '.title.info')]${NC} $*"
}

function ops_warn() {
    echo -e "${YELLOW}[$(echo "$I18N_DATA" | jq -r '.title.warn')]${NC} $*" >&2
}

function ops_pass() {
    printf '%b\n' "${GREEN}[PASS]${NC} $*"
}

function ops_fail() {
    printf '%b\n' "${RED}[FAIL]${NC} $*"
}

function ops_get_warp_container_ip() {
    command -v docker >/dev/null 2>&1 || return 1
    docker inspect --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' xray-script-warp 2>/dev/null
}

# A TCP listener does NOT prove a working SOCKS handshake or WARP tunnel.
function ops_warp_tcp_listener() {
    local ip="$1"
    [[ "$ip" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || return 1
    timeout 3 bash -c 'exec 3<>/dev/tcp/"$1"/40001' _ "$ip" 2>/dev/null
}

# Optional second parameter captures curl's failure reason without dumping
# verbose TLS output into the terminal or treating a failure as a valid trace.
function ops_warp_trace() {
    local container_ip="$1" error_file="${2:-/dev/null}"
    [[ -n "${container_ip}" ]] || return 1
    curl --noproxy "" --proxy "socks5h://${container_ip}:40001" \
        -fsS --connect-timeout 4 --max-time 10 \
        https://www.cloudflare.com/cdn-cgi/trace 2>"${error_file}"
}

function ops_warp_client_snapshot() {
    docker exec xray-script-warp warp-cli --accept-tos status 2>/dev/null
}

function ops_warp_client_status() {
    ops_warp_client_snapshot |
        awk -F': ' '/^Status update:/{print $2; exit}'
}

function ops_warp_client_reason() {
    ops_warp_client_snapshot |
        awk -F': ' '/^Reason:/{print $2; exit}'
}

function ops_warp_client_mode() {
    docker exec xray-script-warp warp-cli --accept-tos settings 2>/dev/null |
        awk -F'Mode: ' '/Mode:/{print $2; exit}'
}

function ops_warp_direct_fallback_state() {
    echo "${SCRIPT_CONFIG}" | jq -r \
        'if (.xray.warp_fallback // 0) == 1 then "enabled" else "disabled" end'
}

# Observes the working data path; never changes daemon registration, mode,
# WARP protocol, Xray configuration or container state.
function handler_warp_status() {
    local configured container_state container_ip client_status client_reason client_mode
    local trace='' egress_ip='' country='' warp_state='' error_file='' last_error=''
    local attempt

    configured="$(echo "${SCRIPT_CONFIG}" | jq -r '.xray.warp // 0')"
    echo "WARP configured : ${configured}"
    if ! command -v docker >/dev/null 2>&1; then
        echo "Docker          : unavailable"
        return 0
    fi

    container_state="$(docker inspect -f '{{.State.Status}}' xray-script-warp 2>/dev/null || true)"
    echo "Container       : ${container_state:-missing}"
    [[ "${container_state}" == running ]] || return 0

    container_ip="$(ops_get_warp_container_ip || true)"
    echo "Container IP    : ${container_ip:-unknown}"
    client_status="$(ops_warp_client_status || true)"
    client_reason="$(ops_warp_client_reason || true)"
    client_mode="$(ops_warp_client_mode || true)"
    echo "WARP client     : ${client_status:-unknown}"
    [[ -n "${client_reason}" ]] && echo "Connection stage: ${client_reason}"
    echo "WARP mode       : ${client_mode:-unknown}"

    if ops_warp_tcp_listener "${container_ip}"; then
        echo "SOCKS TCP port  : reachable (not a SOCKS/data-path check)"
    else
        echo "SOCKS TCP port  : unreachable"
    fi

    # A single Connecting transition may occur during normal renegotiation.
    # Two bounded probes reduce false negatives, but persistent failures are
    # still displayed as failures (not silently converted to healthy).
    error_file="$(mktemp)" || error_file='/dev/null'
    for attempt in 1 2; do
        trace="$(ops_warp_trace "${container_ip}" "${error_file}" || true)"
        if [[ -n "${trace}" ]]; then
            break
        fi
        [[ "${attempt}" == 1 ]] && sleep 2
    done
    if [[ -z "${trace}" ]]; then
        last_error="$(tail -n 1 "${error_file}" 2>/dev/null || true)"
    fi
    [[ "${error_file}" == /dev/null ]] || rm -f -- "${error_file}"

    if [[ -z "${trace}" ]]; then
        echo "SOCKS data path : failed (2 attempts)"
        [[ -n "${last_error}" ]] && echo "Probe error     : ${last_error}"
        echo "WARP data path  : unverified/failed"
        echo "Direct fallback : $(ops_warp_direct_fallback_state)"
        echo "Action          : Check Connecting stage; optional menu 13 reconnects without deleting registration"
        return 0
    fi

    egress_ip="$(printf '%s\n' "${trace}" | awk -F= '$1=="ip"{print $2; exit}')"
    country="$(printf '%s\n' "${trace}" | awk -F= '$1=="loc"{print $2; exit}')"
    warp_state="$(printf '%s\n' "${trace}" | awk -F= '$1=="warp"{print $2; exit}')"
    echo "SOCKS data path : HTTP request succeeded"
    echo "Egress IP       : ${egress_ip:-unknown}"
    echo "Country         : ${country:-unknown}"
    if [[ "${warp_state}" == on || "${warp_state}" == plus ]]; then
        echo "WARP data path  : ok (warp=${warp_state})"
    else
        echo "WARP data path  : FAILED (warp=${warp_state:-unknown})"
    fi
    echo "Direct fallback : $(ops_warp_direct_fallback_state)"
}

# Manual, explicitly confirmed recovery. Does not change transport protocol,
# delete reg.json, reinstall Docker/Xray, rotate credentials or change routing.
function handler_warp_reconnect() {
    local state answer=''
    [[ "$(echo "${SCRIPT_CONFIG}" | jq -r '.xray.warp // 0')" == 1 ]] ||
        { echo "WARP is not configured; cannot reconnect." >&2; return 1; }
    command -v docker >/dev/null 2>&1 ||
        { echo "Docker is unavailable." >&2; return 1; }
    state="$(docker inspect -f '{{.State.Status}}' xray-script-warp 2>/dev/null || true)"
    [[ "${state}" == running ]] ||
        { echo "WARP container is not running; inspect its logs first." >&2; return 1; }

    echo "WARP traffic may be briefly interrupted; registration, container and Xray config are preserved."
    printf 'Type yes to reconnect WARP (anything else cancels): '
    read -r answer || return 1
    [[ "${answer}" == yes ]] || { echo "Canceled."; return 0; }

    # Failing to disconnect an already disconnected daemon is not fatal, but
    # failing to issue the subsequent connect is an actionable error.
    docker exec xray-script-warp warp-cli --accept-tos disconnect ||
        echo "Note: WARP disconnect was not accepted; trying connect." >&2
    docker exec xray-script-warp warp-cli --accept-tos connect ||
        { echo "WARP connect failed; inspect docker logs, no registration data was deleted." >&2; return 1; }
    handler_warp_status
}

function handler_warp_fallback() {
    local enabled
    enabled="$(echo "${SCRIPT_CONFIG}" | jq -r '.xray.warp_fallback // 0')"
    XRAY_CONFIG="$(jq '.' "${XRAY_CONFIG_PATH}")" || _error "Failed to read Xray configuration"

    if [[ "${enabled}" -eq 1 ]]; then
        XRAY_CONFIG="$(echo "${XRAY_CONFIG}" | jq '
            .routing.rules |= map(
                if .balancerTag == "warp-fallback" then
                    del(.balancerTag) | .outboundTag = "warp"
                else . end
            )
            | .routing.balancers = ((.routing.balancers // []) | map(select(.tag != "warp-fallback")))
            | if ((.routing.balancers // []) | length) == 0 then del(.routing.balancers) else . end
            | if .observatory then
                .observatory.subjectSelector = ((.observatory.subjectSelector // []) | map(select(. != "warp")))
                | if (.observatory.subjectSelector | length) == 0 then del(.observatory) else . end
              else . end
        ')"
        SCRIPT_CONFIG="$(echo "${SCRIPT_CONFIG}" | jq '.xray.warp_fallback = 0')"
        apply_xray_config "warp:fallback:disable" "restart"
        SCRIPT_CONFIG="$(echo "${SCRIPT_CONFIG}" | jq --argjson rules "$(echo "${XRAY_CONFIG}" | jq '.routing.rules // []')" '.rules = $rules')"
        persist_script_config
        ops_info "WARP direct fallback disabled"
        return 0
    fi

    [[ "$(echo "${SCRIPT_CONFIG}" | jq -r '.xray.warp // 0')" -eq 1 ]] ||
        _error "Enable WARP before enabling direct fallback"
    echo "${XRAY_CONFIG}" | jq -e '.outbounds[]? | select(.tag == "warp")' >/dev/null ||
        _error "WARP outbound was not found in Xray config"
    echo "${XRAY_CONFIG}" | jq -e '.outbounds[]? | select(.tag == "direct")' >/dev/null ||
        _error "Direct outbound was not found in Xray config"

    XRAY_CONFIG="$(echo "${XRAY_CONFIG}" | jq '
        .routing.balancers = (
            ((.routing.balancers // []) | map(select(.tag != "warp-fallback")))
            + [{
                "tag": "warp-fallback",
                "selector": ["warp"],
                "fallbackTag": "direct",
                "strategy": {"type": "random"}
            }]
        )
        | .observatory = (
            (.observatory // {})
            | .subjectSelector = (((.subjectSelector // []) + ["warp"]) | unique)
            | .probeUrl = (.probeUrl // "https://www.gstatic.com/generate_204")
            | .probeInterval = (.probeInterval // "30s")
            | .enableConcurrency = (.enableConcurrency // false)
        )
        | .routing.rules |= map(
            if .outboundTag == "warp" then
                del(.outboundTag) | .balancerTag = "warp-fallback"
            else . end
        )
    ')"
    SCRIPT_CONFIG="$(echo "${SCRIPT_CONFIG}" | jq '.xray.warp_fallback = 1')"
    apply_xray_config "warp:fallback:enable" "restart"
    SCRIPT_CONFIG="$(echo "${SCRIPT_CONFIG}" | jq --argjson rules "$(echo "${XRAY_CONFIG}" | jq '.routing.rules // []')" '.rules = $rules')"
    persist_script_config
    ops_info "WARP direct fallback enabled (observatory + balancer fallbackTag=direct)"
}

function handler_direct_family() {
    local family="$1"
    local strategy=''

    case "${family}" in
    auto) strategy='AsIs' ;;
    ipv4) strategy='UseIPv4' ;;
    ipv6) strategy='UseIPv6' ;;
    *) _error "Unsupported direct egress family: ${family}" ;;
    esac

    XRAY_CONFIG="$(jq '.' "${XRAY_CONFIG_PATH}")" || _error "Failed to read Xray configuration"
    echo "${XRAY_CONFIG}" | jq -e '.outbounds[]? | select(.tag == "direct" and .protocol == "freedom")' >/dev/null ||
        _error "Direct freedom outbound was not found"

    if [[ "${family}" == 'auto' ]]; then
        XRAY_CONFIG="$(echo "${XRAY_CONFIG}" | jq '
            .outbounds |= map(
                if .tag == "direct" and .protocol == "freedom" then
                    if .streamSettings?.sockopt? then
                        del(.streamSettings.sockopt.domainStrategy)
                        | if (.streamSettings.sockopt | length) == 0 then del(.streamSettings.sockopt) else . end
                        | if (.streamSettings | length) == 0 then del(.streamSettings) else . end
                    else . end
                else . end
            )
        ')"
    else
        XRAY_CONFIG="$(echo "${XRAY_CONFIG}" | jq --arg strategy "${strategy}" '
            .outbounds |= map(
                if .tag == "direct" and .protocol == "freedom" then
                    .streamSettings = (.streamSettings // {})
                    | .streamSettings.sockopt = (.streamSettings.sockopt // {})
                    | .streamSettings.sockopt.domainStrategy = $strategy
                else . end
            )
        ')"
    fi

    SCRIPT_CONFIG="$(echo "${SCRIPT_CONFIG}" | jq --arg family "${family}" '.xray.direct_family = $family')"
    apply_xray_config "direct:family:${family}" "restart"
    persist_script_config
    ops_info "Direct egress family: ${family}"
}

function list_xray_backups_array() {
    [[ -d "${XRAY_BACKUP_DIR}" ]] || return 0
    find "${XRAY_BACKUP_DIR}" -maxdepth 1 -type f -name 'config-*.json' -printf '%T@ %p\n' 2>/dev/null |
        sort -nr |
        cut -d' ' -f2-
}

function handler_backup_list() {
    local -a backups=()
    local i
    mapfile -t backups < <(list_xray_backups_array)
    if ((${#backups[@]} == 0)); then
        echo "No Xray backups found"
        return 0
    fi
    for ((i=0; i<${#backups[@]}; i++)); do
        printf '%2d. %s\n' "$((i+1))" "$(basename "${backups[${i}]}")"
    done
}

function handler_backup_restore() {
    local -a backups=()
    local choice selected script_selected candidate_script=''
    mapfile -t backups < <(list_xray_backups_array)
    ((${#backups[@]} > 0)) || _error "No Xray backups found"

    handler_backup_list
    printf "Backup index to restore [0=cancel]: " >&2
    read -r choice
    [[ "${choice}" =~ ^[0-9]+$ ]] || _error "Invalid backup index"
    [[ "${choice}" -eq 0 ]] && return 0
    ((choice >= 1 && choice <= ${#backups[@]})) || _error "Invalid backup index"

    selected="${backups[$((choice-1))]}"
    script_selected="${selected/config-/script-}"
    XRAY_CONFIG="$(jq '.' "${selected}")" || _error "Selected backup is not valid JSON"

    # v2026.09.23.9+ backups pair Xray config with script state; legacy backups remain supported.
    if [[ -f "${script_selected}" ]]; then
        candidate_script="$(jq '.' "${script_selected}")" || _error "Paired script-state backup is invalid JSON"
        candidate_script="$(echo "${candidate_script}" | jq --arg version "$(echo "${SCRIPT_CONFIG}" | jq -r '.version')" '.version = $version')"
    fi

    if [[ -n "${candidate_script}" ]]; then
        snapshot_script_config_for_xray_change
        trap '[[ -f "${SCRIPT_CONFIG_PENDING_PATH}" ]] && restore_pending_script_config >/dev/null 2>&1 || true' EXIT
        SCRIPT_CONFIG="${candidate_script}"
        persist_script_config
        apply_xray_config "xray:regenerate:backup-restore:$(basename "${selected}")" "restart"
        trap - EXIT
    else
        apply_xray_config "backup:restore:$(basename "${selected}")" "restart"
        SCRIPT_CONFIG="$(echo "${SCRIPT_CONFIG}" | jq --argjson rules "$(echo "${XRAY_CONFIG}" | jq '.routing.rules // []')" '.rules = $rules')"
        persist_script_config
        ops_warn "This is a legacy Xray-only backup; protocol metadata in script config was not restored"
    fi
    ops_info "Restored Xray backup: $(basename "${selected}")"
}
function handler_export_config() {
    local export_dir="${SCRIPT_CONFIG_DIR}/exports"
    local work export_file timestamp
    timestamp="$(date '+%Y%m%d-%H%M%S')"
    mkdir -p "${export_dir}" || _error "Failed to create export directory"
    chmod 700 "${export_dir}" || _error "Failed to secure export directory"
    work="$(mktemp -d)" || _error "Failed to create export workspace"
    export_file="${export_dir}/xray-script-export-${timestamp}.tar.gz"

    cp -p "${SCRIPT_CONFIG_PATH}" "${work}/script-config.json" || { rm -rf "${work}"; _error "Failed to stage script config"; }
    cp -p "${XRAY_CONFIG_PATH}" "${work}/xray-config.json" || { rm -rf "${work}"; _error "Failed to stage Xray config"; }
    jq -n         --arg created "$(date -Iseconds)"         --arg version "$(echo "${SCRIPT_CONFIG}" | jq -r '.version // empty')"         '{format:1,created:$created,version:$version}' >"${work}/manifest.json"

    tar -C "${work}" -czf "${export_file}" manifest.json script-config.json xray-config.json ||
        { rm -rf "${work}"; _error "Failed to create config export"; }
    rm -rf "${work}"
    chmod 600 "${export_file}"
    ops_info "Config export: ${export_file}"
}

function handler_import_config() {
    local bundle="${1:-}"
    local work member candidate_script
    if [[ -z "${bundle}" ]]; then
        printf "Config bundle path: " >&2
        read -r bundle
    fi
    [[ -f "${bundle}" ]] || _error "Config bundle not found: ${bundle}"

    local members
    members="$(tar -tzf "${bundle}" 2>/dev/null)" || _error "Invalid config bundle"
    while IFS= read -r member; do
        [[ -n "${member}" ]] || continue
        case "${member}" in
        manifest.json|script-config.json|xray-config.json) ;;
        *) _error "Unsupported file in config bundle: ${member}" ;;
        esac
    done <<<"${members}"

    work="$(mktemp -d)" || _error "Failed to create import workspace"
    tar -xzf "${bundle}" -C "${work}" --no-same-owner --no-same-permissions ||
        { rm -rf "${work}"; _error "Failed to extract config bundle"; }
    for member in manifest.json script-config.json xray-config.json; do
        [[ -f "${work}/${member}" && ! -L "${work}/${member}" ]] ||
            { rm -rf "${work}"; _error "Config bundle contains an invalid file type: ${member}"; }
    done

    jq -e '.format == 1' "${work}/manifest.json" >/dev/null ||
        { rm -rf "${work}"; _error "Unsupported config bundle format"; }
    candidate_script="$(jq '.' "${work}/script-config.json")" ||
        { rm -rf "${work}"; _error "Invalid script config in bundle"; }
    candidate_script="$(echo "${candidate_script}" | jq --arg version "$(echo "${SCRIPT_CONFIG}" | jq -r '.version')" '.version = $version')"
    XRAY_CONFIG="$(jq '.' "${work}/xray-config.json")" ||
        { rm -rf "${work}"; _error "Invalid Xray config in bundle"; }

    snapshot_script_config_for_xray_change
    trap '[[ -f "${SCRIPT_CONFIG_PENDING_PATH}" ]] && restore_pending_script_config >/dev/null 2>&1 || true' EXIT
    SCRIPT_CONFIG="${candidate_script}"
    persist_script_config
    apply_xray_config "xray:regenerate:bundle-import" "restart"
    trap - EXIT
    rm -rf "${work}"
    ops_info "Config bundle imported successfully"
}

function handler_logs() {
    echo "===== Xray systemd (last 80) ====="
    journalctl -u xray -n 80 --no-pager 2>/dev/null || true
    echo
    echo "===== Xray access.log (last 80) ====="
    [[ -f /var/log/xray/access.log ]] && tail -n 80 /var/log/xray/access.log || echo "(missing)"
    echo
    echo "===== Xray error.log (last 80) ====="
    [[ -f /var/log/xray/error.log ]] && tail -n 80 /var/log/xray/error.log || echo "(missing)"
    echo
    echo "===== WARP container (last 80) ====="
    if command -v docker >/dev/null 2>&1 && docker inspect xray-script-warp >/dev/null 2>&1; then
        docker logs --tail 80 xray-script-warp 2>&1 || true
    else
        echo "(container missing)"
    fi
    echo
    echo "===== Clash subscription service (last 80) ====="
    journalctl -u xray-clash-subscription -n 80 --no-pager 2>/dev/null || true
}

function handler_doctor() {
    local failures=0 warnings=0 configured_port backup_count
    echo "===== Xray-script Doctor ====="

    for cmd in jq curl xray systemctl; do
        if command -v "${cmd}" >/dev/null 2>&1; then
            ops_pass "command: ${cmd}"
        else
            ops_fail "command missing: ${cmd}"
            ((failures++))
        fi
    done

    if jq -e . "${SCRIPT_CONFIG_PATH}" >/dev/null 2>&1; then
        ops_pass "script config JSON"
    else
        ops_fail "script config JSON"
        ((failures++))
    fi

    if jq -e . "${XRAY_CONFIG_PATH}" >/dev/null 2>&1; then
        ops_pass "Xray config JSON"
    else
        ops_fail "Xray config JSON"
        ((failures++))
    fi

    if command -v xray >/dev/null 2>&1 && xray run -test -format=json -c "${XRAY_CONFIG_PATH}" >/dev/null 2>&1; then
        ops_pass "xray config validation"
    else
        ops_fail "xray config validation"
        ((failures++))
    fi

    if command -v systemctl >/dev/null 2>&1 && systemctl -q is-active xray 2>/dev/null; then
        ops_pass "xray service active"
    else
        ops_fail "xray service inactive"
        ((failures++))
    fi

    configured_port="$(echo "${SCRIPT_CONFIG}" | jq -r '.xray.port // 443')"
    if command -v ss >/dev/null 2>&1 && ss -ltn 2>/dev/null | grep -Eq "[:.]${configured_port}([[:space:]]|$)"; then
        ops_pass "TCP port ${configured_port} listening"
    else
        ops_warn "TCP port ${configured_port} not detected as listening"
        ((warnings++))
    fi

    backup_count="$(list_xray_backups_array | wc -l | tr -d ' ')"
    ops_pass "Xray backups: ${backup_count}"

    if [[ -f "${SCRIPT_CONFIG_PENDING_PATH}" ]]; then
        ops_warn "pending Xray/script transaction snapshot exists; a previous reconfiguration may have been interrupted"
        ((warnings++))
    fi

    if [[ "$(echo "${SCRIPT_CONFIG}" | jq -r '.xray.warp // 0')" -eq 1 ]]; then
        local state ip trace
        if ! command -v docker >/dev/null 2>&1; then
            ops_fail "WARP configured but Docker is unavailable"
            ((failures++))
        else
            state="$(docker inspect -f '{{.State.Status}}' xray-script-warp 2>/dev/null || true)"
            if [[ "${state}" == 'running' ]]; then
                ops_pass "WARP container running"
                ip="$(ops_get_warp_container_ip || true)"
                trace="$(ops_warp_trace "${ip}" || true)"
                if [[ -n "${trace}" ]]; then
                    local doctor_warp_state
                    doctor_warp_state="$(printf '%s\n' "${trace}" | awk -F= '$1=="warp"{print $2; exit}')"
                    if [[ "${doctor_warp_state}" == 'on' || "${doctor_warp_state}" == 'plus' ]]; then
                        ops_pass "WARP SOCKS data path active (warp=${doctor_warp_state})"
                    else
                        ops_fail "WARP proxy reachable but traffic is not tunneled (warp=${doctor_warp_state:-unknown})"
                        ((failures++))
                    fi
                else
                    local stage=''
                    stage="$(ops_warp_client_status || true)"
                    ops_fail "WARP SOCKS data path unreachable (client=${stage:-unknown}); see WARP status menu for reason and TCP listener check"
                    ((failures++))
                fi
            else
                ops_fail "WARP configured but container not running"
                ((failures++))
            fi
        fi

        if [[ "$(echo "${SCRIPT_CONFIG}" | jq -r '.xray.warp_fallback // 0')" -eq 1 ]]; then
            if jq -e '.routing.balancers[]? | select(.tag == "warp-fallback" and .fallbackTag == "direct")' "${XRAY_CONFIG_PATH}" >/dev/null 2>&1 &&
               jq -e '.observatory.subjectSelector[]? | select(. == "warp")' "${XRAY_CONFIG_PATH}" >/dev/null 2>&1; then
                ops_pass "WARP Direct fallback wiring"
            else
                ops_fail "WARP Direct fallback flag/config mismatch"
                ((failures++))
            fi
        fi
    fi

    if [[ -f "${SCRIPT_CONFIG_DIR}/clash/subscription.json" ]]; then
        local backend
        backend="$(jq -r '.backend // empty' "${SCRIPT_CONFIG_DIR}/clash/subscription.json" 2>/dev/null)"
        if [[ "${backend}" == 'http' ]]; then
            if systemctl -q is-active xray-clash-subscription 2>/dev/null; then
                ops_pass "Clash HTTP subscription service active"
            else
                ops_warn "Clash HTTP subscription configured but service inactive"
                ((warnings++))
            fi
        elif [[ "${backend}" == 'nginx' ]]; then
            ops_pass "Clash subscription backend: nginx HTTPS"
        fi
    fi

    echo "Doctor summary: failures=${failures}, warnings=${warnings}"
    return 0
}
