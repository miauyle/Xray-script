#!/usr/bin/env bash
#
# Copyright (C) 2025 zxcvos
#
# Xray-script:
#   https://github.com/miauyle/Xray-script
# =============================================================================
# 脚本名称: clash.sh
# 功能描述: 生成 Clash Verge Rev / Mihomo 配置，并在 SNI + Nginx 场景下发布 HTTPS 订阅。
# 维护者: miauyle
# 依赖: bash, jq, curl, openssl, nginx (远程订阅时)
# =============================================================================

PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin:/snap/bin
export PATH

readonly GREEN='\033[32m'
readonly YELLOW='\033[33m'
readonly RED='\033[31m'
readonly NC='\033[0m'

readonly CUR_DIR="$(cd -P -- "$(dirname -- "$0")" && pwd -P)"
readonly PROJECT_ROOT="$(cd -P -- "${CUR_DIR}/.." && pwd -P)"
readonly SCRIPT_CONFIG_DIR="${HOME}/.xray-script"
readonly SCRIPT_CONFIG_PATH="${SCRIPT_CONFIG_DIR}/config.json"
readonly XRAY_CONFIG_PATH="/usr/local/etc/xray/config.json"
readonly I18N_DIR="${PROJECT_ROOT}/i18n"
readonly CLASH_DIR="${SCRIPT_CONFIG_DIR}/clash"
readonly CLASH_CONFIG_PATH="${CLASH_DIR}/clash.yaml"
readonly CLASH_TOKEN_PATH="${CLASH_DIR}/subscription.token"
readonly NGINX_CONFIG_DIR="/usr/local/nginx/conf"
readonly NGINX_SUB_CONFIG="${NGINX_CONFIG_DIR}/nginxconfig.io/clash-subscription.conf"

declare I18N_DATA=''
declare SCRIPT_CONFIG=''
declare XRAY_CONFIG=''
declare PUBLIC_IP=''
declare -a NODE_NAMES=()
declare PROXY_BUFFER=''

function load_i18n() {
    local lang
    lang="$(jq -r '.language // "zh"' "${SCRIPT_CONFIG_PATH}")"
    [[ "${lang}" == 'auto' ]] && lang="${LANG%%_*}"
    [[ -f "${I18N_DIR}/${lang}.json" ]] || lang='zh'
    I18N_DATA="$(jq '.' "${I18N_DIR}/${lang}.json")"
}

function msg() {
    echo "${I18N_DATA}" | jq -r --arg key "$1" '.clash[$key] // $key'
}

function info() {
    echo -e "${GREEN}[$(echo "${I18N_DATA}" | jq -r '.title.info')]${NC} $*"
}

function warn() {
    echo -e "${YELLOW}[$(echo "${I18N_DATA}" | jq -r '.title.warn')]${NC} $*" >&2
}

function fail() {
    echo -e "${RED}[$(echo "${I18N_DATA}" | jq -r '.title.error')]${NC} $*" >&2
    exit 1
}

function load_config() {
    [[ -f "${SCRIPT_CONFIG_PATH}" ]] || fail "$(msg script_config_missing)"
    [[ -f "${XRAY_CONFIG_PATH}" ]] || fail "$(msg xray_config_missing)"
    SCRIPT_CONFIG="$(jq '.' "${SCRIPT_CONFIG_PATH}")" || fail "$(msg script_config_invalid)"
    XRAY_CONFIG="$(jq '.' "${XRAY_CONFIG_PATH}")" || fail "$(msg xray_config_invalid)"
}

function yaml_quote() {
    local value="$1"
    value="${value//\'/\'\'}"
    printf "'%s'" "${value}"
}

function get_public_ip() {
    if [[ -z "${PUBLIC_IP}" ]]; then
        PUBLIC_IP="$(curl -4 -fsSL --max-time 8 https://ipv4.icanhazip.com 2>/dev/null | tr -d '[:space:]')"
    fi
    [[ -n "${PUBLIC_IP}" ]] || fail "$(msg public_ip_failed)"
    printf '%s' "${PUBLIC_IP}"
}

function inbound_index_by_tag() {
    local tag="$1"
    echo "${XRAY_CONFIG}" | jq -r --arg tag "${tag}" '.inbounds | to_entries[] | select(.value.tag == $tag) | .key' | head -n1
}

