#!/usr/bin/env bats
# test/cmd_transfer.bats - cmd_pull, cmd_push.

load 'test_helper'

setup() {
    phonectl_test_setup
    source "${PHONECTL_ROOT}/lib/core/output.sh"
    source "${PHONECTL_ROOT}/lib/core/deps.sh"
    source "${PHONECTL_ROOT}/lib/core/config.sh"
    source "${PHONECTL_ROOT}/lib/core/adb.sh"
    source "${PHONECTL_ROOT}/lib/commands/transfer.sh"
    config_load
    config_set host 192.168.1.51
    config_set adb_port 5555
    config_load
}
teardown() { phonectl_test_teardown; }

# ---- cmd_pull --------------------------------------------------------------

@test "cmd_pull constructs correct adb argv" {
    STUB_ADB_LOG="${TEST_TMP}/adb.log" \
        STUB_ADB_OUTPUT_FILE="${PHONECTL_FIXTURES}/adb_pull_success.txt" \
        run cmd_pull /sdcard/foo.txt /tmp/foo.txt
    [ "$status" -eq 0 ]
    grep -q '^adb -s 192.168.1.51:5555 pull /sdcard/foo.txt /tmp/foo.txt$' "${TEST_TMP}/adb.log"
}

@test "cmd_pull surfaces adb stderr on failure" {
    STUB_ADB_OUTPUT_FILE="${PHONECTL_FIXTURES}/adb_pull_missing.txt" \
        STUB_ADB_EXIT=1 \
        run cmd_pull /sdcard/missing.txt /tmp/x
    [ "$status" -ne 0 ]
    [[ "$output" == *"failed to stat"* ]]
}

@test "cmd_pull with no args fails with usage hint" {
    run cmd_pull
    [ "$status" -ne 0 ]
    [[ "$output" == *"usage: phonectl pull"* ]]
}

@test "cmd_pull with one arg fails with usage hint" {
    run cmd_pull /sdcard/foo.txt
    [ "$status" -ne 0 ]
    [[ "$output" == *"usage: phonectl pull"* ]]
}

@test "cmd_pull fails with hint when no host configured" {
    rm -f "${XDG_CONFIG_HOME}/phonectl/config"
    config_load
    run cmd_pull /sdcard/foo /tmp/foo
    [ "$status" -ne 0 ]
    [[ "$output" == *"phonectl init"* ]]
}

# ---- cmd_push --------------------------------------------------------------

@test "cmd_push constructs correct adb argv" {
    STUB_ADB_LOG="${TEST_TMP}/adb.log" \
        STUB_ADB_OUTPUT_FILE="${PHONECTL_FIXTURES}/adb_push_success.txt" \
        run cmd_push /tmp/foo.txt /sdcard/foo.txt
    [ "$status" -eq 0 ]
    grep -q '^adb -s 192.168.1.51:5555 push /tmp/foo.txt /sdcard/foo.txt$' "${TEST_TMP}/adb.log"
}

@test "cmd_push with no args fails with usage hint" {
    run cmd_push
    [ "$status" -ne 0 ]
    [[ "$output" == *"usage: phonectl push"* ]]
}

@test "cmd_push with one arg fails with usage hint" {
    run cmd_push /tmp/foo.txt
    [ "$status" -ne 0 ]
    [[ "$output" == *"usage: phonectl push"* ]]
}
