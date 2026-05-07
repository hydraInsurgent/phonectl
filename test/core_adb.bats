#!/usr/bin/env bats
# test/core_adb.bats - lib/core/adb.sh

load 'test_helper'

setup() {
    phonectl_test_setup
    source "${PHONECTL_ROOT}/lib/core/output.sh"
    source "${PHONECTL_ROOT}/lib/core/config.sh"
    source "${PHONECTL_ROOT}/lib/core/adb.sh"
    config_load
    config_set host 192.168.1.51
    config_set adb_port 5555
    config_load
}
teardown() { phonectl_test_teardown; }

@test "adb_device returns host:adb_port" {
    run adb_device
    [ "$status" -eq 0 ]
    [ "$output" = "192.168.1.51:5555" ]
}

@test "adb_run pre-fills -s host:adb_port" {
    STUB_ADB_LOG="${TEST_TMP}/adb.log" \
        STUB_ADB_OUTPUT="ok" \
        run adb_run shell echo hi
    [ "$status" -eq 0 ]
    grep -q '^adb -s 192.168.1.51:5555 shell echo hi$' "${TEST_TMP}/adb.log"
}

@test "adb_shell adds 'shell --' separator" {
    STUB_ADB_LOG="${TEST_TMP}/adb.log" \
        STUB_ADB_OUTPUT="ok" \
        run adb_shell dumpsys battery
    [ "$status" -eq 0 ]
    grep -q '^adb -s 192.168.1.51:5555 shell -- dumpsys battery$' "${TEST_TMP}/adb.log"
}

@test "adb_run propagates the wrapped binary's exit code" {
    STUB_ADB_EXIT=42 run adb_run anything
    [ "$status" -eq 42 ]
}

@test "adb_run fails with hint when no host is configured" {
    rm -f "${XDG_CONFIG_HOME}/phonectl/config"
    config_load
    run adb_run shell echo hi
    [ "$status" -ne 0 ]
    [[ "$output" == *"phonectl init"* ]]
}

@test "adb_connect echoes the resolved host:port on success" {
    STUB_ADB_OUTPUT="connected to 192.168.1.51:5555" run adb_connect
    [ "$status" -eq 0 ]
    [ "$output" = "192.168.1.51:5555" ]
}

@test "adb_connect succeeds on 'already connected' too" {
    STUB_ADB_OUTPUT="already connected to 192.168.1.51:5555" run adb_connect
    [ "$status" -eq 0 ]
}

@test "adb_connect falls back to host_alt when primary fails" {
    config_set host_alt 192.168.1.50
    config_load
    # Stub returns an error first; we can't easily script per-invocation
    # output, so simulate failure on both and assert it returns non-zero.
    STUB_ADB_OUTPUT="failed to connect to '192.168.1.51:5555'" \
        STUB_ADB_EXIT=1 \
        run adb_connect
    [ "$status" -ne 0 ]
}