function inbound_value() {
    local index="$1"
    local filter="$2"
    echo "${XRAY_CONFIG}" | jq -r --argjson i "${index}" ".inbounds[\$i]${filter} // empty"
}

function reality_server_name() {
    local index="$1"
    echo "${XRAY_CONFIG}" | jq -r --argjson i "${index}" '
        [.inbounds[$i].streamSettings.realitySettings.serverNames[]? | select(length > 0)][0]
        // empty
    '
}

function reality_short_id() {
    local index="$1"
    echo "${XRAY_CONFIG}" | jq -r --argjson i "${index}" '
        ([.inbounds[$i].streamSettings.realitySettings.shortIds[]? | select(length > 0)][0]
        // .inbounds[$i].streamSettings.realitySettings.shortIds[0]
        // "")
    '
}

function xray_reality_compat_warning() {
    local version major minor patch
    version="$(echo "${SCRIPT_CONFIG}" | jq -r '.xray.version // empty')"
    if [[ "${version}" =~ ^v?([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
        major="${BASH_REMATCH[1]}"
        minor="${BASH_REMATCH[2]}"
        patch="${BASH_REMATCH[3]}"
        if (( major > 26 || (major == 26 && minor > 7) || (major == 26 && minor == 7 && patch >= 11) )); then
            warn "$(msg reality_compat_warning) ${version}"
        fi
    fi
}

function append_vless_reality_node() {
    local name="$1"
    local inbound_index="$2"
    local reality_index="$3"
    local server="$4"
    local uuid flow network servername short_id public_key path host mode port

    uuid="$(inbound_value "${inbound_index}" '.settings.clients[0].id')"
    flow="$(inbound_value "${inbound_index}" '.settings.clients[0].flow')"
    network="$(inbound_value "${inbound_index}" '.streamSettings.network')"
    [[ "${network}" == 'raw' ]] && network='tcp'
    servername="$(reality_server_name "${reality_index}")"
    [[ -n "${servername}" ]] || servername="$(echo "${SCRIPT_CONFIG}" | jq -r '.nginx.domain // empty')"
    short_id="$(reality_short_id "${reality_index}")"
    public_key="$(echo "${SCRIPT_CONFIG}" | jq -r '.xray.publicKey // empty')"
    port="$(echo "${SCRIPT_CONFIG}" | jq -r '.xray.port // 443')"

    [[ -n "${uuid}" && -n "${server}" && -n "${servername}" && -n "${public_key}" ]] || return 1

    NODE_NAMES+=("${name}")
    PROXY_BUFFER+="  - name: $(yaml_quote "${name}")\n"
    PROXY_BUFFER+="    type: vless\n"
    PROXY_BUFFER+="    server: $(yaml_quote "${server}")\n"
    PROXY_BUFFER+="    port: ${port}\n"
    PROXY_BUFFER+="    uuid: $(yaml_quote "${uuid}")\n"
    PROXY_BUFFER+="    udp: true\n"
    PROXY_BUFFER+="    tls: true\n"
    PROXY_BUFFER+="    servername: $(yaml_quote "${servername}")\n"
    PROXY_BUFFER+="    client-fingerprint: chrome\n"
    PROXY_BUFFER+="    encryption: ''\n"
    [[ -n "${flow}" ]] && PROXY_BUFFER+="    flow: $(yaml_quote "${flow}")\n"
    PROXY_BUFFER+="    reality-opts:\n"
    PROXY_BUFFER+="      public-key: $(yaml_quote "${public_key}")\n"
    PROXY_BUFFER+="      short-id: $(yaml_quote "${short_id}")\n"

    if [[ "${network}" == 'xhttp' ]]; then
        path="$(inbound_value "${inbound_index}" '.streamSettings.xhttpSettings.path')"
        host="$(inbound_value "${inbound_index}" '.streamSettings.xhttpSettings.host')"
        mode="$(inbound_value "${inbound_index}" '.streamSettings.xhttpSettings.mode')"
        [[ -n "${mode}" ]] || mode='auto'
        PROXY_BUFFER+="    network: xhttp\n"
        PROXY_BUFFER+="    xhttp-opts:\n"
        PROXY_BUFFER+="      path: $(yaml_quote "${path:-/}")\n"
        PROXY_BUFFER+="      host: $(yaml_quote "${host}")\n"
        PROXY_BUFFER+="      mode: $(yaml_quote "${mode}")\n"
    else
        PROXY_BUFFER+="    network: tcp\n"
    fi
}

function append_vless_tls_xhttp_node() {
    local name="$1"
    local inbound_index="$2"
    local server="$3"
    local uuid path host mode

    uuid="$(inbound_value "${inbound_index}" '.settings.clients[0].id')"
    path="$(inbound_value "${inbound_index}" '.streamSettings.xhttpSettings.path')"
    host="$(inbound_value "${inbound_index}" '.streamSettings.xhttpSettings.host')"
    mode="$(inbound_value "${inbound_index}" '.streamSettings.xhttpSettings.mode')"
    [[ -n "${mode}" ]] || mode='auto'
    [[ -n "${host}" ]] || host="${server}"

    [[ -n "${uuid}" && -n "${server}" ]] || return 1

    NODE_NAMES+=("${name}")
    PROXY_BUFFER+="  - name: $(yaml_quote "${name}")\n"
    PROXY_BUFFER+="    type: vless\n"
    PROXY_BUFFER+="    server: $(yaml_quote "${server}")\n"
    PROXY_BUFFER+="    port: 443\n"
    PROXY_BUFFER+="    uuid: $(yaml_quote "${uuid}")\n"
    PROXY_BUFFER+="    udp: true\n"
    PROXY_BUFFER+="    tls: true\n"
    PROXY_BUFFER+="    servername: $(yaml_quote "${server}")\n"
    PROXY_BUFFER+="    client-fingerprint: chrome\n"
    PROXY_BUFFER+="    encryption: ''\n"
    PROXY_BUFFER+="    network: xhttp\n"
    PROXY_BUFFER+="    alpn:\n"
    PROXY_BUFFER+="      - h2\n"
    PROXY_BUFFER+="    xhttp-opts:\n"
    PROXY_BUFFER+="      path: $(yaml_quote "${path:-/}")\n"
    PROXY_BUFFER+="      host: $(yaml_quote "${host}")\n"
    PROXY_BUFFER+="      mode: $(yaml_quote "${mode}")\n"
}

function build_nodes() {
    local tag vision_index xhttp_index server domain cdn
    tag="$(echo "${SCRIPT_CONFIG}" | jq -r '.xray.tag // empty | ascii_downcase')"
    server="$(get_public_ip)"
    vision_index="$(inbound_index_by_tag 'VLESS-Vision-REALITY')"
    xhttp_index="$(inbound_index_by_tag 'VLESS-XHTTP-REALITY')"
    domain="$(echo "${SCRIPT_CONFIG}" | jq -r '.nginx.domain // empty')"
    cdn="$(echo "${SCRIPT_CONFIG}" | jq -r '.nginx.cdn // empty')"

    case "${tag}" in
    vision)
        [[ -n "${vision_index}" ]] || fail "$(msg no_supported_nodes)"
        append_vless_reality_node 'Vision-Reality' "${vision_index}" "${vision_index}" "${server}" || fail "$(msg node_generation_failed)"
        ;;
    xhttp)
        [[ -n "${xhttp_index}" ]] || xhttp_index="$(inbound_index_by_tag 'VLESS-XHTTP-REALITY')"
        [[ -n "${xhttp_index}" ]] || xhttp_index=1
        append_vless_reality_node 'XHTTP-Reality' "${xhttp_index}" "${xhttp_index}" "${server}" || fail "$(msg node_generation_failed)"
        ;;
    fallback)
        [[ -n "${vision_index}" && -n "${xhttp_index}" ]] || fail "$(msg no_supported_nodes)"
        append_vless_reality_node 'Fallback-Vision-Reality' "${vision_index}" "${vision_index}" "${server}" || fail "$(msg node_generation_failed)"
        append_vless_reality_node 'Fallback-XHTTP-Reality' "${xhttp_index}" "${vision_index}" "${server}" || fail "$(msg node_generation_failed)"
        ;;
    sni)
        [[ -n "${vision_index}" && -n "${xhttp_index}" ]] || fail "$(msg no_supported_nodes)"
        append_vless_reality_node 'SNI-Vision-Reality' "${vision_index}" "${vision_index}" "${server}" || fail "$(msg node_generation_failed)"
        append_vless_reality_node 'SNI-XHTTP-Reality' "${xhttp_index}" "${vision_index}" "${server}" || fail "$(msg node_generation_failed)"
        if [[ -n "${cdn}" ]]; then
            append_vless_tls_xhttp_node 'SNI-XHTTP-TLS-CDN' "${xhttp_index}" "${cdn}" || true
        fi
        ;;
    mkcp)
        fail "$(msg unsupported_mkcp)"
        ;;
    trojan)
        fail "$(msg unsupported_trojan_xhttp)"
        ;;
    *)
        if [[ -n "${vision_index}" ]]; then
            append_vless_reality_node 'Vision-Reality' "${vision_index}" "${vision_index}" "${server}" || fail "$(msg node_generation_failed)"
        elif [[ -n "${xhttp_index}" ]]; then
            append_vless_reality_node 'XHTTP-Reality' "${xhttp_index}" "${xhttp_index}" "${server}" || fail "$(msg node_generation_failed)"
        else
            fail "$(msg no_supported_nodes)"
        fi
        ;;
    esac
}

