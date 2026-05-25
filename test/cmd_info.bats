#!/usr/bin/env bats
# test/cmd_info.bats - the five v0.3 device-info verbs.
#
# Combined into one file (rather than five) since each verb is small and
# they share the same setup. cmd_battery, cmd_info, cmd_storage use status-
# style multi-field panels; cmd_ip and cmd_uptime print bare one-line values.

load 'test_helper'

setup() {
    phonectl_test_setup
    source "${PHONECTL_ROOT}/lib/core/output.sh"
    source "${PHONECTL_ROOT}/lib/core/deps.sh"
    source "${PHONECTL_ROOT}/lib/core/config.sh"
    source "${PHONECTL_ROOT}/lib/core/ssh.sh"
    source "${PHONECTL_ROOT}/lib/commands/info.sh"
    config_load
    config_set host 192.168.1.51
    config_set ssh_port 8022
    config_load
}
teardown() { phonectl_test_teardown; }

# ---- cmd_battery -----------------------------------------------------------

@test "cmd_battery renders status-style panel from termux-battery-status fixture" {
    # ssh_battery_status uses ssh_run internally; the stub returns whatever
    # STUB_SSH_OUTPUT_FILE points to.
    STUB_SSH_OUTPUT_FILE="${PHONECTL_FIXTURES}/termux_battery_status.json" \
        run cmd_battery
    [ "$status" -eq 0 ]
    [[ "$output" == *"── Battery ──"* ]]
    [[ "$output" == *"Level:"* ]]
    [[ "$output" == *"1%"* ]]            # level=1 in fixture
    [[ "$output" == *"41"* ]]            # temperature=41.0
    [[ "$output" == *"NOT_CHARGING"* ]]
    [[ "$output" == *"UNPLUGGED"* ]]
    [[ "$output" == *"GOOD"* ]]
}

@test "cmd_battery fails with init hint when no host" {
    rm -f "${XDG_CONFIG_HOME}/phonectl/config"
    config_load
    run cmd_battery
    [ "$status" -ne 0 ]
    [[ "$output" == *"phonectl init"* ]]
}

# ---- cmd_info --------------------------------------------------------------

@test "cmd_info renders Model + Android from getprop fixtures" {
    # cmd_info makes two ssh_run calls (model, android). Override ssh_run
    # to dispatch by argv to the right fixture - same pattern v0.2 cmd_status uses.
    ssh_run() {
        case "$*" in
            *"ro.product.model"*)             cat "${PHONECTL_FIXTURES}/ssh_getprop_model.txt" ;;
            *"ro.build.version.release"*)     cat "${PHONECTL_FIXTURES}/ssh_getprop_android.txt" ;;
            *) echo "unmatched: $*" >&2; return 1 ;;
        esac
    }

    run cmd_info
    [ "$status" -eq 0 ]
    [[ "$output" == *"── Device ──"* ]]
    [[ "$output" == *"RMX3360"* ]]
    [[ "$output" == *"13"* ]]
}

@test "cmd_info fails with init hint when no host" {
    rm -f "${XDG_CONFIG_HOME}/phonectl/config"
    config_load
    run cmd_info
    [ "$status" -ne 0 ]
    [[ "$output" == *"phonectl init"* ]]
}

# ---- cmd_ip ----------------------------------------------------------------

@test "cmd_ip prints bare IP value from termux-wifi-connectioninfo fixture" {
    STUB_SSH_OUTPUT_FILE="${PHONECTL_FIXTURES}/termux_wifi_connectioninfo.json" \
        run cmd_ip
    [ "$status" -eq 0 ]
    # Bare value, no header / colour / decoration
    [ "$output" = "192.168.1.51" ]
}

@test "cmd_ip surfaces error when no IP in JSON" {
    # Empty wifi info - cmd_ip should fail with an explanatory error
    STUB_SSH_OUTPUT='{"ip": null, "ssid": "<unknown ssid>"}' run cmd_ip
    [ "$status" -ne 0 ]
    [[ "$output" == *"could not determine"* ]]
}

