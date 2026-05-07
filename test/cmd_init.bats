#!/usr/bin/env bats
# test/cmd_init.bats - first-run wizard.
#
# `cmd_init` is exercised by sourcing it into the test shell and overriding
# the device-discovery helpers (`_pctl_init_devices_list`, `_pctl_init_detect_ip`)
# so we can drive the wizard deterministically without a real phone.

load 'test_helper'

setup() {
    phonectl_test_setup
    source "${PHONECTL_ROOT}/lib/core/output.sh"
    source "${PHONECTL_ROOT}/lib/core/deps.sh"
    source "${PHONECTL_ROOT}/lib/core/config.sh"
    source "${PHONECTL_ROOT}/lib/commands/init.sh"
    config_load
}
teardown() { phonectl_test_teardown; }

@test "init with no devices fails with hint and non-zero exit" {
    _pctl_init_devices_list() { :; }     # empty output
    run cmd_init
    [ "$status" -ne 0 ]
    [[ "$output" == *"no adb devices"* ]]
    [[ "$output" == *"USB debugging"* ]]
}

@test "init with one device + all defaults writes correct config" {
    _pctl_init_devices_list() { echo "192.168.1.51:5555"; }
    _pctl_init_detect_ip() { echo "192.168.1.51"; }
    run cmd_init <<EOF




EOF
    [ "$status" -eq 0 ]
    config_load
    [ "${PCTL_HOST}" = "192.168.1.51" ]
    [ "${PCTL_SSH_PORT}" = "8022" ]
    [ "${PCTL_ADB_PORT}" = "5555" ]
    [ "${PCTL_PROOT_DISTRO}" = "ubuntu" ]
    [ "${PCTL_BACKUP_DIR}" = "${HOME}/phone-backup" ]
}

@test "init with custom values writes them all" {
    _pctl_init_devices_list() { echo "192.168.1.51:5555"; }
    _pctl_init_detect_ip() { echo "192.168.1.51"; }
    run cmd_init <<EOF
10.0.0.99
2222
debian
/tmp/my-backup
EOF
    [ "$status" -eq 0 ]
    config_load
    [ "${PCTL_HOST}" = "10.0.0.99" ]
    [ "${PCTL_SSH_PORT}" = "2222" ]
    [ "${PCTL_PROOT_DISTRO}" = "debian" ]
    [ "${PCTL_BACKUP_DIR}" = "/tmp/my-backup" ]
}

@test "init with two devices prompts to pick" {
    _pctl_init_devices_list() {
        printf '192.168.1.51:5555\n192.168.1.50:5555\n'
    }
    _pctl_init_detect_ip() { echo "192.168.1.50"; }
    # Pick option 2, then accept all defaults.
    run cmd_init <<EOF
2




EOF
    [ "$status" -eq 0 ]
    config_load
    [ "${PCTL_HOST}" = "192.168.1.50" ]
}

@test "init with invalid pick fails" {
    _pctl_init_devices_list() {
        printf 'dev1\ndev2\n'
    }
    run cmd_init <<EOF
99
EOF
    [ "$status" -ne 0 ]
    [[ "$output" == *"invalid pick"* ]]
}

@test "init when IP cannot be detected requires manual entry" {
    _pctl_init_devices_list() { echo "192.168.1.51:5555"; }
    _pctl_init_detect_ip() { :; }    # empty
    run cmd_init <<EOF



EOF
    [ "$status" -ne 0 ]
    [[ "$output" == *"host is required"* ]]
}

@test "init with detect failure but manual host succeeds" {
    _pctl_init_devices_list() { echo "192.168.1.51:5555"; }
    _pctl_init_detect_ip() { :; }
    run cmd_init <<EOF
192.168.1.42



EOF
    [ "$status" -eq 0 ]
    config_load
    [ "${PCTL_HOST}" = "192.168.1.42" ]
}
