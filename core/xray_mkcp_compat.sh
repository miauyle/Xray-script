#!/usr/bin/env bash
# Select the old/new FinalMask compatibility spelling for legacy mKCP seeds.
function xray_mkcp_select_mask() {
    local candidate="$1" binary="${XRAY_BINARY_PATH:-/usr/local/bin/xray}"
    local work='' alternate=''
    work="$(mktemp)" || return 1
    chmod 600 "$work" || { rm -f "$work"; return 1; }
    if ! printf '%s\n' "$candidate" >"$work"; then
        rm -f "$work"
        return 1
    fi
    # Probe the installed core rather than guessing a version boundary.
    if "$binary" run -test -format=json -c "$work" >/dev/null 2>&1; then
        rm -f "$work"
        printf '%s\n' "$candidate"
        return 0
    fi
    alternate="$(printf '%s\n' "$candidate" | jq '
        .inbounds[1].streamSettings.finalmask.udp[0] |=
        (if .type == "mkcp-legacy" then
            {"type":"mkcp-aes128gcm", "settings":{"password":.settings.value}}
         else . end)
    ')" || { rm -f "$work"; return 1; }
    if ! printf '%s\n' "$alternate" >"$work"; then
        rm -f "$work"
        return 1
    fi
    if "$binary" run -test -format=json -c "$work" >/dev/null 2>&1; then
        rm -f "$work"
        printf '%s\n' "$alternate"
        return 0
    fi
    rm -f "$work"
    # Preserve the original candidate to show its diagnostic in apply.
    printf '%s\n' "$candidate"
    return 0
}
