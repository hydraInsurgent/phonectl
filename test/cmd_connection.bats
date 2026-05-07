#!/usr/bin/env bats
# test/cmd_connection.bats - cmd_ssh, cmd_connect, cmd_status.

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

# ---- cmd_ssh ----------------------------------------------------------------

@test "cmd_ssh forwards to ssh_run with no extra args" {
    STUB_SSH_LOG="${TEST_TMP}/ssh.log" \
        STUB_SSH_OUTPUT="ok" \
        run cmd_ssh
    [ "$status" -eq 0 ]
    grep -q '^ssh -p 8022 192.168.1.51 *$' "${TEST_TMP}/ssh.log"
}

@test "cmd_ssh forwards remote command verbatim" {
    STUB_SSH_LOG="${TEST_TMP}/ssh.log" \
        STUB_SSH_OUTPUT="hi" \
        run cmd_ssh uname -a
    [ "$status" -eq 0 ]
    grep -q 'ssh -p 8022 192.168.1.51 uname -a' "${TEST_TMP}/ssh.log"
}

@test "cmd_ssh fails with hint when no host configured" {
    rm -f "${XDG_CONFIG_HOME}/phonectl/config"
    config_load
    run cmd_ssh
    [ "$status" -ne 0 ]
    [[ "$output" == *"phonectl init"* ]]
}

# ---- cmd_connect ------------------------------------------------------------

@test "cmd_connect prints success when adb says 'connected to'" {
    STUB_ADB_OUTPUT="connected to 192.168.1.51:5555" run cmd_connect
    [ "$status" -eq 0 ]
    [[ "$output" == *"Connected to 192.168.1.51:5555"* ]]
}

@test "cmd_connect prints success when adb says 'already connected'" {
    STUB_ADB_OUTPUT="already connected to 192.168.1.51:5555" run cmd_connect
    [ "$status" -eq 0 ]
    [[ "$output" == *"Connected to 192.168.1.51:5555"* ]]
}

@test "cmd_connect fails with error when adb returns failure" {
    STUB_ADB_OUTPUT="failed to connect to '192.168.1.51:5555': Connection refused" \
        STUB_ADB_EXIT=1 \
        run cmd_connect
    [ "$status" -ne 0 ]
    [[ "$output" == *"could not connect"* ]]
}

@test "cmd_connect mentions host_alt in failure when configured" {
    config_set host_alt 192.168.1.50
    config_load
    STUB_ADB_OUTPUT="failed to connect" STUB_ADB_EXIT=1 run cmd_connect
    [ "$status" -ne 0 ]
    [[ "$output" == *"192.168.1.50"* ]]
}

# ---- cmd_status -------------------------------------------------------------
#
# cmd_status makes 5 different adb_shell calls. The stub adb cannot
# differentiate by argv, so we override `adb_shell` to dispatch on its args
# to the matching real-output fixture from test/fixtures/.

_status_dispatch_adb_shell() {
    case "$*" in
        *"getprop ro.product.model"*)            cat "${PHONECTL_FIXTURES}/getprop_model.txt" ;;
        *"getprop ro.build.version.release"*)    cat "${PHONECTL_FIXTURES}/getprop_android.txt" ;;
        *"dumpsys battery"*)                     cat "${PHONECTL_FIXTURES}/dumpsys_battery.txt" ;;
        *"df /sdcard"*)                          cat "${PHONECTL_FIXTURES}/df_sdcard.txt" ;;
        *"cat /proc/uptime"*)                    cat "${PHONECTL_FIXTURES}/proc_uptime.txt" ;;
        *"ip addr show wlan0"*)                  cat "${PHONECTL_FIXTURES}/ip_addr_wlan0.txt" ;;
        *) echo "stub adb_shell: unmatched: $*" >&2; return 1 ;;
    esac
}

@test "cmd_status renders all sections from real fixtures" {
    adb_shell() { _status_dispatch_adb_shell "$@"; }
    STUB_SSH_OUTPUT="ok" STUB_SSH_EXIT=0 run cmd_status
    [ "$status" -eq 0 ]

    [[ "$output" == *"── Device ──"* ]]
    [[ "$output" == *"RMX3360"* ]]
    [[ "$output" == *"13"* ]]                # Android version

    [[ "$output" == *"── Battery ──"* ]]
    [[ "$output" == *"53%"* ]]
    [[ "$output" == *"34.5°C"* ]]
    [[ "$output" == *"not charging"* ]]      # status code 4

    [[ "$output" == *"── Storage ──"* ]]
    [[ "$output" == *"GB"* ]]
    [[ "$output" == *"12%"* ]]               # Use%

    [[ "$output" == *"── Uptime ──"* ]]

    [[ "$output" == *"── Network ──"* ]]
    [[ "$output" == *"192.168.1.51"* ]]
    [[ "$output" == *"reachable"* ]]
}

@test "cmd_status marks SSH unreachable when ssh_check fails" {
    adb_shell() { _status_dispatch_adb_shell "$@"; }
    STUB_SSH_EXIT=1 run cmd_status
    [ "$status" -eq 0 ]
    [[ "$output" == *"unreachable"* ]]
}
