#!/usr/bin/env bats
# test/core_adb.bats - lib/core/adb.sh
#
# In v0.2 the adb wrappers route through `adb_select_device` (USB-first,
# wireless-fallback). Tests exercise both paths via STUB_ADB_OUTPUT_FILE
# pointing at real-output fixtures captured in test/fixtures/.

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

# ---- adb_select_device ------------------------------------------------------

@test "adb_select_device returns USB id when a USB device is connected" {
    STUB_ADB_OUTPUT_FILE="${PHONECTL_FIXTURES}/adb_devices_usb_only.txt" \
        run adb_select_device
    [ "$status" -eq 0 ]
    [ "$output" = "abcd1234efgh" ]
}

@test "adb_select_device prefers USB over wireless when both present" {
    STUB_ADB_OUTPUT_FILE="${PHONECTL_FIXTURES}/adb_devices_mixed.txt" \
        run adb_select_device
    [ "$status" -eq 0 ]
    # USB serial comes first in the awk scan, wins over the host:port row
    [ "$output" = "abcd1234efgh" ]
}

@test "adb_select_device returns wireless id when already connected and no USB" {
    STUB_ADB_OUTPUT_FILE="${PHONECTL_FIXTURES}/adb_devices.txt" \
        run adb_select_device
    [ "$status" -eq 0 ]
    [ "$output" = "192.168.1.51:5555" ]
}

@test "adb_select_device falls through to adb connect when wireless not yet attached" {
    # Stub returns the same value for both `adb devices` and `adb connect`.
    # When the value matches "(connected to|already connected)", the
    # connect-fallback branch succeeds.
    STUB_ADB_OUTPUT="connected to 192.168.1.51:5555" run adb_select_device
    [ "$status" -eq 0 ]
    [ "$output" = "192.168.1.51:5555" ]
}

@test "adb_select_device fails when no device anywhere" {
    STUB_ADB_OUTPUT="List of devices attached" run adb_select_device
    [ "$status" -ne 0 ]
}

@test "adb_select_device fails when adb_port is empty (not yet paired)" {
    config_set adb_port ""
    config_load
    # Even with USB visible the function bails early if adb_port unset?
    # No - USB is checked FIRST, before the adb_port guard. So USB still
    # works without pairing. This test asserts the wireless-fallback case
    # specifically: empty STUB so no USB found, then bail.
    STUB_ADB_OUTPUT="List of devices attached" run adb_select_device
    [ "$status" -ne 0 ]
}

# ---- adb_run / adb_shell argv ------------------------------------------------

@test "adb_run forwards args with -s <selected device>" {
    STUB_ADB_LOG="${TEST_TMP}/adb.log" \
        STUB_ADB_OUTPUT_FILE="${PHONECTL_FIXTURES}/adb_devices.txt" \
        run adb_run pull /sdcard/foo.txt /tmp/foo.txt
    [ "$status" -eq 0 ]
    grep -q "^adb -s 192.168.1.51:5555 pull /sdcard/foo.txt /tmp/foo.txt$" "${TEST_TMP}/adb.log"
}

@test "adb_shell adds 'shell --' separator after -s <selected device>" {
    STUB_ADB_LOG="${TEST_TMP}/adb.log" \
        STUB_ADB_OUTPUT_FILE="${PHONECTL_FIXTURES}/adb_devices.txt" \
        run adb_shell dumpsys battery
    [ "$status" -eq 0 ]
    grep -q "^adb -s 192.168.1.51:5555 shell -- dumpsys battery$" "${TEST_TMP}/adb.log"
}

@test "adb_run fails with the user-facing hint when no device available" {
    STUB_ADB_OUTPUT="List of devices attached" run adb_run shell echo hi
    [ "$status" -ne 0 ]
    [[ "$output" == *"phonectl pair"* ]]
}

@test "adb_run fails with hint when no host configured" {
    rm -f "${XDG_CONFIG_HOME}/phonectl/config"
    config_load
    run adb_run shell echo hi
    [ "$status" -ne 0 ]
    [[ "$output" == *"phonectl init"* ]]
}

# ---- adb_pair ---------------------------------------------------------------

@test "adb_pair calls 'adb pair <host>:<port> <code>' (positional code)" {
    STUB_ADB_LOG="${TEST_TMP}/adb.log" \
        STUB_ADB_OUTPUT_FILE="${PHONECTL_FIXTURES}/adb_pair_success.txt" \
        run adb_pair 192.168.1.51:37123 123456
    [ "$status" -eq 0 ]
    grep -q "^adb pair 192.168.1.51:37123 123456$" "${TEST_TMP}/adb.log"
}

@test "adb_pair echoes adb output for the caller to parse" {
    STUB_ADB_OUTPUT_FILE="${PHONECTL_FIXTURES}/adb_pair_success.txt" \
        run adb_pair 192.168.1.51:37123 123456
    [ "$status" -eq 0 ]
    [[ "$output" == *"Successfully paired to 192.168.1.51:41267"* ]]
}

@test "adb_pair surfaces wrong-code failure" {
    STUB_ADB_OUTPUT_FILE="${PHONECTL_FIXTURES}/adb_pair_wrong_code.txt" \
        STUB_ADB_EXIT=1 \
        run adb_pair 192.168.1.51:37123 999999
    [ "$status" -ne 0 ]
    [[ "$output" == *"Failed: Wrong pairing code"* ]]
}
