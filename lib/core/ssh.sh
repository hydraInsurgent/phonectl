# lib/core/ssh.sh - thin wrappers around the `ssh` binary.
#
# The host and port come from the loaded config. ssh_run is the user-
# facing path (interactive or one-shot); ssh_check is for reachability
# probes, where we want a fast non-interactive failure rather than a
# password prompt or 30-second hang.

# Interactive or one-shot SSH to the configured phone. Any args after
# the function name are forwarded as the remote command.
# Example: ssh_run                        # interactive
#          ssh_run uname -a               # one-shot
ssh_run() {
    config_require_host || return 1
    command ssh -p "${PCTL_SSH_PORT}" "${PCTL_HOST}" "$@"
}

# Reachability check. Adds:
#   -o BatchMode=yes              # never prompt for a password
#   -o ConnectTimeout=3           # fail fast on unreachable hosts
#   -o StrictHostKeyChecking=accept-new  # auto-accept first-seen keys
# Returns 0 if the remote command ran, non-zero otherwise. Stdout/stderr
# from ssh and the remote command are passed through to the caller.
ssh_check() {
    config_require_host || return 1
    command ssh \
        -p "${PCTL_SSH_PORT}" \
        -o BatchMode=yes \
        -o ConnectTimeout=3 \
        -o StrictHostKeyChecking=accept-new \
        "${PCTL_HOST}" "$@"
}
