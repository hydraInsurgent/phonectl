#!/usr/bin/env bats
# test/cmd_pair.bats - first-time wireless ADB pair wizard.
#
# `adb_pair` and `adb_select_device` are overridden inside individual
# tests to control the success/failure scenarios deterministically without
# requiring a live phone in pair mode.

load 'test_helper'

setup() {
    phonectl_test_setup
    source "${PHONECTL_ROOT}/lib/core/output.sh"
    source "${PHONECTL_ROOT}/lib/core/deps.sh"
    source "${PHONECTL_ROOT}/lib/core/config.sh"
    source "${PHONECTL_ROOT}/lib/core/adb.sh"
    source "${PHONECTL_ROOT}/lib/commands/pair.sh"
    config_load
    config_set host 192.168.1.51
    config_set adb_port 5555
    config_load
}
teardown() { phonectl_test_teardown; }

@test "successful pair writes the parsed connect port to adb_port" {
    # Override the adb wrappers so we don't hit the real binary.
    adb_pair() { cat "${PHONECTL_FIXTURES}/adb_pair_success.txt"; }
    adb_select_device() { echo "192.168.1.51:41267"; }

    run cmd_pair <<EOF
37123
123456
EOF
    [ "$status" -eq 0 ]
    [[ "$output" == *"Connect port = 41267"* ]]

    config_load
    [ "${PCTL_ADB_PORT}" = "41267" ]
}

@test "wrong-code failure surfaces the expiry / wrong-port hints" {
    adb_pair() { cat "${PHONECTL_FIXTURES}/adb_pair_wrong_code.txt"; return 1; }

    run cmd_pair <<EOF
37123
999999
EOF
    [ "$status" -ne 0 ]
    [[ "$output" == *"pair failed"* ]]
    [[ "$output" == *"Pairing code expired"* ]]
    [[ "$output" == *"Re-tap 'Pair device'"* ]]
}

@test "non-integer pair port fails fast with hint" {
    run cmd_pair <<EOF
abc
EOF
    [ "$status" -ne 0 ]
    [[ "$output" == *"pair port must be a number"* ]]
}

@test "5-digit code fails fast (must be exactly 6 digits)" {
    run cmd_pair <<EOF
37123
12345
EOF
    [ "$status" -ne 0 ]
    [[ "$output" == *"6 digits"* ]]
}

@test "non-numeric code fails fast" {
    run cmd_pair <<EOF
37123
abcdef
EOF
    [ "$status" -ne 0 ]
    [[ "$output" == *"6 digits"* ]]
}

@test "pair succeeded but adb output unparseable: manual-set hint" {
    adb_pair() { echo "Some unexpected adb output without the success phrase"; }

    run cmd_pair <<EOF
37123
123456
EOF
    [ "$status" -ne 0 ]
    [[ "$output" == *"could not be parsed"* ]]
    [[ "$output" == *"phonectl config adb_port"* ]]
}

@test "pair succeeds but adb_select_device fails: warn + suggest connect" {
    adb_pair() { cat "${PHONECTL_FIXTURES}/adb_pair_success.txt"; }
    adb_select_device() { return 1; }    # post-pair verify fails

    run cmd_pair <<EOF
37123
123456
EOF
    [ "$status" -eq 0 ]    # pair itself succeeded; verify is informational
    [[ "$output" == *"Connect port = 41267"* ]]
    [[ "$output" == *"phonectl connect"* ]]
}

@test "no host configured fails with init hint" {
    rm -f "${XDG_CONFIG_HOME}/phonectl/config"
    config_load
    run cmd_pair <<EOF
37123
123456
EOF
    [ "$status" -ne 0 ]
    [[ "$output" == *"phonectl init"* ]]
}
