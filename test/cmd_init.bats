#!/usr/bin/env bats
# test/cmd_init.bats - first-run wizard.
#
# v0.2 simplification: the v0.1 wizard called `adb devices` and parsed
# its output to auto-detect the phone's IP, which made the wizard adb-
# dependent and prone to the piped-stdin hang. v0.2 is pure manual prompts,
# so these tests are simpler - no helper-function overrides, no adb mocks,
# just heredoc-piped prompts and config-file assertions.

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

@test "init with all defaults writes correct config (5 newlines: host then 4 defaults)" {
    run cmd_init <<EOF
192.168.1.51




EOF
    [ "$status" -eq 0 ]
    config_load
    [ "${PCTL_HOST}" = "192.168.1.51" ]
    [ "${PCTL_SSH_PORT}" = "8022" ]
    [ "${PCTL_ADB_PORT}" = "5555" ]
    [ "${PCTL_PROOT_DISTRO}" = "ubuntu" ]
    [ "${PCTL_BACKUP_DIR}" = "${HOME}/phone-backup" ]
}

@test "init with all custom values writes them" {
    run cmd_init <<EOF
10.0.0.99
2222
6666
debian
/tmp/my-backup
EOF
    [ "$status" -eq 0 ]
    config_load
    [ "${PCTL_HOST}" = "10.0.0.99" ]
    [ "${PCTL_SSH_PORT}" = "2222" ]
    [ "${PCTL_ADB_PORT}" = "6666" ]
    [ "${PCTL_PROOT_DISTRO}" = "debian" ]
    [ "${PCTL_BACKUP_DIR}" = "/tmp/my-backup" ]
}

@test "init with empty host errors out" {
    run cmd_init <<EOF




EOF
    [ "$status" -ne 0 ]
    [[ "$output" == *"phone IP is required"* ]]
}

@test "init does not hang under fully-piped stdin (was the v0.1 bug)" {
    # Regression test for the v0.1 piped-stdin hang. v0.2's wizard makes
    # no adb subprocess calls, so the buffering interaction that caused
    # `set -e` to trip after the first prompt is gone.
    run cmd_init <<< "192.168.1.51"$'\n\n\n\n\n'
    [ "$status" -eq 0 ]
    config_load
    [ "${PCTL_HOST}" = "192.168.1.51" ]
    [ "${PCTL_SSH_PORT}" = "8022" ]
}

@test "init makes zero adb calls (no longer adb-dependent)" {
    STUB_ADB_LOG="${TEST_TMP}/adb.log" run cmd_init <<EOF
192.168.1.51




EOF
    [ "$status" -eq 0 ]
    # If adb were called, the stub would have created/written this log.
    [ ! -f "${TEST_TMP}/adb.log" ] || {
        echo "adb was unexpectedly called during cmd_init:"
        cat "${TEST_TMP}/adb.log" >&2
        false
    }
}

@test "init strips incidental whitespace around the host" {
    run cmd_init <<EOF
  192.168.1.51




EOF
    [ "$status" -eq 0 ]
    config_load
    [ "${PCTL_HOST}" = "192.168.1.51" ]
}
