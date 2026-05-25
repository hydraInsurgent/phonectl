#!/usr/bin/env bats
# test/cmd_transfer.bats - cmd_pull, cmd_push (v0.2 scp-based).

load 'test_helper'

setup() {
    phonectl_test_setup
    source "${PHONECTL_ROOT}/lib/core/output.sh"
    source "${PHONECTL_ROOT}/lib/core/deps.sh"
    source "${PHONECTL_ROOT}/lib/core/config.sh"
    source "${PHONECTL_ROOT}/lib/core/ssh.sh"
    source "${PHONECTL_ROOT}/lib/commands/transfer.sh"
    config_load
    config_set host 192.168.1.51
    config_set ssh_port 8022
    config_load
}
teardown() { phonectl_test_teardown; }

# ---- cmd_pull --------------------------------------------------------------

@test "cmd_pull constructs scp argv with capital-P port and host:remote" {
    STUB_SCP_LOG="${TEST_TMP}/scp.log" run cmd_pull /sdcard/foo.txt /tmp/foo.txt
    [ "$status" -eq 0 ]
    grep -q '^scp -P 8022 192.168.1.51:/sdcard/foo.txt /tmp/foo.txt$' "${TEST_TMP}/scp.log"
}

@test "cmd_pull surfaces scp error on failure (no-route fixture)" {
    STUB_SCP_OUTPUT_FILE="${PHONECTL_FIXTURES}/scp_no_route.txt" \
        STUB_SCP_EXIT=1 \
        run cmd_pull /sdcard/foo /tmp/foo
    [ "$status" -ne 0 ]
}

@test "cmd_pull with zero args fails with usage hint" {
    run cmd_pull
    [ "$status" -ne 0 ]
    [[ "$output" == *"usage: phonectl pull"* ]]
}

@test "cmd_pull with one arg fails with usage hint" {
    run cmd_pull /sdcard/foo.txt
    [ "$status" -ne 0 ]
    [[ "$output" == *"usage: phonectl pull"* ]]
}

@test "cmd_pull fails with init hint when no host" {
    rm -f "${XDG_CONFIG_HOME}/phonectl/config"
    config_load
    run cmd_pull /sdcard/foo /tmp/foo
    [ "$status" -ne 0 ]
    [[ "$output" == *"phonectl init"* ]]
}

# ---- cmd_push --------------------------------------------------------------

@test "cmd_push constructs scp argv with local then host:remote" {
    STUB_SCP_LOG="${TEST_TMP}/scp.log" run cmd_push /tmp/foo.txt /sdcard/foo.txt
    [ "$status" -eq 0 ]
    grep -q '^scp -P 8022 /tmp/foo.txt 192.168.1.51:/sdcard/foo.txt$' "${TEST_TMP}/scp.log"
}

@test "cmd_push with zero args fails with usage hint" {
    run cmd_push
    [ "$status" -ne 0 ]
    [[ "$output" == *"usage: phonectl push"* ]]
}

@test "cmd_push with one arg fails with usage hint" {
    run cmd_push /tmp/foo.txt
    [ "$status" -ne 0 ]
    [[ "$output" == *"usage: phonectl push"* ]]
}
