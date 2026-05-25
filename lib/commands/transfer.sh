# lib/commands/transfer.sh - cmd_pull, cmd_push.
#
# v0.2: now uses scp (via ssh_pull / ssh_push) instead of `adb pull/push`.
# SSH path works post-phone-reboot without re-pairing wireless ADB,
# matching the "SSH always" architecture decided post-v0.1.

cmd_pull() {
    require_deps ssh scp || return 1
    config_require_host || return 1
    if [[ $# -lt 2 ]]; then
        error "usage: phonectl pull <remote> <local>"
        return 1
    fi
    ssh_pull "$1" "$2"
}

cmd_push() {
    require_deps ssh scp || return 1
    config_require_host || return 1
    if [[ $# -lt 2 ]]; then
        error "usage: phonectl push <local> <remote>"
        return 1
    fi
    ssh_push "$1" "$2"
}
