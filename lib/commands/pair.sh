# lib/commands/pair.sh - first-time pair flow for Android 11+ wireless debugging.
#
# Walks the user through the Settings -> Developer options -> Wireless
# debugging -> "Pair device with pairing code" screen, takes the pair
# port + 6-digit code shown, runs `adb pair`, parses the connect port
# from the success line, and writes it to ~/.config/phonectl/config as
# `adb_port`. Subsequent ADB operations work without re-pairing until
# the phone reboots or wireless debugging is toggled off.
#
# The pair port is single-use and different from the connect port.
# Trust persists across reboots - so if the user re-pairs from THIS
# laptop after a previous successful pair, the next `adb connect` will
# work without going through this wizard at all. `phonectl connect
# <new-port>` is the right tool for that case.

cmd_pair() {
    require_deps adb || return 1
    config_require_host || return 1

    info "PhoneCTL pair wizard (Android 11+ wireless debugging)"
    echo
    info "On the phone:"
    info "  1. Settings -> System -> Developer options -> Wireless debugging"
    info "  2. Toggle 'Wireless debugging' ON if it isn't already"
    info "  3. Tap 'Pair device with pairing code'"
    echo
    info "The phone will show an IP+port (the PAIR port - single-use) and a"
    info "6-digit pairing code (expires in ~30 seconds)."
    echo

    # ---- prompt + validate pair port ----
    printf 'Pair port (number after the colon): '
    local pair_port
    read -r pair_port
    if ! [[ "${pair_port}" =~ ^[0-9]+$ ]]; then
        error "pair port must be a number, got: ${pair_port}"
        return 1
    fi

    # ---- prompt + validate code ----
    printf '6-digit pairing code: '
    local code
    read -r code
    if ! [[ "${code}" =~ ^[0-9]{6}$ ]]; then
        error "pairing code must be exactly 6 digits, got: ${code}"
        return 1
    fi

    info "Pairing with ${PCTL_HOST}:${pair_port}..."

    local pair_output rc
    pair_output=$(adb_pair "${PCTL_HOST}:${pair_port}" "${code}")
    rc=$?

    if [[ "${rc}" -ne 0 ]]; then
        error "pair failed."
        info "  ${pair_output}"
        echo
        info "Possible causes:"
        info "  - Wrong pair port (each pair screen generates a new port). Re-tap 'Pair device'."
        info "  - Pairing code expired (~30s timeout). Re-tap 'Pair device' for a fresh one."
        info "  - Wireless debugging is not enabled on the phone."
        return 1
    fi

    # ---- parse the connect port from "Successfully paired to <host>:<port>" ----
    # adb pair's success line format: "Successfully paired to 192.168.1.51:41267 [guid=adb-RMX3360-XXXXXX]"
    # The trailing "[guid=...]" varies between adb versions; the host:port
    # part is stable. Extract just the port (digits after the last colon
    # within that phrase).
    local connect_port
    connect_port=$(printf '%s\n' "${pair_output}" \
        | sed -nE 's/.*Successfully paired to [0-9.]+:([0-9]+).*/\1/p' \
        | head -1)

    if [[ -z "${connect_port}" || ! "${connect_port}" =~ ^[0-9]+$ ]]; then
        error "pair succeeded but the connect port could not be parsed from adb output."
        info "  Raw output: ${pair_output}"
        info "  Set manually: phonectl config adb_port <port>"
        return 1
    fi

    config_set adb_port "${connect_port}"
    config_load

    echo
    success "Paired. Connect port = ${connect_port} (saved to $(config_path))"

    # ---- verify wireless ADB is now reachable ----
    info "Verifying wireless ADB is reachable..."
    local device
    if device=$(adb_select_device 2>/dev/null); then
        success "Connected via ${device}"
    else
        warn "Pair succeeded but adb_select_device did not find the device."
        info "  Try: phonectl connect"
    fi

    echo
    info "Re-run \`phonectl pair\` if the phone reboots or wireless debugging is toggled off."
    info "For 'already paired, port changed' (the common post-reboot case):"
    info "  phonectl connect <new-port>"
}
