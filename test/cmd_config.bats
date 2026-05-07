#!/usr/bin/env bats
# test/cmd_config.bats - phonectl config (show / get / set).

load 'test_helper'

setup() { phonectl_test_setup; }
teardown() { phonectl_test_teardown; }

@test "config with no args prints all known keys" {
    mkdir -p "${XDG_CONFIG_HOME}/phonectl"
    cat > "${XDG_CONFIG_HOME}/phonectl/config" <<EOF
host=192.168.1.51
ssh_port=8022
EOF
    run_phonectl config
    [ "$status" -eq 0 ]
    [[ "$output" == *"host=192.168.1.51"* ]]
    [[ "$output" == *"ssh_port=8022"* ]]
    [[ "$output" == *"adb_port=5555"* ]]    # default still shown
}

@test "config <key> prints just that value" {
    mkdir -p "${XDG_CONFIG_HOME}/phonectl"
    echo "host=192.168.1.51" > "${XDG_CONFIG_HOME}/phonectl/config"
    run_phonectl config host
    [ "$status" -eq 0 ]
    [ "$output" = "192.168.1.51" ]
}

@test "config <key> <value> writes and re-reads correctly" {
    run_phonectl config host 192.168.1.51
    [ "$status" -eq 0 ]
    grep -q '^host=192.168.1.51$' "${XDG_CONFIG_HOME}/phonectl/config"

    run_phonectl config host
    [ "$output" = "192.168.1.51" ]
}

@test "config bogus_key fails with error" {
    run_phonectl config bogus_key
    [ "$status" -ne 0 ]
    [[ "$output" == *"unknown config key"* ]]
}

@test "config too many args fails with usage" {
    run_phonectl config a b c d
    [ "$status" -ne 0 ]
    [[ "$output" == *"usage"* ]]
}

@test "PHONECTL_HOST env override beats the file in cmd_config output" {
    mkdir -p "${XDG_CONFIG_HOME}/phonectl"
    echo "host=192.168.1.51" > "${XDG_CONFIG_HOME}/phonectl/config"
    PHONECTL_HOST=10.0.0.99 run_phonectl config host
    [ "$status" -eq 0 ]
    [ "$output" = "10.0.0.99" ]
}
