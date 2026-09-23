#!/usr/bin/env bash
#
# Copyright (C) 2025 zxcvos
#
# Xray-script:
#   https://github.com/miauyle/Xray-script
# =============================================================================
# 脚本名称: clash.sh
# 功能描述: 生成 Clash Verge Rev / Mihomo 配置，并通过可用的静态 HTTP(S) 后端发布订阅。
# 维护者: miauyle
# 依赖: bash, jq, curl, openssl；远程订阅复用 Nginx 或 Python 3 标准库
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
readonly CLASH_STATE_PATH="${CLASH_DIR}/subscription.json"
readonly CLASH_HTTP_SERVER_PATH="${CUR_DIR}/clash_http_server.py"
readonly CLASH_HTTP_SERVICE="/etc/systemd/system/xray-clash-subscription.service"
readonly DEFAULT_CLASH_HTTP_PORT=80
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

    local temp_file node
    temp_file="$(mktemp "${CLASH_DIR}/clash.yaml.tmp.XXXXXX")" || fail "$(msg temp_failed)"
    {
        cat <<'EOF_YAML'
# Generated by Xray-script for Clash Verge Rev / Mihomo.
# TUN and DNS are intentionally left to the client so this subscription
# does not override local Clash Verge networking preferences.

mixed-port: 7890
allow-lan: false
mode: rule
log-level: info
ipv6: false
unified-delay: true
tcp-concurrent: true

profile:
  store-selected: true

# =========================
# Sniffer
# =========================
sniffer:
  enable: true
  sniff:
    HTTP:
      ports:
        - 80
        - 8080-8880
      override-destination: true
    TLS:
      ports:
        - 443
        - 8443
    QUIC:
      ports:
        - 443
        - 8443
  skip-domain:
    - "Mijia Cloud"
    - "+.push.apple.com"

# =========================
# GEO data
# =========================
geodata-mode: true
geodata-loader: memconservative
geo-auto-update: true
geo-update-interval: 24
geox-url:
  geoip: "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geoip.dat"
  geosite: "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geosite.dat"

# =========================
# Proxies
# =========================
proxies:
EOF_YAML
        printf '%b' "${PROXY_BUFFER}"

        cat <<'EOF_YAML'

# =========================
# Proxy groups
# =========================
proxy-groups:
  - name: Proxy
    type: select
    proxies:
      - Auto
EOF_YAML
        for node in "${NODE_NAMES[@]}"; do
            echo "      - $(yaml_quote "${node}")"
        done
        echo "      - DIRECT"

        cat <<'EOF_YAML'

  - name: Auto
    type: url-test
    url: "https://www.gstatic.com/generate_204"
    interval: 300
    tolerance: 50
    lazy: true
    expected-status: 204
    proxies:
EOF_YAML
        for node in "${NODE_NAMES[@]}"; do
            echo "      - $(yaml_quote "${node}")"
        done

        cat <<'EOF_YAML'

# =========================
# Routing rules
# =========================
rules:
  # Reject common advertising domains first.
  - GEOSITE,category-ads-all,REJECT

  # LAN/private destinations stay direct.
  - GEOIP,lan,DIRECT,no-resolve

  # Mainland-China services/domains/IPs stay direct.
  - GEOSITE,steam@cn,DIRECT
  - GEOSITE,microsoft@cn,DIRECT
  - GEOSITE,CN,DIRECT
  - GEOIP,CN,DIRECT,no-resolve

  # Everything else follows the user-selected policy.
  - MATCH,Proxy
EOF_YAML
    } >"${temp_file}"

    mv -f "${temp_file}" "${CLASH_CONFIG_PATH}"
    chmod 600 "${CLASH_CONFIG_PATH}"
    xray_reality_compat_warning
    info "$(msg generated): ${CLASH_CONFIG_PATH}"
}
function current_token() {
    [[ -s "${CLASH_TOKEN_PATH}" ]] && tr -d '[:space:]' <"${CLASH_TOKEN_PATH}"
}

