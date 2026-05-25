# lib/core/ssh.sh - thin wrappers around the `ssh` and `scp` binaries.
#
# Host and port come from the loaded config. ssh_run is the user-facing
# path (interactive or one-shot); ssh_check is for reachability probes
# (BatchMode + ConnectTimeout); ssh_pull / ssh_push use scp; and
# ssh_battery_status hits `termux-battery-status` on the phone for the
# v0.2 SSH-default `cmd_status` path.

# Interactive or one-shot SSH to the configured phone.
# Example: ssh_run                  # interactive
#          ssh_run uname -a         # one-shot
ssh_run() {
    config_require_host || return 1
    command ssh -p "${PCTL_SSH_PORT}" "${PCTL_HOST}" "$@"
}

# Reachability check. BatchMode prevents password prompts, ConnectTimeout
# fails fast on unreachable hosts. Returns 0 if the remote command ran.
ssh_check() {
    config_require_host || return 1
    command ssh \
        -p "${PCTL_SSH_PORT}" \
        -o BatchMode=yes \
        -o ConnectTimeout=3 \
        -o StrictHostKeyChecking=accept-new \
        "${PCTL_HOST}" "$@"
}

# Pull a file from the phone over scp. NOTE: scp uses `-P` (capital) for
# port, NOT `-p` like ssh (lowercase -p in scp would preserve mod-times).
# Example: ssh_pull /sdcard/Download/foo.txt /tmp/foo.txt
ssh_pull() {
    config_require_host || return 1
    local remote="$1"
    local local_path="$2"
    command scp -P "${PCTL_SSH_PORT}" \
        "${PCTL_HOST}:${remote}" \
        "${local_path}"
}

# Push a local file to the phone over scp.
# Example: ssh_push /tmp/foo.txt /sdcard/Download/foo.txt
ssh_push() {
    config_require_host || return 1
    local local_path="$1"
    local remote="$2"
    command scp -P "${PCTL_SSH_PORT}" \
        "${local_path}" \
        "${PCTL_HOST}:${remote}"
}

# Run termux-battery-status on the phone over SSH and echo the JSON.
# Surfaces a clear install hint if the tool isn't on the phone yet
# (requires the `termux-api` package PLUS the Termux:API APK).
ssh_battery_status() {
    config_require_host || return 1
    local out rc
    out=$(ssh_run termux-battery-status 2>&1)
    rc=$?
    if [[ "${rc}" -ne 0 ]]; then
        if printf '%s' "${out}" | grep -qE "command not found|No such file"; then
            error "termux-battery-status not available on the phone."
            info "  In Termux on the phone, run: pkg install termux-api"
            info "  Also install the Termux:API APK from F-Droid."
            return 1
        fi
        # Any other failure - surface verbatim so the user can debug.
        printf '%s\n' "${out}" >&2
        return "${rc}"
    fi
    printf '%s' "${out}"
}