function generate_yaml() {
    mkdir -p "${CLASH_DIR}"
    chmod 700 "${CLASH_DIR}"
    NODE_NAMES=()
    PROXY_BUFFER=''
    build_nodes
    ((${#NODE_NAMES[@]} > 0)) || fail "$(msg no_supported_nodes)"

    local temp_file
    temp_file="$(mktemp "${CLASH_DIR}/clash.yaml.tmp.XXXXXX")" || fail "$(msg temp_failed)"
    {
        echo "mixed-port: 7890"
        echo "allow-lan: false"
        echo "mode: rule"
        echo "log-level: info"
        echo "ipv6: true"
        echo "proxies:"
        printf '%b' "${PROXY_BUFFER}"
        echo "proxy-groups:"
        echo "  - name: PROXY"
        echo "    type: select"
        echo "    proxies:"
        local node
        for node in "${NODE_NAMES[@]}"; do
            echo "      - $(yaml_quote "${node}")"
        done
        echo "      - DIRECT"
        echo "rules:"
        echo "  - MATCH,PROXY"
    } >"${temp_file}"

    mv -f "${temp_file}" "${CLASH_CONFIG_PATH}"
    chmod 600 "${CLASH_CONFIG_PATH}"
    xray_reality_compat_warning
    info "$(msg generated): ${CLASH_CONFIG_PATH}"
}

function current_token() {
    [[ -s "${CLASH_TOKEN_PATH}" ]] && tr -d '[:space:]' <"${CLASH_TOKEN_PATH}"
}

function generate_token() {
    mkdir -p "${CLASH_DIR}"
    chmod 700 "${CLASH_DIR}"
    openssl rand -hex 24 >"${CLASH_TOKEN_PATH}" || fail "$(msg token_failed)"
    chmod 600 "${CLASH_TOKEN_PATH}"
    current_token
}

function subscription_domain() {
    local domain
    domain="$(echo "${SCRIPT_CONFIG}" | jq -r '.nginx.domain // empty')"
    [[ -n "${domain}" ]] || domain="$(echo "${SCRIPT_CONFIG}" | jq -r '.nginx.cdn // empty')"
    printf '%s' "${domain}"
}

function subscription_url() {
    local token domain
    token="$(current_token)"
    domain="$(subscription_domain)"
    [[ -n "${token}" && -n "${domain}" ]] || return 1
    printf 'https://%s/sub/%s/clash.yaml' "${domain}" "${token}"
}

function ensure_site_include() {
    local site_file="$1"
    [[ -f "${site_file}" ]] || return 0
    if ! grep -Fq 'include nginxconfig.io/clash-subscription.conf;' "${site_file}"; then
        sed -i '/# additional config/i\    include nginxconfig.io/clash-subscription.conf;' "${site_file}" || return 1
    fi
}

function write_nginx_subscription_config() {
    local token="$1"
    mkdir -p "$(dirname "${NGINX_SUB_CONFIG}")"
    cat >"${NGINX_SUB_CONFIG}" <<EOF_NGINX
# Managed by Xray-script. The tokenized path is a secret because the YAML contains proxy credentials.
location = /sub/${token}/clash.yaml {
    alias ${CLASH_CONFIG_PATH};
    default_type text/yaml;
    charset utf-8;
    access_log off;
    add_header Cache-Control "no-store" always;
    add_header X-Content-Type-Options "nosniff" always;
}
EOF_NGINX
}

function nginx_validate_reload() {
    nginx -t >/dev/null 2>&1 || fail "$(msg nginx_validation_failed)"
    systemctl -q is-active nginx && systemctl reload nginx || systemctl start nginx
}

function enable_remote() {
    local tag domain cdn token
    tag="$(echo "${SCRIPT_CONFIG}" | jq -r '.xray.tag // empty | ascii_downcase')"
    [[ "${tag}" == 'sni' ]] || fail "$(msg remote_requires_sni)"
    command -v nginx >/dev/null 2>&1 || fail "$(msg nginx_missing)"

    generate_yaml
    token="$(current_token)"
    [[ -n "${token}" ]] || token="$(generate_token)"
    domain="$(echo "${SCRIPT_CONFIG}" | jq -r '.nginx.domain // empty')"
    cdn="$(echo "${SCRIPT_CONFIG}" | jq -r '.nginx.cdn // empty')"
    [[ -n "${domain}" ]] || fail "$(msg domain_missing)"

    write_nginx_subscription_config "${token}"
    ensure_site_include "${NGINX_CONFIG_DIR}/sites-available/${domain}.conf" || fail "$(msg nginx_update_failed)"
    [[ -n "${cdn}" ]] && ensure_site_include "${NGINX_CONFIG_DIR}/sites-available/${cdn}.conf" || true
    nginx_validate_reload
    show_info
}

function rotate_remote() {
    local tag domain cdn token
    tag="$(echo "${SCRIPT_CONFIG}" | jq -r '.xray.tag // empty | ascii_downcase')"
    [[ "${tag}" == 'sni' ]] || fail "$(msg remote_requires_sni)"
    [[ -f "${CLASH_CONFIG_PATH}" ]] || generate_yaml
    rm -f "${CLASH_TOKEN_PATH}"
    token="$(generate_token)"
    domain="$(echo "${SCRIPT_CONFIG}" | jq -r '.nginx.domain // empty')"
    cdn="$(echo "${SCRIPT_CONFIG}" | jq -r '.nginx.cdn // empty')"
    write_nginx_subscription_config "${token}"
    ensure_site_include "${NGINX_CONFIG_DIR}/sites-available/${domain}.conf" || fail "$(msg nginx_update_failed)"
    [[ -n "${cdn}" ]] && ensure_site_include "${NGINX_CONFIG_DIR}/sites-available/${cdn}.conf" || true
    nginx_validate_reload
    show_info
}

function disable_remote() {
    if [[ -d "$(dirname "${NGINX_SUB_CONFIG}")" ]]; then
        printf '%s\n' '# Clash/Mihomo remote subscription is disabled.' >"${NGINX_SUB_CONFIG}"
    fi
    rm -f "${CLASH_TOKEN_PATH}"
    if command -v nginx >/dev/null 2>&1; then
        nginx_validate_reload
    fi
    info "$(msg remote_disabled)"
}

function show_info() {
    echo -e "${GREEN}Clash / Mihomo${NC}"
    echo "$(msg local_file): ${CLASH_CONFIG_PATH}"
    if [[ -s "${CLASH_TOKEN_PATH}" ]]; then
        local url
        url="$(subscription_url 2>/dev/null || true)"
        [[ -n "${url}" ]] && echo "$(msg remote_url): ${url}"
    else
        echo "$(msg remote_url): $(msg disabled)"
    fi
}

function main() {
    load_i18n
    load_config
    case "${1:-show}" in
    generate) generate_yaml ;;
    enable) enable_remote ;;
    rotate) rotate_remote ;;
    disable) disable_remote ;;
    show) show_info ;;
    *) fail "$(msg unsupported_action): ${1}" ;;
    esac
}

main "$@"
