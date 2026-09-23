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

function ops_warp_trace() {
    local container_ip="$1"
    [[ -n "${container_ip}" ]] || return 1
    curl --noproxy '*' --socks5-hostname "${container_ip}:40001" -fsS --max-time 10         https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null
}

function handler_warp_status() {
    local configured container_state container_ip trace egress_ip country warp_state

    configured="$(echo "${SCRIPT_CONFIG}" | jq -r '.xray.warp // 0')"
    echo "WARP configured : ${configured}"

    if ! command -v docker >/dev/null 2>&1; then
        echo "Docker          : unavailable"
        return 0
    fi

    container_state="$(docker inspect -f '{{.State.Status}}' xray-script-warp 2>/dev/null || true)"
    [[ -n "${container_state}" ]] || container_state='missing'
    echo "Container       : ${container_state}"

    if [[ "${container_state}" != 'running' ]]; then
        return 0
    fi

    container_ip="$(ops_get_warp_container_ip || true)"
    echo "Container IP    : ${container_ip:-unknown}"

    trace="$(ops_warp_trace "${container_ip}" || true)"
    if [[ -z "${trace}" ]]; then
        echo "SOCKS health    : failed"
        return 0
    fi

    egress_ip="$(printf '%s\n' "${trace}" | awk -F= '$1=="ip"{print $2; exit}')"
    country="$(printf '%s\n' "${trace}" | awk -F= '$1=="loc"{print $2; exit}')"
    warp_state="$(printf '%s\n' "${trace}" | awk -F= '$1=="warp"{print $2; exit}')"

    echo "SOCKS health    : ok"
    echo "Egress IP       : ${egress_ip:-unknown}"
    echo "Country         : ${country:-unknown}"
    echo "Cloudflare WARP : ${warp_state:-unknown}"
    echo "Direct fallback : $(echo "${SCRIPT_CONFIG}" | jq -r 'if (.xray.warp_fallback // 0) == 1 then "enabled" else "disabled" end')"
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
    local choice selected
    mapfile -t backups < <(list_xray_backups_array)
    ((${#backups[@]} > 0)) || _error "No Xray backups found"

    handler_backup_list
    printf "Backup index to restore [0=cancel]: " >&2
    read -r choice
    [[ "${choice}" =~ ^[0-9]+$ ]] || _error "Invalid backup index"
    [[ "${choice}" -eq 0 ]] && return 0
    ((choice >= 1 && choice <= ${#backups[@]})) || _error "Invalid backup index"

    selected="${backups[$((choice-1))]}"
    XRAY_CONFIG="$(jq '.' "${selected}")" || _error "Selected backup is not valid JSON"
    apply_xray_config "backup:restore:$(basename "${selected}")" "restart"

    SCRIPT_CONFIG="$(echo "${SCRIPT_CONFIG}" | jq --argjson rules "$(echo "${XRAY_CONFIG}" | jq '.routing.rules // []')" '.rules = $rules')"
    persist_script_config
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
    tar -xzf "${bundle}" -C "${work}" --no-same-owner ||
        { rm -rf "${work}"; _error "Failed to extract config bundle"; }

    jq -e '.format == 1' "${work}/manifest.json" >/dev/null ||
        { rm -rf "${work}"; _error "Unsupported config bundle format"; }
    candidate_script="$(jq '.' "${work}/script-config.json")" ||
        { rm -rf "${work}"; _error "Invalid script config in bundle"; }
    candidate_script="$(echo "${candidate_script}" | jq --arg version "$(echo "${SCRIPT_CONFIG}" | jq -r '.version')" '.version = $version')"
    XRAY_CONFIG="$(jq '.' "${work}/xray-config.json")" ||
        { rm -rf "${work}"; _error "Invalid Xray config in bundle"; }

    apply_xray_config "bundle:import" "restart"
    SCRIPT_CONFIG="${candidate_script}"
    persist_script_config
    rm -rf "${work}"
    ops_info "Config bundle imported successfully"
}

function handler_logs() {
    echo "===== Xray systemd (last 80) ====="
    journalctl -u xray -n 80 --no-pager 2>/dev/null || true
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

    if systemctl -q is-active xray 2>/dev/null; then
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

    if [[ "$(echo "${SCRIPT_CONFIG}" | jq -r '.xray.warp // 0')" -eq 1 ]]; then
        local state ip trace
        state="$(docker inspect -f '{{.State.Status}}' xray-script-warp 2>/dev/null || true)"
        if [[ "${state}" == 'running' ]]; then
            ops_pass "WARP container running"
            ip="$(ops_get_warp_container_ip || true)"
            trace="$(ops_warp_trace "${ip}" || true)"
            if [[ -n "${trace}" ]]; then
                ops_pass "WARP SOCKS egress reachable"
            else
                ops_warn "WARP SOCKS egress check failed"
                ((warnings++))
            fi
        else
            ops_fail "WARP configured but container not running"
            ((failures++))
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
        fi
    fi

    echo "Doctor summary: failures=${failures}, warnings=${warnings}"
    return 0
}
