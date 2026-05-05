# lib/commands/transfer.sh - cmd_pull, cmd_push.
#
# Both verbs are thin wrappers over `adb pull` / `adb push` with the
# device-id flag pre-filled by `adb_run`. Argument validation is local
# so the user gets a usage hint instead of a cryptic adb error.

cmd_pull() {
    require_deps adb || return 1
    config_require_host || return 1
    if [[ $# -lt 2 ]]; then
        error "usage: phonectl pull <remote> <local>"
        return 1
    fi
    adb_run pull "$1" "$2"
}

cmd_push() {
    require_deps adb || return 1
    config_require_host || return 1
    if [[ $# -lt 2 ]]; then
        error "usage: phonectl push <local> <remote>"
        return 1
    fi
    adb_run push "$1" "$2"
}
