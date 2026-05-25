# lib/commands/init.sh - first-run wizard.
#
# v0.2 rewrite. The v0.1 wizard called `adb devices` to auto-detect a
# USB-connected phone's IP, which had two problems:
#   1. It required the user to plug in via USB (impractical for a headless
#      home-server install done from the laptop).
#   2. It hung after the first prompt under piped stdin (set -e + read +
#      subprocess buffering interaction; documented in
#      docs/learnings/bash-strict-mode-pipefail-and-read.md).
#
# This version is pure manual prompts. The user already knows their phone's
# IP from the DHCP reservation done during `guides/phone-server-setup.md`,
# so we just ask. No adb calls; no `require_deps adb`.
#
# `adb_port=5555` is written as a placeholder default. The real wireless
# adb port is dynamic on Android 11+ and gets overwritten by `phonectl pair`.

cmd_init() {
    info "PhoneCTL setup wizard"
    echo
    info "Writes ~/.config/phonectl/config. Re-run anytime to redo, or edit"
    info "individual values with \`phonectl config <key> <value>\`."
    echo

    # ---- host (required) ----
    printf 'Phone IP: '
    local host
    read -r host
    # Strip incidental whitespace from terminal paste mishaps.
    host="${host// /}"
    if [[ -z "${host}" ]]; then
        error "phone IP is required (e.g. 192.168.1.51 from your DHCP reservation)"
        return 1
    fi

    # ---- ssh_port (Termux's default) ----
    printf 'SSH port [8022]: '
    local ssh_port
    read -r ssh_port
    ssh_port="${ssh_port:-8022}"

    # ---- adb_port (placeholder; `phonectl pair` overwrites on Android 11+) ----
    printf 'ADB wireless port [5555]: '
    local adb_port
    read -r adb_port
    adb_port="${adb_port:-5555}"

    # ---- proot_distro ----
    printf 'proot distro name [ubuntu]: '
    local proot_distro
    read -r proot_distro
    proot_distro="${proot_distro:-ubuntu}"

    # ---- backup_dir ----
    local default_backup="${HOME}/phone-backup"
    printf 'Backup dir [%s]: ' "${default_backup}"
    local backup_dir
    read -r backup_dir
    backup_dir="${backup_dir:-${default_backup}}"

    # Persist + reload
    config_set host "${host}"
    config_set ssh_port "${ssh_port}"
    config_set adb_port "${adb_port}"
    config_set proot_distro "${proot_distro}"
    config_set backup_dir "${backup_dir}"
    config_load

    echo
    success "Config saved to $(config_path):"
    config_print | sed 's/^/  /'
    echo
    info "Next steps:"
    info "  phonectl ssh        - SSH into Termux on the phone"
    info "  phonectl status     - one-panel device snapshot (SSH path)"
    info "  phonectl pair       - register wireless ADB (Android 11+ pair flow)"
}
