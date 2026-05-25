# lib/commands/info.sh - five device-info verbs split out of `phonectl status`.
#
# Each verb is a sharper, scriptable view of one section of the `status` panel.
# All five share the SSH-based data sources already wired in v0.2:
#   - termux-battery-status (battery JSON via Termux:API)
#   - termux-wifi-connectioninfo (WiFi JSON via Termux:API)
#   - getprop (model + Android version, available at /system/bin/getprop)
#   - df (storage usage)
#   - uptime (system uptime)
#
# Format convention:
#   - Multi-field verbs (battery, info, storage) print a status-style panel
#     using output.sh's `header` + `kv` helpers - the same look as `status`.
#   - Single-value verbs (ip, uptime) print a bare value on one line, no
#     formatting, so users can capture them in shell: `IP=$(phonectl ip)`.

# ---- battery ----------------------------------------------------------------

cmd_battery() {
    require_deps ssh jq || return 1
    config_require_host || return 1

    local battery_json
    battery_json=$(ssh_battery_status) || return 1

    local level temp status plugged health
    level=$(printf '%s' "${battery_json}" | jq -r '.level // ""')
    temp=$(printf '%s' "${battery_json}" | jq -r '.temperature // ""')
    status=$(printf '%s' "${battery_json}" | jq -r '.status // ""')
    plugged=$(printf '%s' "${battery_json}" | jq -r '.plugged // ""')
    health=$(printf '%s' "${battery_json}" | jq -r '.health // ""')

    header "Battery"
    kv "Level" "${level:-?}%"
    kv "Temp" "${temp:-?}°C"
    kv "Status" "${status:-?}"
    kv "Plug" "${plugged:-?}"
    kv "Health" "${health:-?}"
}

# ---- info -------------------------------------------------------------------
#
# Intentionally minimal: model + Android version, matching what `status`
# already shows in its Device section. No kernel, serial, build fingerprint,
# or hardware id - those land in a separate verb if ever needed.

cmd_info() {
    require_deps ssh || return 1
    config_require_host || return 1

    local model android
    model=$(ssh_run getprop ro.product.model | tr -d '\r')
    android=$(ssh_run getprop ro.build.version.release | tr -d '\r')

    header "Device"
    kv "Model" "${model:-?}"
    kv "Android" "${android:-?}"
}

# ---- ip ---------------------------------------------------------------------
#
# Bare value. `IP=$(phonectl ip)` is the natural use. Full WiFi panel
# (RSSI, link speed, frequency) stays in `status`.

cmd_ip() {
    require_deps ssh jq || return 1
    config_require_host || return 1

    local wifi_json ip
    wifi_json=$(ssh_run termux-wifi-connectioninfo)
    ip=$(printf '%s' "${wifi_json}" | jq -r '.ip // ""')

    if [[ -z "${ip}" ]]; then
        error "could not determine WiFi IP from termux-wifi-connectioninfo output"
        return 1
    fi
    printf '%s\n' "${ip}"
}

# ---- storage ----------------------------------------------------------------
#
# Default path is /storage/emulated/0 (the user-data partition, what
# `status` shows). Optional positional arg lets the user inspect any path:
#
#   phonectl storage                  # /storage/emulated/0
#   phonectl storage termux           # alias -> Termux's $PREFIX (expanded on phone)
#   phonectl storage /data            # arbitrary path
#
# For the `termux` alias we send `df $PREFIX` as a single-quoted string so
# the local shell does NOT expand $PREFIX (which would be empty on the
# laptop) - the remote bash on the phone expands it correctly.

cmd_storage() {
    require_deps ssh || return 1
    config_require_host || return 1

    local arg="${1:-}"
    local storage_line label

    if [[ "${arg}" = "termux" ]]; then
        # Literal $PREFIX in the wire payload - expands on the phone.
        storage_line=$(ssh_run df '$PREFIX' | tr -d '\r' | tail -1)
        label='$PREFIX (Termux)'
    else
        local path="${arg:-/storage/emulated/0}"
        storage_line=$(ssh_run df "${path}" | tr -d '\r' | tail -1)
        label="${path}"
    fi

    local total_kb used_kb avail_kb use_pct total_gb used_gb avail_gb
    total_kb=$(printf '%s\n' "${storage_line}" | awk '{print $2}')
    used_kb=$(printf '%s\n' "${storage_line}" | awk '{print $3}')
    avail_kb=$(printf '%s\n' "${storage_line}" | awk '{print $4}')
    use_pct=$(printf '%s\n' "${storage_line}" | awk '{print $5}')
    total_gb=$(awk -v v="${total_kb:-0}" 'BEGIN { printf "%.1f", v/1024/1024 }')
    used_gb=$(awk -v v="${used_kb:-0}" 'BEGIN { printf "%.1f", v/1024/1024 }')
    avail_gb=$(awk -v v="${avail_kb:-0}" 'BEGIN { printf "%.1f", v/1024/1024 }')

    header "Storage (${label})"
    kv "Total" "${total_gb} GB"
    kv "Used" "${used_gb} GB (${use_pct:-?})"
    kv "Free" "${avail_gb} GB"
}

# ---- uptime -----------------------------------------------------------------
#
# Bare value. Parses the "up X" segment from the `uptime` command's output,
# same sed pattern as v0.2's cmd_status. Handles both short ("up 1:09") and
# long ("up 1 day, 3:45") formats.

cmd_uptime() {
    require_deps ssh || return 1
    config_require_host || return 1

    local uptime_line uptime_pretty
    uptime_line=$(ssh_run uptime | tr -d '\r')
    # `uptime` output format varies:
    #   Linux:  "HH:MM:SS up <UPTIME>, N user(s),  load average: ..."
    #   Termux: "HH:MM:SS up <UPTIME>,  load average: ..."   (no users segment)
    # where <UPTIME> can be "1:09", "5 min", "1 day, 3:45", "12 days, 17:32".
    # The long form contains an internal comma, so anchor on ", load average:"
    # which sits AFTER any uptime form. Strip a trailing ", N user(s)" if
    # present (Linux but not Termux).
    uptime_pretty=$(printf '%s' "${uptime_line}" \
        | sed -nE 's/^.* up +(.+), +load average:.*$/\1/p' \
        | sed -E 's/, +[0-9]+ users?$//' \
        | head -1)

    if [[ -z "${uptime_pretty}" ]]; then
        error "could not parse uptime from: ${uptime_line}"
        return 1
    fi
    printf '%s\n' "${uptime_pretty}"
}