function generate_token_value() {
    openssl rand -hex 24 || fail "$(msg token_failed)"
}

function save_token() {
    local token="$1"
    mkdir -p "${CLASH_DIR}"
    chmod 700 "${CLASH_DIR}"
    printf '%s\n' "${token}" >"${CLASH_TOKEN_PATH}" || fail "$(msg token_failed)"
    chmod 600 "${CLASH_TOKEN_PATH}"
}

function save_state() {
    local backend="$1"
    local host="$2"
    local port="$3"
    mkdir -p "${CLASH_DIR}"
    chmod 700 "${CLASH_DIR}"
    jq -n --arg backend "${backend}" --arg host "${host}" --argjson port "${port}"         '{backend:$backend,host:$host,port:$port}' >"${CLASH_STATE_PATH}" || fail "$(msg state_failed)"
    chmod 600 "${CLASH_STATE_PATH}"
}

function state_value() {
    local key="$1"
    [[ -s "${CLASH_STATE_PATH}" ]] || return 1
    jq -r --arg key "${key}" '.[$key] // empty' "${CLASH_STATE_PATH}"
}

function subscription_domain() {
    local domain
    domain="$(echo "${SCRIPT_CONFIG}" | jq -r '.nginx.domain // empty')"
    [[ -n "${domain}" ]] || domain="$(echo "${SCRIPT_CONFIG}" | jq -r '.nginx.cdn // empty')"
    printf '%s' "${domain}"
}

function nginx_subscription_available() {
    local domain
    command -v nginx >/dev/null 2>&1 || return 1
    domain="$(subscription_domain)"
    [[ -n "${domain}" ]] || return 1
    [[ -f "${NGINX_CONFIG_DIR}/sites-available/${domain}.conf" ]] || return 1
    return 0
}

function subscription_url() {
    local token backend host port
    token="$(current_token)"
    backend="$(state_value backend 2>/dev/null || true)"
    host="$(state_value host 2>/dev/null || true)"
    port="$(state_value port 2>/dev/null || true)"
    [[ -n "${token}" && -n "${backend}" && -n "${host}" ]] || return 1

    case "${backend}" in
    nginx)
        printf 'https://%s/sub/%s/clash.yaml' "${host}" "${token}"
        ;;
    http)
        [[ -n "${port}" ]] || return 1
        if [[ "${port}" -eq 80 ]]; then
            printf 'http://%s/sub/%s/clash.yaml' "${host}" "${token}"
        else
            printf 'http://%s:%s/sub/%s/clash.yaml' "${host}" "${port}" "${token}"
        fi
        ;;
    *)
        return 1
        ;;
    esac
}

