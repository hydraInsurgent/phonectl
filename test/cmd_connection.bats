#!/usr/bin/env bats
# test/cmd_connection.bats - cmd_ssh, cmd_connect, cmd_status (v0.2 SSH-only).

load 'test_helper'

setup() {
    phonectl_test_setup
    source "${PHONECTL_ROOT}/lib/core/output.sh"
    source "${PHONECTL_ROOT}/lib/core/deps.sh"
    source "${PHONECTL_ROOT}/lib/core/config.sh"
    source "${PHONECTL_ROOT}/lib/core/adb.sh"
    source "${PHONECTL_ROOT}/lib/core/ssh.sh"
    source "${PHONECTL_ROOT}/lib/commands/connection.sh"
    config_load
    config_set host 192.168.1.51
    config_set ssh_port 8022
    config_set adb_port 5555
    config_load
}
teardown() { phonectl_test_teardown; }

# ---- cmd_ssh ---------------------------------------------------------------

@test "cmd_ssh forwards args to ssh_run" {
    STUB_SSH_LOG="${TEST_TMP}/ssh.log" \
        STUB_SSH_OUTPUT="ok" \
        run cmd_ssh uname -a
    [ "$status" -eq 0 ]
    grep -q 'ssh -p 8022 192.168.1.51 uname -a' "${TEST_TMP}/ssh.log"
}

@test "cmd_ssh fails with init hint when no host" {
    rm -f "${XDG_CONFIG_HOME}/phonectl/config"
    config_load
    run cmd_ssh
    [ "$status" -ne 0 ]
    [[ "$output" == *"phonectl init"* ]]
}

# ---- cmd_connect -----------------------------------------------------------

@test "cmd_connect (no args) uses adb_select_device against saved config" {
    STUB_ADB_OUTPUT_FILE="${PHONECTL_FIXTURES}/adb_devices_usb_only.txt" \
        run cmd_connect
    [ "$status" -eq 0 ]
    [[ "$output" == *"Connected via abcd1234efgh"* ]]
}

@test "cmd_connect with port arg updates adb_port before reconnecting" {
    STUB_ADB_OUTPUT="connected to 192.168.1.51:41267" run cmd_connect 41267
    [ "$status" -eq 0 ]
    [[ "$output" == *"Updated adb_port to 41267"* ]]
    [[ "$output" == *"Connected via 192.168.1.51:41267"* ]]

    config_load
    [ "${PCTL_ADB_PORT}" = "41267" ]
}

@test "cmd_connect with non-numeric port arg fails fast" {
    run cmd_connect notaport
    [ "$status" -ne 0 ]
    [[ "$output" == *"must be a number"* ]]
}

@test "cmd_connect failure surfaces all three recovery hints" {
    STUB_ADB_OUTPUT="List of devices attached" run cmd_connect
    [ "$status" -ne 0 ]
    [[ "$output" == *"USB"* ]]
    [[ "$output" == *"connect <new-port>"* ]]
    [[ "$output" == *"phonectl pair"* ]]
}

# ---- cmd_status (SSH-only) ------------------------------------------------
#
# cmd_status makes multiple ssh_run calls for different commands. The ssh
# stub returns the same output for every call, so we override ssh_run
# directly to dispatch by argv to the right fixture - same pattern v0.1
# used for cmd_status testing, just with SSH not ADB this time.

_status_dispatch_ssh_run() {
    case "$*" in
        *"getprop ro.product.model"*)            cat "${PHONECTL_FIXTURES}/ssh_getprop_model.txt" ;;
        *"getprop ro.build.version.release"*)    cat "${PHONECTL_FIXTURES}/ssh_getprop_android.txt" ;;
        *"termux-battery-status"*)               cat "${PHONECTL_FIXTURES}/termux_battery_status.json" ;;
        *"df /storage/emulated/0"*)              cat "${PHONECTL_FIXTURES}/ssh_df_storage.txt" ;;
        *"uptime"*)                              cat "${PHONECTL_FIXTURES}/ssh_uptime.txt" ;;
        *"termux-wifi-connectioninfo"*)          cat "${PHONECTL_FIXTURES}/termux_wifi_connectioninfo.json" ;;
        *)
            echo "unmatched ssh_run argv: $*" >&2
            return 1
            ;;
    esac
}

@test "cmd_status renders all sections against real fixtures" {
    ssh_run() { _status_dispatch_ssh_run "$@"; }
    ssh_check() { return 0; }   # reachability probe always succeeds

    run cmd_status
    [ "$status" -eq 0 ]

    [[ "$output" == *"── Device ──"* ]]
    [[ "$output" == *"RMX3360"* ]]
    [[ "$output" == *"13"* ]]

    [[ "$output" == *"── Battery ──"* ]]
    [[ "$output" == *"1%"* ]]            # level from fixture
    [[ "$output" == *"41"* ]]            # temperature
    [[ "$output" == *"NOT_CHARGING"* ]]
    [[ "$output" == *"UNPLUGGED"* ]]

    [[ "$output" == *"── Storage ──"* ]]
    [[ "$output" == *"GB"* ]]
    [[ "$output" == *"18%"* ]]

    [[ "$output" == *"── Uptime ──"* ]]
    [[ "$output" == *"1:09"* ]]          # parsed from ssh_uptime fixture

    [[ "$output" == *"── Network ──"* ]]
    [[ "$output" == *"192.168.1.51"* ]]
    [[ "$output" == *"-38"* ]]           # rssi
    [[ "$output" == *"780"* ]]           # link_speed_mbps
    [[ "$output" == *"reachable"* ]]
}

@test "cmd_status fails loud when SSH is unreachable" {
    ssh_check() { return 1; }    # reachability probe fails

    run cmd_status
    [ "$status" -ne 0 ]
    [[ "$output" == *"SSH unreachable"* ]]
}

@test "cmd_status with no host configured fails with init hint" {
    rm -f "${XDG_CONFIG_HOME}/phonectl/config"
    config_load
    run cmd_status
    [ "$status" -ne 0 ]
    [[ "$output" == *"phonectl init"* ]]
}
