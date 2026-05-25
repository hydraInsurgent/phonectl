# lib/commands/connection.sh - cmd_ssh, cmd_connect, cmd_status.
#
# v0.2 changes from v0.1:
#   - cmd_status is SSH-only (uses termux-battery-status JSON,
#     termux-wifi-connectioninfo JSON, df /storage/emulated/0, uptime
#     command, getprop over SSH). The v0.1 ADB-based pipeline is gone.
#   - cmd_connect uses adb_select_device (USB-first, wireless-fallback)
#     and accepts an optional <port> arg for the "trust persists, port
#     changed" post-reboot recovery case (no full re-pair needed).

# ---- ssh -------------------------------------------------------------------

cmd_ssh() {
    require_deps ssh || return 1
    config_require_host || return 1
    ssh_run "$@"
}

# ---- connect --------------------------------------------------------------

# Usage:
#   phonectl connect                 # try USB-first, then wireless at saved adb_port
#   phonectl connect <new-port>      # update adb_port to <new-port>, then reconnect
#
# The optional port arg covers the common case after a phone reboot or
# wireless-debugging toggle: trust is still established with the laptop
# (no re-pair needed), only the dynamic connect port has changed.
cmd_connect() {
    require_deps adb || return 1
    config_require_host || return 1

    if [[ $# -gt 0 ]]; then
        local new_port="$1"
        if ! [[ "${new_port}" =~ ^[0-9]+$ ]]; then
            error "adb_port must be a number, got: ${new_port}"
            return 1
        fi
        config_set adb_port "${new_port}"
        config_load
        info "Updated adb_port to ${new_port}"
    fi

    local device
    if device=$(adb_select_device); then
        success "Connected via ${device}"
        return 0
    fi

    error "no adb device available."
    info "  - For USB: plug in the phone with USB debugging enabled."
    info "  - If only the port changed: phonectl connect <new-port>"
    info "  - First-time pair / phone-rebooted-fully: phonectl pair"
    return 1
}

# ---- status (SSH-only) ----------------------------------------------------
#
# Implementation:
#  - One ssh_check call up-front fails fast if SSH is down (3s timeout).
#  - Each data section gathered via its own ssh_run call. Order matters
#    only for readability; failures still propagate via set -e in bin/phonectl.
#  - JSON outputs (termux-battery-status, termux-wifi-connectioninfo)
#    parsed with jq. Text outputs (df, uptime, getprop) parsed with awk/sed.
#  - `tr -d '\r'` applied where Termux's bash might emit CRLF, defensive.

cmd_status() {
    require_deps ssh jq || return 1
    config_require_host || return 1

    # ---- reachability probe ----
    if ! ssh_check echo ok >/dev/null 2>&1; then
        error "SSH unreachable on ${PCTL_HOST}:${PCTL_SSH_PORT}"
        info "  Check sshd on the phone, or whether the LAN can see it"
        info "  (see docs/issues/wifi-lan-inbound-drops.md if pings are also failing)."
        return 1
    fi

    # ---- gather ----
    local model android battery_json storage_line uptime_line wifi_json
    model=$(ssh_run getprop ro.product.model | tr -d '\r')
    android=$(ssh_run getprop ro.build.version.release | tr -d '\r')
    battery_json=$(ssh_battery_status) || return 1
    storage_line=$(ssh_run df /storage/emulated/0 | tr -d '\r' | tail -1)
    uptime_line=$(ssh_run uptime | tr -d '\r')
    wifi_json=$(ssh_run termux-wifi-connectioninfo)

    # ---- parse battery (JSON; temperature already in C from Termux:API) ----
    local level temp status plugged health
    level=$(printf '%s' "${battery_json}" | jq -r '.level // ""')
    temp=$(printf '%s' "${battery_json}" | jq -r '.temperature // ""')
    status=$(printf '%s' "${battery_json}" | jq -r '.status // ""')
    plugged=$(printf '%s' "${battery_json}" | jq -r '.plugged // ""')
    health=$(printf '%s' "${battery_json}" | jq -r '.health // ""')

    # ---- parse storage (df: filesystem, 1K-blocks, used, available, use%, mount) ----
    local total_kb used_kb avail_kb use_pct total_gb used_gb avail_gb
    total_kb=$(printf '%s\n' "${storage_line}" | awk '{print $2}')
    used_kb=$(printf '%s\n' "${storage_line}" | awk '{print $3}')
    avail_kb=$(printf '%s\n' "${storage_line}" | awk '{print $4}')
    use_pct=$(printf '%s\n' "${storage_line}" | awk '{print $5}')
    total_gb=$(awk -v v="${total_kb:-0}" 'BEGIN { printf "%.1f", v/1024/1024 }')
    used_gb=$(awk -v v="${used_kb:-0}" 'BEGIN { printf "%.1f", v/1024/1024 }')
    avail_gb=$(awk -v v="${avail_kb:-0}" 'BEGIN { printf "%.1f", v/1024/1024 }')

    # ---- parse uptime ("HH:MM:SS up X day, Y:Z, load average: ...") ----
    # Extract everything between "up " and the next comma. Handles both
    # short (" up 1:09,") and long (" up 1 day, 3:45,") formats.
    local uptime_pretty
    uptime_pretty=$(printf '%s' "${uptime_line}" \
        | sed -nE 's/^.* up +([^,]+(,[^,]*day[^,]*)?),.*$/\1/p' \
        | head -1)
    [[ -z "${uptime_pretty}" ]] && uptime_pretty="?"

    # ---- parse wifi (JSON; ssid/mac/bssid are randomized by Android privacy) ----
    local ip rssi link_speed_mbps freq_mhz
    ip=$(printf '%s' "${wifi_json}" | jq -r '.ip // ""')
    rssi=$(printf '%s' "${wifi_json}" | jq -r '.rssi // ""')
    link_speed_mbps=$(printf '%s' "${wifi_json}" | jq -r '.link_speed_mbps // ""')
    freq_mhz=$(printf '%s' "${wifi_json}" | jq -r '.frequency_mhz // ""')

    # ---- render ----
    header "Device"
    kv "Model" "${model:-?}"
    kv "Android" "${android:-?}"

    echo
    header "Battery"
    kv "Level" "${level:-?}%"
    kv "Temp" "${temp:-?}°C"
    kv "Status" "${status:-?}"
    kv "Plug" "${plugged:-?}"
    kv "Health" "${health:-?}"

    echo
    header "Storage"
    kv "Total" "${total_gb} GB"
    kv "Used" "${used_gb} GB (${use_pct:-?})"
    kv "Free" "${avail_gb} GB"

    echo
    header "Uptime"
    kv "Uptime" "${uptime_pretty}"

    echo
    header "Network"
    kv "WiFi IP" "${ip:-?}"
    kv "RSSI" "${rssi:-?} dBm"
    kv "Link" "${link_speed_mbps:-?} Mbps @ ${freq_mhz:-?} MHz"
    kv "Configured" "${PCTL_HOST}"
    kv "SSH" "${PCTL_HOST}:${PCTL_SSH_PORT} (reachable)"
}
