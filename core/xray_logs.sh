#!/usr/bin/env bash
# Manage only the two Xray-script log paths. Never truncate or delete old logs.
# Safe to source; intentionally does not execute anything on import.
function xray_prepare_log_files() {
    local config_path="${1:-${XRAY_CONFIG_PATH:-/usr/local/etc/xray/config.json}}"
    local log_dir="${XRAY_LOG_DIR:-/var/log/xray}"
    local paths='' service_user='' service_group='' current_owner=''
    local path='' backup='' timestamp=''
    [[ -f "$config_path" ]] || return 0
    paths="$(jq -r '[.log.access // empty, .log.error // empty] | .[]' "$config_path")" || {
        echo "ERROR: Cannot read Xray log paths from $config_path" >&2
        return 1
    }
    [[ -n "$paths" ]] || return 0
    # Only touch this script's two known log files. Custom external paths remain
    # the responsibility of the service operator.
    while IFS= read -r path; do
        [[ -n "$path" ]] || continue
        case "$path" in
            "$log_dir/access.log"|"$log_dir/error.log") ;;
            *) echo "WARN: Unmanaged Xray log path; check its permissions: $path" >&2 ;;
        esac
    done <<<"$paths"
    if ! grep -Fxq "$log_dir/access.log" <<<"$paths" &&
       ! grep -Fxq "$log_dir/error.log" <<<"$paths"; then
        return 0
    fi

    # systemd User/Group can change after reinstall/upgrade. Do not assume
    # root or nobody. Empty User means root; empty Group means user's primary.
    service_user="$(systemctl show xray -p User --value 2>/dev/null)" || {
        echo "ERROR: Cannot inspect xray.service User; refusing to modify logs" >&2
        return 1
    }
    service_user="${service_user:-root}"
    service_user="$(id -un "$service_user" 2>/dev/null)" || {
        echo "ERROR: Unknown xray.service User: $service_user" >&2
        return 1
    }
    service_group="$(systemctl show xray -p Group --value 2>/dev/null)" || {
        echo "ERROR: Cannot inspect xray.service Group; refusing to modify logs" >&2
        return 1
    }
    service_group="${service_group:-$(id -gn "$service_user")}"
    getent group "$service_group" >/dev/null || {
        echo "ERROR: Unknown xray.service Group: $service_group" >&2
        return 1
    }
    if [[ "$(systemctl show xray -p DynamicUser --value 2>/dev/null)" == 'yes' ]]; then
        echo "ERROR: DynamicUser=yes; configure systemd LogsDirectory instead of fixed log ownership" >&2
        return 1
    fi

    if [[ -L "$log_dir" || ( -e "$log_dir" && ! -d "$log_dir" ) ]]; then
        echo "ERROR: Invalid Xray log directory: $log_dir" >&2
        return 1
    fi
    if [[ ! -d "$log_dir" ]]; then
        install -d -m 0750 -o "$service_user" -g "$service_group" "$log_dir" || return 1
    else
        current_owner="$(stat -c %U "$log_dir")" || return 1
        # Do not silently seize an unrelated nonroot-owned directory.
        if [[ "$current_owner" != root && "$current_owner" != "$service_user" ]]; then
            echo "ERROR: Existing $log_dir belongs to $current_owner; manual review required" >&2
            return 1
        fi
        chown "$service_user:$service_group" "$log_dir" && chmod 0750 "$log_dir" || return 1
    fi

    for path in "$log_dir/access.log" "$log_dir/error.log"; do
        grep -Fxq "$path" <<<"$paths" || continue
        if [[ -L "$path" || ( -e "$path" && ! -f "$path" ) ]]; then
            echo "ERROR: Not a regular, non-symlink Xray log file: $path" >&2
            return 1
        fi
        if [[ -e "$path" ]]; then
            if [[ "$(stat -c %h "$path")" != 1 ]]; then
                echo "ERROR: Hard-linked Xray log refused: $path" >&2
                return 1
            fi
            if ! runuser -u "$service_user" -g "$service_group" -- test -w "$path"; then
                # Preserve previous bytes and metadata in a unique backup,
                # then create a fresh writable file. Never delete the old log.
                timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
                backup="$(mktemp "$path.backup-$timestamp.XXXXXX")" || return 1
                if ! mv -f -- "$path" "$backup"; then
                    rm -f -- "$backup" # only remove our empty reserved name
                    echo "ERROR: Failed to back up $path" >&2
                    return 1
                fi
                chown root:root "$backup" && chmod 0600 "$backup" || return 1
                echo "INFO: Preserved previous log in $backup" >&2
            fi
        fi
        if [[ ! -e "$path" ]]; then
            # O_EXCL-like no-clobber behavior for a new file; do not truncate.
            (umask 077; set -C; : >"$path") || return 1
            chown "$service_user:$service_group" "$path" && chmod 0640 "$path" || return 1
        fi
        if ! runuser -u "$service_user" -g "$service_group" -- test -w "$path"; then
            echo "ERROR: Xray User=$service_user Group=$service_group cannot write $path" >&2
            return 1
        fi
    done
    return 0
}