function ensure_site_include() {
    local site_file="$1"
    [[ -f "${site_file}" ]] || return 1
    if ! grep -Fq 'include nginxconfig.io/clash-subscription.conf;' "${site_file}"; then
        sed -i '/# additional config/i\    include nginxconfig.io/clash-subscription.conf;' "${site_file}" || return 1
        grep -Fq 'include nginxconfig.io/clash-subscription.conf;' "${site_file}" || return 1
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

function restore_nginx_file() {
    local original="$1"
    local backup="$2"
    local existed="$3"
    if [[ "${existed}" -eq 1 ]]; then
        cp -af "${backup}" "${original}"
    else
        rm -f "${original}"
    fi
}

function publish_nginx_subscription() {
    local token="$1"
    local domain cdn domain_file cdn_file backup_dir
    local sub_existed=0 domain_existed=0 cdn_existed=0

    domain="$(echo "${SCRIPT_CONFIG}" | jq -r '.nginx.domain // empty')"
    cdn="$(echo "${SCRIPT_CONFIG}" | jq -r '.nginx.cdn // empty')"
    [[ -n "${domain}" ]] || return 1
    domain_file="${NGINX_CONFIG_DIR}/sites-available/${domain}.conf"
    cdn_file="${NGINX_CONFIG_DIR}/sites-available/${cdn}.conf"
    [[ -f "${domain_file}" ]] || return 1

    backup_dir="$(mktemp -d "${CLASH_DIR}/nginx-backup.XXXXXX")" || return 1
    if [[ -f "${NGINX_SUB_CONFIG}" ]]; then
        cp -af "${NGINX_SUB_CONFIG}" "${backup_dir}/subscription.conf"
        sub_existed=1
    fi
    cp -af "${domain_file}" "${backup_dir}/domain.conf"
    domain_existed=1
    if [[ -n "${cdn}" && -f "${cdn_file}" ]]; then
        cp -af "${cdn_file}" "${backup_dir}/cdn.conf"
        cdn_existed=1
    fi

    if ! write_nginx_subscription_config "${token}" || ! ensure_site_include "${domain_file}"; then
        restore_nginx_file "${NGINX_SUB_CONFIG}" "${backup_dir}/subscription.conf" "${sub_existed}"
        restore_nginx_file "${domain_file}" "${backup_dir}/domain.conf" "${domain_existed}"
        [[ "${cdn_existed}" -eq 1 ]] && restore_nginx_file "${cdn_file}" "${backup_dir}/cdn.conf" 1
        rm -rf "${backup_dir}"
        return 1
    fi
    if [[ "${cdn_existed}" -eq 1 ]]; then
        ensure_site_include "${cdn_file}" || {
            restore_nginx_file "${NGINX_SUB_CONFIG}" "${backup_dir}/subscription.conf" "${sub_existed}"
            restore_nginx_file "${domain_file}" "${backup_dir}/domain.conf" "${domain_existed}"
            restore_nginx_file "${cdn_file}" "${backup_dir}/cdn.conf" 1
            rm -rf "${backup_dir}"
            return 1
        }
    fi

    if ! nginx -t >/dev/null 2>&1; then
        restore_nginx_file "${NGINX_SUB_CONFIG}" "${backup_dir}/subscription.conf" "${sub_existed}"
        restore_nginx_file "${domain_file}" "${backup_dir}/domain.conf" "${domain_existed}"
        [[ "${cdn_existed}" -eq 1 ]] && restore_nginx_file "${cdn_file}" "${backup_dir}/cdn.conf" 1
        rm -rf "${backup_dir}"
        return 2
    fi

    if systemctl -q is-active nginx; then
        if ! systemctl reload nginx; then
            restore_nginx_file "${NGINX_SUB_CONFIG}" "${backup_dir}/subscription.conf" "${sub_existed}"
            restore_nginx_file "${domain_file}" "${backup_dir}/domain.conf" "${domain_existed}"
            [[ "${cdn_existed}" -eq 1 ]] && restore_nginx_file "${cdn_file}" "${backup_dir}/cdn.conf" 1
            nginx -t >/dev/null 2>&1 && systemctl reload nginx >/dev/null 2>&1 || true
            rm -rf "${backup_dir}"
            return 3
        fi
    else
        if ! systemctl start nginx; then
            restore_nginx_file "${NGINX_SUB_CONFIG}" "${backup_dir}/subscription.conf" "${sub_existed}"
            restore_nginx_file "${domain_file}" "${backup_dir}/domain.conf" "${domain_existed}"
            [[ "${cdn_existed}" -eq 1 ]] && restore_nginx_file "${cdn_file}" "${backup_dir}/cdn.conf" 1
            rm -rf "${backup_dir}"
            return 3
        fi
    fi

    rm -rf "${backup_dir}"
    return 0
}

function http_service_active() {
    systemctl -q is-active xray-clash-subscription 2>/dev/null
}

function prompt_http_port() {
    local port
    printf "%s [%s]: " "$(msg http_port_prompt)" "${DEFAULT_CLASH_HTTP_PORT}" >&2
    read -r port
    port="${port:-${DEFAULT_CLASH_HTTP_PORT}}"

    if [[ ! "${port}" =~ ^[0-9]+$ ]] || ((port < 1 || port > 65535)); then
        fail "$(msg http_port_invalid)"
    fi
    printf '%s' "${port}"
}

function write_http_service() {
    local port="$1"
    local python_bin
    python_bin="$(command -v python3)" || return 1
    [[ -f "${CLASH_HTTP_SERVER_PATH}" ]] || return 1

    cat >"${CLASH_HTTP_SERVICE}" <<EOF_SERVICE
[Unit]
Description=Xray-script Clash/Mihomo subscription server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${python_bin} ${CLASH_HTTP_SERVER_PATH} --bind 0.0.0.0 --port ${port} --token-file ${CLASH_TOKEN_PATH} --yaml-file ${CLASH_CONFIG_PATH}
Restart=on-failure
RestartSec=2
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF_SERVICE
}

function http_port_available() {
    local port="$1"
    local python_bin current_backend current_port
    current_backend="$(state_value backend 2>/dev/null || true)"
    current_port="$(state_value port 2>/dev/null || true)"

    if http_service_active && [[ "${current_backend}" == 'http' && "${current_port}" == "${port}" ]]; then
        return 0
    fi

    python_bin="$(command -v python3)" || return 1
    "${python_bin}" - "${port}" <<'PY' >/dev/null 2>&1
import socket
import sys
port = int(sys.argv[1])
s = socket.socket()
try:
    s.bind(("0.0.0.0", port))
finally:
    s.close()
PY
}

function print_http_service_diagnostics() {
    echo -e "${YELLOW}----- xray-clash-subscription status -----${NC}" >&2
    systemctl status xray-clash-subscription --no-pager -l >&2 2>/dev/null || true
    echo -e "${YELLOW}----- recent journal -----${NC}" >&2
    journalctl -u xray-clash-subscription -n 30 --no-pager -o cat >&2 2>/dev/null || true
}

function wait_http_subscription() {
    local token="$1"
    local port="$2"
    local attempt

    for attempt in 1 2 3 4 5 6 7 8 9 10; do
        if curl --noproxy '*' -fsS --max-time 2 "http://127.0.0.1:${port}/sub/${token}/clash.yaml" >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.3
    done
    return 1
}

function restore_http_service() {
    local backup="$1"
    local had_service="$2"
    if [[ "${had_service}" -eq 1 ]]; then
        cp -af "${backup}" "${CLASH_HTTP_SERVICE}"
        systemctl daemon-reload >/dev/null 2>&1 || true
        systemctl restart xray-clash-subscription >/dev/null 2>&1 || true
    else
        systemctl disable --now xray-clash-subscription >/dev/null 2>&1 || true
        rm -f "${CLASH_HTTP_SERVICE}"
        systemctl daemon-reload >/dev/null 2>&1 || true
    fi
}

function publish_http_subscription() {
    local token="$1"
    local port="$2"
    local old_token='' had_token=0 had_service=0 backup_service=''

    command -v python3 >/dev/null 2>&1 || return 1
    http_port_available "${port}" || return 2

    [[ -s "${CLASH_TOKEN_PATH}" ]] && {
        old_token="$(current_token)"
        had_token=1
    }

    if [[ -f "${CLASH_HTTP_SERVICE}" ]]; then
        backup_service="$(mktemp "${CLASH_DIR}/http-service.bak.XXXXXX")" || return 1
        cp -af "${CLASH_HTTP_SERVICE}" "${backup_service}"
        had_service=1
    fi

    save_token "${token}"
    write_http_service "${port}" || {
        if [[ "${had_token}" -eq 1 ]]; then save_token "${old_token}"; else rm -f "${CLASH_TOKEN_PATH}"; fi
        [[ -n "${backup_service}" ]] && rm -f "${backup_service}"
        return 1
    }

    systemctl daemon-reload || {
        if [[ "${had_token}" -eq 1 ]]; then save_token "${old_token}"; else rm -f "${CLASH_TOKEN_PATH}"; fi
        restore_http_service "${backup_service}" "${had_service}"
        rm -f "${backup_service}"
        return 1
    }
    systemctl enable xray-clash-subscription >/dev/null 2>&1 || true

    if ! systemctl restart xray-clash-subscription; then
        print_http_service_diagnostics
        if [[ "${had_token}" -eq 1 ]]; then save_token "${old_token}"; else rm -f "${CLASH_TOKEN_PATH}"; fi
        restore_http_service "${backup_service}" "${had_service}"
        rm -f "${backup_service}"
        return 3
    fi

    if ! systemctl -q is-active xray-clash-subscription; then
        print_http_service_diagnostics
        if [[ "${had_token}" -eq 1 ]]; then save_token "${old_token}"; else rm -f "${CLASH_TOKEN_PATH}"; fi
        restore_http_service "${backup_service}" "${had_service}"
        rm -f "${backup_service}"
        return 3
    fi

    if ! wait_http_subscription "${token}" "${port}"; then
        print_http_service_diagnostics
        if command -v ss >/dev/null 2>&1; then
            echo -e "${YELLOW}----- listening sockets on port ${port} -----${NC}" >&2
            ss -ltnp 2>/dev/null | grep -E "[:.]${port}([[:space:]]|$)" >&2 || true
        fi
        if [[ "${had_token}" -eq 1 ]]; then save_token "${old_token}"; else rm -f "${CLASH_TOKEN_PATH}"; fi
        restore_http_service "${backup_service}" "${had_service}"
        rm -f "${backup_service}"
        return 4
    fi

    rm -f "${backup_service}"
    return 0
}

function disable_nginx_subscription() {
    local backup=''
    local had_config=0

    [[ -f "${NGINX_SUB_CONFIG}" ]] || return 0
    mkdir -p "${CLASH_DIR}"
    backup="$(mktemp "${CLASH_DIR}/subscription.conf.bak.XXXXXX")" || return 1
    cp -af "${NGINX_SUB_CONFIG}" "${backup}"
    had_config=1
    printf '%s\n' '# Clash/Mihomo remote subscription is disabled.' >"${NGINX_SUB_CONFIG}"

    if command -v nginx >/dev/null 2>&1; then
        if ! nginx -t >/dev/null 2>&1; then
            [[ "${had_config}" -eq 1 ]] && cp -af "${backup}" "${NGINX_SUB_CONFIG}"
            rm -f "${backup}"
            return 2
        fi
        if systemctl -q is-active nginx && ! systemctl reload nginx; then
            [[ "${had_config}" -eq 1 ]] && cp -af "${backup}" "${NGINX_SUB_CONFIG}"
            nginx -t >/dev/null 2>&1 && systemctl reload nginx >/dev/null 2>&1 || true
            rm -f "${backup}"
            return 3
        fi
    fi

    rm -f "${backup}"
    return 0
}

function disable_http_subscription() {
    if [[ -f "${CLASH_HTTP_SERVICE}" ]] || systemctl list-unit-files xray-clash-subscription.service >/dev/null 2>&1; then
        systemctl disable --now xray-clash-subscription >/dev/null 2>&1 || true
        rm -f "${CLASH_HTTP_SERVICE}"
        systemctl daemon-reload >/dev/null 2>&1 || true
        systemctl reset-failed xray-clash-subscription >/dev/null 2>&1 || true
    fi
}

function confirm_http_fallback() {
    warn "$(msg http_warning)"
    printf "%s [y/N]: " "$(msg http_prompt)" >&2
    local confirm
    read -r confirm
    case "${confirm,,}" in
    y | yes) return 0 ;;
    *) return 1 ;;
    esac
}