@test "cmd_ip fails with init hint when no host" {
    rm -f "${XDG_CONFIG_HOME}/phonectl/config"
    config_load
    run cmd_ip
    [ "$status" -ne 0 ]
    [[ "$output" == *"phonectl init"* ]]
}

# ---- cmd_storage -----------------------------------------------------------

@test "cmd_storage (no args) runs 'df /storage/emulated/0'" {
    STUB_SSH_LOG="${TEST_TMP}/ssh.log" \
        STUB_SSH_OUTPUT_FILE="${PHONECTL_FIXTURES}/ssh_df_storage.txt" \
        run cmd_storage
    [ "$status" -eq 0 ]
    grep -q 'df /storage/emulated/0' "${TEST_TMP}/ssh.log"
}

@test "cmd_storage termux alias sends literal '\$PREFIX' over the wire" {
    # Critical: the local shell must NOT expand \$PREFIX (which is empty
    # locally - we don't have Termux here). Single-quoted in the source.
    # The wire payload must contain the literal token \$PREFIX so the
    # phone-side bash expands it.
    STUB_SSH_LOG="${TEST_TMP}/ssh.log" \
        STUB_SSH_OUTPUT_FILE="${PHONECTL_FIXTURES}/ssh_df_storage.txt" \
        run cmd_storage termux
    [ "$status" -eq 0 ]
    grep -q 'df \$PREFIX' "${TEST_TMP}/ssh.log"
}

@test "cmd_storage with arbitrary path argument" {
    STUB_SSH_LOG="${TEST_TMP}/ssh.log" \
        STUB_SSH_OUTPUT_FILE="${PHONECTL_FIXTURES}/ssh_df_storage.txt" \
        run cmd_storage /data
    [ "$status" -eq 0 ]
    grep -q 'df /data' "${TEST_TMP}/ssh.log"
}

@test "cmd_storage renders status-style panel with GB conversion" {
    STUB_SSH_OUTPUT_FILE="${PHONECTL_FIXTURES}/ssh_df_storage.txt" \
        run cmd_storage
    [ "$status" -eq 0 ]
    [[ "$output" == *"── Storage"* ]]
    [[ "$output" == *"Total:"* ]]
    [[ "$output" == *"Used:"* ]]
    [[ "$output" == *"Free:"* ]]
    [[ "$output" == *"GB"* ]]
    [[ "$output" == *"18%"* ]]    # use% from the v0.2 ssh_df_storage.txt fixture
}

@test "cmd_storage fails with init hint when no host" {
    rm -f "${XDG_CONFIG_HOME}/phonectl/config"
    config_load
    run cmd_storage
    [ "$status" -ne 0 ]
    [[ "$output" == *"phonectl init"* ]]
}

# ---- cmd_uptime ------------------------------------------------------------

@test "cmd_uptime prints bare value from ssh_uptime fixture" {
    STUB_SSH_OUTPUT_FILE="${PHONECTL_FIXTURES}/ssh_uptime.txt" \
        run cmd_uptime
    [ "$status" -eq 0 ]
    # Fixture is " 16:16:36 up  1:09,  load average: 6.18, 6.61, 6.55"
    # Parser pulls out "1:09".
    [ "$output" = "1:09" ]
}

@test "cmd_uptime handles long-format ('up N day(s), HH:MM') correctly" {
    # Simulate uptime after a few days of running. Parser pulls out the
    # whole "1 day, 3:45" segment.
    STUB_SSH_OUTPUT=" 16:16:36 up 1 day, 3:45,  1 user,  load average: 0.30, 0.13, 0.07" \
        run cmd_uptime
    [ "$status" -eq 0 ]
    [ "$output" = "1 day, 3:45" ]
}

@test "cmd_uptime fails with init hint when no host" {
    rm -f "${XDG_CONFIG_HOME}/phonectl/config"
    config_load
    run cmd_uptime
    [ "$status" -ne 0 ]
    [[ "$output" == *"phonectl init"* ]]
}
