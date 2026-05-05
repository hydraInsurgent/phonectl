# lib/commands/init.sh - first-run wizard.
#
# Walks the user through detecting their phone's adb device, picking an IP,
# choosing an SSH port and proot distro, then writes ~/.config/phonectl/config.
#
# The two device-discovery helpers (`_pctl_init_devices_list`,
# `_pctl_init_detect_ip`) are deliberately top-level functions so unit
# tests can override them: a test redefines them after sourcing this file
# and calls `cmd_init` against the override.

# Returns one device id per line, only those in `device` state
# (skips offline / unauthorized).
_pctl_init_devices_list() {
    command adb devices -l 2>/dev/null | awk 'NR>1 && $2=="device" {print $1}'
}

# Returns the IPv4 address bound to wlan0 on the given adb device, or
# an empty string when none can be determined.
_pctl_init_detect_ip() {
    local id="$1"
    command adb -s "${id}" shell ip addr show wlan0 2>/dev/null \
        | awk '/inet / {sub(/\/.*/, "", $2); print $2; exit}'
}

cmd_init() {
    require_deps adb || return 1

    info "PhoneCTL setup wizard"
    echo

    # 1) detect connected adb devices
    local devices
    devices="$(_pctl_init_devices_list)"
    local count=0
    if [[ -n "${devices}" ]]; then
        count=$(printf '%s\n' "${devices}" | wc -l)
    fi

    if [[ "${count}" -eq 0 ]]; then
        error "no adb devices found."
        info "  Connect your phone via USB and enable USB debugging, then re-run \`phonectl init\`."
        info "  If wireless adb is already configured, run \`adb connect <host>:5555\` first."
        return 1
    fi

    # 2) pick a device
    local device_id
    if [[ "${count}" -eq 1 ]]; then
        device_id="${devices}"
        info "Using connected device: ${device_id}"
    else
        info "Multiple devices connected:"
        local i=1 d
        while IFS= read -r d; do
            printf '  %d) %s\n' "${i}" "${d}"
            i=$((i+1))
        done <<< "${devices}"
        printf 'Pick device [1-%d]: ' "${count}"
        local pick
        read -r pick
        device_id="$(printf '%s\n' "${devices}" | sed -n "${pick}p")"
        if [[ -z "${device_id}" ]]; then
            error "invalid pick: ${pick}"
            return 1
        fi
        info "Using device: ${device_id}"
    fi

    # 3) detect IP from wlan0
    local detected_ip=""
    detected_ip="$(_pctl_init_detect_ip "${device_id}" 2>/dev/null || true)"

    # 4) prompt for host (with detected default)
    local host
    if [[ -n "${detected_ip}" ]]; then
        printf 'Phone IP [%s]: ' "${detected_ip}"
        read -r host
        host="${host:-${detected_ip}}"
    else
        warn "could not auto-detect IP from device wlan0"
        printf 'Phone IP: '
        read -r host
        if [[ -z "${host}" ]]; then
            error "host is required"
            return 1
        fi
    fi

    # 5) prompt for SSH port
    printf 'SSH port [8022]: '
    local ssh_port
    read -r ssh_port
    ssh_port="${ssh_port:-8022}"

    # 6) prompt for proot distro
    printf 'proot distro name [ubuntu]: '
    local proot_distro
    read -r proot_distro
    proot_distro="${proot_distro:-ubuntu}"

    # 7) prompt for backup dir
    local default_backup="${HOME}/phone-backup"
    printf 'Backup dir [%s]: ' "${default_backup}"
    local backup_dir
    read -r backup_dir
    backup_dir="${backup_dir:-${default_backup}}"

    # 8) write config + reload
    config_set host "${host}"
    config_set ssh_port "${ssh_port}"
    config_set adb_port 5555
    config_set proot_distro "${proot_distro}"
    config_set backup_dir "${backup_dir}"
    config_load

    echo
    success "Config saved to $(config_path):"
    config_print | sed 's/^/  /'
    echo
    info "Try \`phonectl status\` to verify the connection."
}
