#!/usr/bin/env bash
# Xray StatsService viewer. Queries a single read-only snapshot by default.
# Requires only jq and standard Linux coreutils; no extra runtime dependency.
set -o pipefail

XRAY_BIN="${XRAY_BIN:-/usr/local/bin/xray}"
XRAY_STATS_SERVER="${XRAY_STATS_SERVER:-127.0.0.1:32768}"
reset=false
raw=false

case "${1:-}" in
    '' | --read-only) ;;
    --raw) raw=true ;;
    reset | --reset) reset=true ;;
    *)
        printf 'Usage: %s [--raw | --read-only | --reset]\n' "$0" >&2
        printf 'The default and --raw do not reset counters; --reset explicitly clears them.\n' >&2
        exit 2
        ;;
esac
if (($# > 1)); then
    echo 'Too many arguments to traffic stats viewer' >&2
    exit 2
fi

for dependency in jq numfmt; do
    command -v "${dependency}" >/dev/null 2>&1 || {
        printf 'Missing dependency: %s\n' "${dependency}" >&2
        exit 1
    }
done
[[ -x "${XRAY_BIN}" ]] || {
    printf 'Xray binary not executable: %s\n' "${XRAY_BIN}" >&2
    exit 1
}

# A StatsService snapshot uses overlapping accounting dimensions:
# inbound (listener), outbound (egress), user (authenticated identity).
# Their totals must NEVER be added together as server bandwidth usage.
query_time="$(date '+%Y-%m-%d %H:%M:%S %Z')"
pid=''
started=''
if command -v systemctl >/dev/null 2>&1; then
    pid="$(systemctl show xray --property=MainPID --value 2>/dev/null || true)"
    if [[ "${pid}" =~ ^[1-9][0-9]*$ ]]; then
        started="$(ps -p "${pid}" -o lstart= 2>/dev/null | sed -e 's/^[[:space:]]*//' || true)"
    else
        pid=''
    fi
fi

# IMPORTANT: --reset=false is explicit. A normal menu read must not mutate
# counters. Errors must not be silently represented as "0B" traffic.
if ! response="$("${XRAY_BIN}" api statsquery \
    "--server=${XRAY_STATS_SERVER}" "--reset=${reset}")"; then
    echo 'ERROR: Xray Stats API query failed; no traffic totals are available.' >&2
    exit 1
fi

# Protocol buffer JSON may omit .stat when there are no counters and may omit
# .value for a zero. Require valid JSON and legitimate nonnegative integers.
if ! printf '%s' "${response}" | jq -e '
    (type == "object") and
    (.stat == null or (.stat | type) == "array") and
    all(.stat[]?; (.name | type) == "string" and ((.value // "0" | tostring) | test("^[0-9]+$")))
' >/dev/null 2>&1; then
    echo 'ERROR: Xray Stats API returned invalid or unsupported JSON; no totals displayed.' >&2
    exit 1
fi

# Parse structured JSON rather than guessing line order or stripping
# "link" from counter names. Values remain decimal strings (not float64).
if ! records="$(printf '%s' "${response}" | jq -r '
    .stat[]?
    | (.name | capture("^(?<kind>inbound|outbound|user)>>>(?<label>.+)>>>traffic>>>(?<direction>uplink|downlink)$")) as $n
    | [$n.kind, $n.label, $n.direction, (.value // "0" | tostring)]
    | @tsv
' | LC_ALL=C sort -t "$(printf '\t')" -k1,1 -k2,2 -k3,3)"; then
    echo 'ERROR: Failed to parse Xray traffic counters.' >&2
    exit 1
fi

format_bytes() {
    if [[ "${raw}" == true ]]; then
        printf '%sB' "$1"
    else
        numfmt --to=iec-i --suffix=B -- "$1"
    fi
}

print_section() {
    local category="$1" title="$2"
    local kind='' label='' direction='' bytes='' display=''
    local up=0 down=0 total=0 count=0 amount=0

    printf '%s\n' "------------${title}----------"
    if [[ -n "${records}" ]]; then
        while IFS=$'\t' read -r kind label direction bytes; do
            [[ "${kind}" == "${category}" ]] || continue
            # API returns int64; count it using Bash integer arithmetic
            # (not awk float64, which loses precision above 2^53).
            [[ "${bytes}" =~ ^(0|[1-9][0-9]*)$ ]] || {
                printf 'ERROR: Invalid byte count: %s\n' "${bytes}" >&2
                return 1
            }
            # Avoid signed 64-bit overflow; individual Xray counters are int64.
            [[ "${#bytes}" -lt 19 || ( "${#bytes}" -eq 19 && "${bytes}" < "9223372036854775808" ) ]] || {
                echo 'ERROR: Byte counter exceeds signed int64.' >&2
                return 1
            }
            amount=$((bytes))
            case "${direction}" in
                uplink)
                    if ((amount > 9223372036854775807 - up)); then
                        echo 'ERROR: Uplink total exceeds signed int64.' >&2
                        return 1
                    fi
                    up=$((up + amount))
                    display=up
                    ;;
                downlink)
                    if ((amount > 9223372036854775807 - down)); then
                        echo 'ERROR: Downlink total exceeds signed int64.' >&2
                        return 1
                    fi
                    down=$((down + amount))
                    display=down
                    ;;
                *) echo 'ERROR: Unknown counter direction' >&2; return 1 ;;
            esac
            printf '%-44s %s\n' "${category}:${label}->${display}" "$(format_bytes "${bytes}")"
            count=$((count + 1))
        done <<<"${records}"
    fi
    if ((count == 0)); then
        echo '(no counters for this category)'
    fi
    if ((down > 9223372036854775807 - up)); then
        echo 'ERROR: Combined total exceeds signed int64.' >&2
        return 1
    fi
    total=$((up + down))
    printf '%-44s %s\n' 'SUM->up:' "$(format_bytes "${up}")"
    printf '%-44s %s\n' 'SUM->down:' "$(format_bytes "${down}")"
    printf '%-44s %s\n' 'SUM->TOTAL:' "$(format_bytes "${total}")"
    echo '-----------------------------'
}

printf 'Xray traffic snapshot: %s\n' "${query_time}"
printf 'API: %s | reset=%s\n' "${XRAY_STATS_SERVER}" "${reset}"
if [[ -n "${pid}" ]]; then
    printf 'Xray PID: %s%s\n' "${pid}" "${started:+ | process started: ${started}}"
fi
if [[ "${reset}" == true ]]; then
    echo 'NOTE: Returned counters are pre-reset values; this explicit command clears them.'
fi
print_section inbound Inbound || exit 1
print_section outbound Outbound || exit 1
print_section user User || exit 1
echo 'Notes: inbound/outbound/user overlap; do NOT add their totals.'
echo 'Counters are in-memory since Xray start or the last explicit reset (not NIC billing traffic).'
echo 'Rounded human-readable sizes may differ slightly from exact byte sums; use --raw for bytes.'
