#!/usr/bin/env bats
# test/core_ssh.bats - lib/core/ssh.sh

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

@test "ssh_check adds BatchMode and ConnectTimeout" {
    STUB_SSH_LOG="${TEST_TMP}/ssh.log" \
        STUB_SSH_OUTPUT="reachable" \
        run ssh_check echo ping
    [ "$status" -eq 0 ]
    grep -q 'BatchMode=yes' "${TEST_TMP}/ssh.log"
    grep -q 'ConnectTimeout=3' "${TEST_TMP}/ssh.log"
    grep -q 'StrictHostKeyChecking=accept-new' "${TEST_TMP}/ssh.log"
}

@test "ssh_check sends the host and remote command" {
    STUB_SSH_LOG="${TEST_TMP}/ssh.log" \
        STUB_SSH_OUTPUT="reachable" \
        run ssh_check echo ping
    grep -q '192.168.1.51 echo ping' "${TEST_TMP}/ssh.log"
}

@test "ssh_run fails with hint when no host is configured" {
    rm -f "${XDG_CONFIG_HOME}/phonectl/config"
    config_load
    run ssh_run echo hi
    [ "$status" -ne 0 ]
    [[ "$output" == *"phonectl init"* ]]
}
