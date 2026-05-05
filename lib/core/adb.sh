# lib/core/adb.sh - thin wrappers around the `adb` binary.
#
# All commands that talk to the phone over adb go through adb_run /
# adb_shell so the `-s host:adb_port` flag is added in one place. The
# config helpers (config_load / config_require_host) must have been called
# by the dispatcher before any of these are invoked.
#
# `command adb` is used (not bare `adb`) to bypass any function or alias
# named `adb` that the user might have defined; PATH lookup still applies,
# so the test stub at test/_stubs/adb is honored when tests prepend it.

adb_device() {
    printf '%s:%s\n' "${PCTL_HOST}" "${PCTL_ADB_PORT}"
}

# Run any adb subcommand against the configured device.
# Example: adb_run pull /sdcard/foo.txt /tmp/foo.txt
adb_run() {
    config_require_host || return 1
    command adb -s "$(adb_device)" "$@"
}

# Run a shell command on the device. The `--` separates adb's own flags
# from the remote command, so a remote arg starting with `-` cannot be
# misinterpreted by adb.
# Example: adb_shell dumpsys battery
adb_shell() {
    config_require_host || return 1
    command adb -s "$(adb_device)" shell -- "$@"
}

# Try to bring the device online via TCP, falling back to host_alt if
# the primary IP fails. Echoes the resolved "host:port" on stdout for
# the caller to use; returns non-zero if neither host responds.
adb_connect() {
    config_require_host || return 1

    local primary="${PCTL_HOST}:${PCTL_ADB_PORT}"
    local out
    out="$(command adb connect "${primary}" 2>&1)"
    if printf '%s' "${out}" | grep -q -E '(connected to|already connected)'; then
        printf '%s\n' "${primary}"
        return 0
    fi

    if [[ -n "${PCTL_HOST_ALT:-}" ]]; then
        local alt="${PCTL_HOST_ALT}:${PCTL_ADB_PORT}"
        out="$(command adb connect "${alt}" 2>&1)"
        if printf '%s' "${out}" | grep -q -E '(connected to|already connected)'; then
            printf '%s\n' "${alt}"
            return 0
        fi
    fi

    return 1
}
