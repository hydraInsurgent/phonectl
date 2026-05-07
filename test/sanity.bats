#!/usr/bin/env bats
# test/sanity.bats - prove the harness wires correctly.

load 'test_helper'

setup() { phonectl_test_setup; }
teardown() { phonectl_test_teardown; }

@test "stub adb is found on PATH ahead of any real adb" {
    run command -v adb
    [ "$status" -eq 0 ]
    [[ "$output" == "${PHONECTL_ROOT}/test/_stubs/adb" ]]
}

@test "stub adb echoes STUB_ADB_OUTPUT and returns 0 by default" {
    STUB_ADB_OUTPUT="hello from stub" run adb anything
    [ "$status" -eq 0 ]
    [ "$output" = "hello from stub" ]
}

@test "stub adb honors STUB_ADB_EXIT" {
    STUB_ADB_EXIT=7 run adb anything
    [ "$status" -eq 7 ]
}

@test "stub adb writes argv to STUB_ADB_LOG when set" {
    STUB_ADB_LOG="${TEST_TMP}/adb.log" run adb -s 192.168.1.51:5555 shell echo hi
    [ "$status" -eq 0 ]
    grep -q "adb -s 192.168.1.51:5555 shell echo hi" "${TEST_TMP}/adb.log"
}

@test "stub adb can stream a fixture file via STUB_ADB_OUTPUT_FILE" {
    fixture="${PHONECTL_FIXTURES}/getprop_model.txt"
    [ -f "$fixture" ] || skip "fixture not in place yet"
    STUB_ADB_OUTPUT_FILE="$fixture" run adb shell getprop ro.product.model
    [ "$status" -eq 0 ]
    [ "$output" = "RMX3360" ]
}

@test "stub ssh mirrors the adb stub behavior" {
    STUB_SSH_OUTPUT="ok" STUB_SSH_EXIT=0 run ssh -p 8022 192.168.1.51 echo
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "XDG_CONFIG_HOME is isolated to the per-test tmp dir" {
    [[ "${XDG_CONFIG_HOME}" == "${TEST_TMP}/.config" ]]
    [ -d "${XDG_CONFIG_HOME}" ]
}
