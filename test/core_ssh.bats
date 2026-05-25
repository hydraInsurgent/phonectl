#!/usr/bin/env bats
# test/core_ssh.bats - lib/core/ssh.sh
#
# Covers v0.1's ssh_run / ssh_check plus v0.2's ssh_pull, ssh_push,
# ssh_battery_status. The scp wrappers are exercised against test/_stubs/scp.

load 'test_helper'

setup() {
    phonectl_test_setup
    source "${PHONECTL_ROOT}/lib/core/output.sh"
    source "${PHONECTL_ROOT}/lib/core/config.sh"
    source "${PHONECTL_ROOT}/lib/core/ssh.sh"
    config_load
    config_set host 192.168.1.51
    config_set ssh_port 8022
    config_load
}
teardown() { phonectl_test_teardown; }

# ---- ssh_run / ssh_check (carried from v0.1) --------------------------------

@test "ssh_run pre-fills -p ssh_port and the host" {
    STUB_SSH_LOG="${TEST_TMP}/ssh.log" \
        STUB_SSH_OUTPUT="ok" \
        run ssh_run uname -a
    [ "$status" -eq 0 ]
    grep -q '^ssh -p 8022 192.168.1.51 uname -a$' "${TEST_TMP}/ssh.log"
}

@test "ssh_run propagates the wrapped binary's exit code" {
    STUB_SSH_EXIT=99 run ssh_run anything
    [ "$status" -eq 99 ]
}

@test "ssh_check adds BatchMode + ConnectTimeout + accept-new" {
    STUB_SSH_LOG="${TEST_TMP}/ssh.log" \
        STUB_SSH_OUTPUT="reachable" \
        run ssh_check echo ping
    [ "$status" -eq 0 ]
    grep -q 'BatchMode=yes' "${TEST_TMP}/ssh.log"
    grep -q 'ConnectTimeout=3' "${TEST_TMP}/ssh.log"
    grep -q 'StrictHostKeyChecking=accept-new' "${TEST_TMP}/ssh.log"
}

@test "ssh_run fails with hint when no host is configured" {
    rm -f "${XDG_CONFIG_HOME}/phonectl/config"
    config_load
    run ssh_run echo hi
    [ "$status" -ne 0 ]
    [[ "$output" == *"phonectl init"* ]]
}

# ---- ssh_pull / ssh_push (v0.2 scp wrappers) --------------------------------

@test "ssh_pull constructs 'scp -P <port> host:<remote> <local>'" {
    STUB_SCP_LOG="${TEST_TMP}/scp.log" \
        run ssh_pull /sdcard/foo.txt /tmp/foo.txt
    [ "$status" -eq 0 ]
    # Note: scp's port flag is CAPITAL -P (scp -p is preserve-mtimes).
    grep -q '^scp -P 8022 192.168.1.51:/sdcard/foo.txt /tmp/foo.txt$' "${TEST_TMP}/scp.log"
}

@test "ssh_push constructs 'scp -P <port> <local> host:<remote>'" {
    STUB_SCP_LOG="${TEST_TMP}/scp.log" \
        run ssh_push /tmp/foo.txt /sdcard/foo.txt
    [ "$status" -eq 0 ]
    grep -q '^scp -P 8022 /tmp/foo.txt 192.168.1.51:/sdcard/foo.txt$' "${TEST_TMP}/scp.log"
}

@test "ssh_pull propagates scp exit code" {
    STUB_SCP_EXIT=1 \
        STUB_SCP_OUTPUT_FILE="${PHONECTL_FIXTURES}/scp_no_route.txt" \
        run ssh_pull /sdcard/foo /tmp/foo
    [ "$status" -ne 0 ]
}

@test "ssh_pull fails with hint when no host is configured" {
    rm -f "${XDG_CONFIG_HOME}/phonectl/config"
    config_load
    run ssh_pull /sdcard/foo /tmp/foo
    [ "$status" -ne 0 ]
    [[ "$output" == *"phonectl init"* ]]
}

# ---- ssh_battery_status (v0.2) ----------------------------------------------

@test "ssh_battery_status returns the JSON from the phone" {
    STUB_SSH_OUTPUT_FILE="${PHONECTL_FIXTURES}/termux_battery_status.json" \
        run ssh_battery_status
    [ "$status" -eq 0 ]
    [[ "$output" == *'"level"'* ]]
    [[ "$output" == *'"temperature"'* ]]
}

@test "ssh_battery_status surfaces install hint when termux-api is missing" {
    STUB_SSH_OUTPUT="bash: termux-battery-status: command not found" \
        STUB_SSH_EXIT=127 \
        run ssh_battery_status
    [ "$status" -ne 0 ]
    [[ "$output" == *"pkg install termux-api"* ]]
}

@test "ssh_battery_status surfaces non-missing errors verbatim" {
    STUB_SSH_STDERR="some other ssh error" \
        STUB_SSH_EXIT=255 \
        run ssh_battery_status
    [ "$status" -ne 0 ]
}
