# lib/core/adb.sh - thin wrappers around the `adb` binary.
#
# All commands that talk to the phone over adb go through adb_run /
# adb_shell. Both route through `adb_select_device` which:
#   1. Prefers a USB-connected device (no port-rotation issues, no pair
#      flow needed - this is the daily-use happy path when the user is
#      sitting at their desk with a cable).
#   2. Falls back to wireless at the saved `adb_port` (set by
#      `phonectl pair` via the Android 11+ pair flow).
#   3. Tries `host_alt` as a final fallback for the wireless path.
#
# `command adb` is used (not bare `adb`) to bypass any function or alias
# named `adb`; PATH lookup still applies, so the test stub at
# test/_stubs/adb is honoured when tests prepend it.

# Select an adb device id, preferring USB. Echoes the resolved id
# ("<usb-serial>" or "<host>:<port>") on success; non-zero on failure.
#
# Detection logic:
#  - `adb devices` lines have form: "<id>\tdevice\t..." for ready devices.
#  - USB ids have no ":<port>" suffix (e.g. "abcd1234efgh").
#  - Wireless ids do (e.g. "192.168.1.51:41267").
#  - We pick the first entry whose state is "device" and whose id does
#    NOT match /:[0-9]+$/ - that's the USB-first preference.
adb_select_device() {
    config_require_host || return 1

    local usb_id
    usb_id=$(command adb devices 2>/dev/null \
        | awk 'NR>1 && $2=="device" && $1 !~ /:[0-9]+$/ { print $1; exit }')
    if [[ -n "${usb_id}" ]]; then
        printf '%s\n' "${usb_id}"
        return 0
    fi

    # No USB present. Try wireless using the saved port (which `pair`
    # rewrites after every Android-11+ pair). If `adb_port` is empty
    # the user hasn't paired yet - fail and let the caller suggest `pair`.
    if [[ -z "${PCTL_ADB_PORT:-}" ]]; then
        return 1
    fi

    # Build the candidate host list: primary first, then host_alt.
    local hosts=("${PCTL_HOST}")
    [[ -n "${PCTL_HOST_ALT:-}" ]] && hosts+=("${PCTL_HOST_ALT}")

    local h target out
    for h in "${hosts[@]}"; do
        target="${h}:${PCTL_ADB_PORT}"

        # Already-connected fast path: avoid the network round-trip
        # of an extra `adb connect` if the device is in `adb devices`.
        # Use awk (not grep with $ anchor) because `adb devices -l` can
        # append product/model/transport-id columns after "device", so
        # an end-of-line anchor on `device` would miss the match.
        if command adb devices 2>/dev/null \
            | awk -v t="${target}" '$1==t && $2=="device" { f=1; exit } END { exit !f }'; then
            printf '%s\n' "${target}"
            return 0
        fi

        # Try to bring it online. Both "connected to ..." (fresh) and
        # "already connected to ..." (idempotent) count as success.
        out=$(command adb connect "${target}" 2>&1)
        if printf '%s' "${out}" | grep -qE '(connected to|already connected)'; then
            printf '%s\n' "${target}"
            return 0
        fi
    done

    return 1
}

# Run an arbitrary adb subcommand against the selected device.
# Example: adb_run pull /sdcard/foo.txt /tmp/foo.txt
adb_run() {
    local device
    if ! device=$(adb_select_device); then
        error "no adb device available. Plug in via USB, or run \`phonectl pair\` for wireless."
        return 1
    fi
    command adb -s "${device}" "$@"
}

# Run a shell command on the selected device. The `--` separates adb's
# own flags from the remote command so a remote arg starting with `-`
# can't be misinterpreted.
# Example: adb_shell getprop ro.product.model
adb_shell() {
    local device
    if ! device=$(adb_select_device); then
        error "no adb device available. Plug in via USB, or run \`phonectl pair\` for wireless."
        return 1
    fi
    command adb -s "${device}" shell -- "$@"
}

# Pair flow (Android 11+ wireless debugging).
# Args:
#   $1 = "<host>:<pair-port>"  (the *pair* port shown on the phone, NOT
#                               the connect port that lands in adb_port)
#   $2 = 6-digit pairing code  (shown on the same phone screen)
#
# Returns adb's output (success line includes the connect port for the
# caller - `cmd_pair` - to parse: "Successfully paired to <host>:<connect-port>").
# `adb pair` accepts the code as a positional arg since adb 1.0.41+
# (the version on the user's host); no stdin pipe needed.
adb_pair() {
    local target="$1"
    local code="$2"
    command adb pair "${target}" "${code}" 2>&1
}
