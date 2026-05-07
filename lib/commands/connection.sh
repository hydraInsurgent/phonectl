# lib/commands/connection.sh - cmd_ssh, cmd_connect, cmd_status.
#
# `cmd_status` is the most parsing-heavy verb in v0.1: it makes several
# adb shell calls, parses /proc + dumpsys output, then renders one panel.
# The parsers were written against real captured output in test/fixtures/
# so they handle the OPLUS-specific dumpsys layout and Android 13's df
# `/dev/fuse` device naming correctly.

# ---- ssh --------------------------------------------------------------------

cmd_ssh() {
    require_deps ssh || return 1
    config_require_host || return 1
    ssh_run "$@"
}

# ---- connect ----------------------------------------------------------------

cmd_connect() {
    require_deps adb || return 1
    config_require_host || return 1
    local resolved
    if resolved="$(adb_connect)"; then
        success "Connected to ${resolved}"
    else
        error "could not connect to ${PCTL_HOST}:${PCTL_ADB_PORT}"
        if [[ -n "${PCTL_HOST_ALT:-}" ]]; then
            info "  (also tried ${PCTL_HOST_ALT}:${PCTL_ADB_PORT})"
        fi
        return 1
    fi
}

# ---- status -----------------------------------------------------------------
#
# Implementation strategy (per plan):
#  - Each adb_shell call is captured into its own variable, with `tr -d '\r'`
#    to normalize Android shell's \r\n line endings.
#  - Parsing uses awk against the field-of-interest; defaults to "?" or "0"
#    if a field is missing.
#  - On any adb failure, set -e + pipefail (set in bin/phonectl) propagate
#    the non-zero exit code and the user sees the raw adb error verbatim
#    (per the "fail loud" principle in the plan).

cmd_status() {
    require_deps adb ssh || return 1
    config_require_host || return 1

    # ----- gather -----
    local model android battery storage_line uptime_secs ip_addr
    model=$(adb_shell getprop ro.product.model | tr -d '\r')
    android=$(adb_shell getprop ro.build.version.release | tr -d '\r')
    battery=$(adb_shell dumpsys battery | tr -d '\r')
    storage_line=$(adb_shell df /sdcard | tr -d '\r' | tail -1)
    uptime_secs=$(adb_shell cat /proc/uptime | tr -d '\r' | awk '{print $1}')
    ip_addr=$(adb_shell ip addr show wlan0 \
        | tr -d '\r' \
        | awk '/inet / { sub(/\/.*/, "", $2); print $2; exit }')

    # ----- parse battery (standard 'Current Battery Service state' block) -----
    local level temp_milli status_code temp_c status_label
    level=$(printf '%s\n' "${battery}" | awk -F': *' '/^  level:/{print $2; exit}')
    temp_milli=$(printf '%s\n' "${battery}" | awk -F': *' '/^  temperature:/{print $2; exit}')
    status_code=$(printf '%s\n' "${battery}" | awk -F': *' '/^  status:/{print $2; exit}')
    temp_c=$(awk -v t="${temp_milli:-0}" 'BEGIN { printf "%.1f", t/10 }')
    case "${status_code}" in
        2) status_label="charging" ;;
        3) status_label="discharging" ;;
        4) status_label="not charging" ;;
        5) status_label="full" ;;
        *) status_label="unknown(${status_code:-?})" ;;
    esac

    # ----- parse df (1K-blocks: total, used, available, use%) -----
    local total_kb used_kb avail_kb use_pct total_gb used_gb avail_gb
    total_kb=$(printf '%s\n' "${storage_line}" | awk '{print $2}')
    used_kb=$(printf '%s\n' "${storage_line}" | awk '{print $3}')
    avail_kb=$(printf '%s\n' "${storage_line}" | awk '{print $4}')
    use_pct=$(printf '%s\n' "${storage_line}" | awk '{print $5}')
    total_gb=$(awk -v v="${total_kb:-0}" 'BEGIN { printf "%.1f", v/1024/1024 }')
    used_gb=$(awk -v v="${used_kb:-0}" 'BEGIN { printf "%.1f", v/1024/1024 }')
    avail_gb=$(awk -v v="${avail_kb:-0}" 'BEGIN { printf "%.1f", v/1024/1024 }')

    # ----- pretty uptime -----
    local uptime_pretty
    uptime_pretty=$(awk -v s="${uptime_secs:-0}" 'BEGIN {
        d = int(s/86400); s -= d*86400
        h = int(s/3600);  s -= h*3600
        m = int(s/60)
        if (d > 0)      printf "%dd %dh %dm", d, h, m
        else if (h > 0) printf "%dh %dm", h, m
        else            printf "%dm", m
    }')

    # ----- ssh reachability (3-second timeout, BatchMode = no password prompt) -----
    local ssh_status="unreachable"
    if ssh_check echo ok >/dev/null 2>&1; then
        ssh_status="reachable"
    fi

    # ----- render -----
    header "Device"
    kv "Model" "${model:-?}"
    kv "Android" "${android:-?}"

    echo
    header "Battery"
    kv "Level" "${level:-?}%"
    kv "Temp" "${temp_c}°C"
    kv "Status" "${status_label}"

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
    kv "WiFi IP" "${ip_addr:-(not detected)}"
    kv "Configured" "${PCTL_HOST}"
    kv "SSH" "${PCTL_HOST}:${PCTL_SSH_PORT} (${ssh_status})"
}