function enable_remote() {
    local token rc host previous_backend
    generate_yaml
    token="$(current_token)"
    [[ -n "${token}" ]] || token="$(generate_token_value)"
    previous_backend="$(state_value backend 2>/dev/null || true)"

    if nginx_subscription_available; then
        publish_nginx_subscription "${token}"
        rc=$?
        case "${rc}" in
        0)
            save_token "${token}"
            host="$(subscription_domain)"
            save_state 'nginx' "${host}" 443
            [[ "${previous_backend}" == 'http' ]] && disable_http_subscription
            ;;
        2) fail "$(msg nginx_validation_failed)" ;;
        *) fail "$(msg nginx_update_failed)" ;;
        esac
    else
        local http_port
        command -v python3 >/dev/null 2>&1 || fail "$(msg remote_backend_missing)"
        confirm_http_fallback || fail "$(msg cancelled)"
        http_port="$(prompt_http_port)"
        publish_http_subscription "${token}" "${http_port}"
        rc=$?
        case "${rc}" in
        0)
            host="$(get_public_ip)"
            save_state 'http' "${host}" "${http_port}"
            if [[ "${previous_backend}" == 'nginx' ]]; then
                disable_nginx_subscription || warn "$(msg old_backend_cleanup_failed)"
            fi
            ;;
        2) fail "$(msg http_port_busy): ${http_port}" ;;
        4) fail "$(msg http_self_test_failed)" ;;
        *) fail "$(msg http_service_failed)" ;;
        esac
    fi
    show_info
}

function rotate_remote() {
    local backend token rc host port
    backend="$(state_value backend 2>/dev/null || true)"
    [[ -n "${backend}" ]] || fail "$(msg remote_not_enabled)"
    [[ -f "${CLASH_CONFIG_PATH}" ]] || generate_yaml
    token="$(generate_token_value)"

    case "${backend}" in
    nginx)
        publish_nginx_subscription "${token}"
        rc=$?
        case "${rc}" in
        0)
            save_token "${token}"
            host="$(subscription_domain)"
            save_state 'nginx' "${host}" 443
            ;;
        2) fail "$(msg nginx_validation_failed)" ;;
        *) fail "$(msg nginx_update_failed)" ;;
        esac
        ;;
    http)
        save_token "${token}"
        host="$(state_value host)"
        port="$(state_value port)"
        save_state 'http' "${host}" "${port}"
        ;;
    *)
        fail "$(msg remote_backend_missing)"
        ;;
    esac
    show_info
}

function disable_remote() {
    local backend rc
    backend="$(state_value backend 2>/dev/null || true)"

    case "${backend}" in
    nginx)
        disable_nginx_subscription
        rc=$?
        case "${rc}" in
        0) ;;
        2) fail "$(msg nginx_validation_failed)" ;;
        *) fail "$(msg nginx_update_failed)" ;;
        esac
        ;;
    http)
        disable_http_subscription
        ;;
    *)
        disable_http_subscription
        ;;
    esac

    rm -f "${CLASH_TOKEN_PATH}" "${CLASH_STATE_PATH}"
    info "$(msg remote_disabled)"
}

function show_info() {
    local backend url
    echo -e "${GREEN}Clash / Mihomo${NC}"
    echo "$(msg local_file): ${CLASH_CONFIG_PATH}"
    backend="$(state_value backend 2>/dev/null || true)"
    if [[ -s "${CLASH_TOKEN_PATH}" && -n "${backend}" ]]; then
        url="$(subscription_url 2>/dev/null || true)"
        [[ -n "${url}" ]] && echo "$(msg remote_url): ${url}"
        echo "$(msg remote_backend): ${backend}"
        if [[ "${backend}" == 'http' ]]; then
            warn "$(msg http_warning)"
            warn "$(msg http_firewall_hint): $(state_value port)"
        fi
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
