#!/usr/bin/env bats
# test/core_config.bats - lib/core/config.sh

load 'test_helper'

setup() {
    phonectl_test_setup
    source "${PHONECTL_ROOT}/lib/core/output.sh"
    source "${PHONECTL_ROOT}/lib/core/config.sh"
}
teardown() { phonectl_test_teardown; }

# ---- defaults + load ---------------------------------------------------------

@test "defaults are applied when no config file exists" {
    config_load
    [ "${PCTL_SSH_PORT}" = "8022" ]
    [ "${PCTL_ADB_PORT}" = "5555" ]
    [ "${PCTL_PROOT_DISTRO}" = "ubuntu" ]
    [ -z "${PCTL_HOST}" ]
    [ -z "${PCTL_HOST_ALT}" ]
}

@test "file values override defaults" {
    mkdir -p "${XDG_CONFIG_HOME}/phonectl"
    cat > "${XDG_CONFIG_HOME}/phonectl/config" <<EOF
host=192.168.1.51
host_alt=192.168.1.50
ssh_port=2222
proot_distro=debian
EOF
    config_load
    [ "${PCTL_HOST}" = "192.168.1.51" ]
    [ "${PCTL_HOST_ALT}" = "192.168.1.50" ]
    [ "${PCTL_SSH_PORT}" = "2222" ]
    [ "${PCTL_PROOT_DISTRO}" = "debian" ]
    [ "${PCTL_ADB_PORT}" = "5555" ]    # untouched key keeps default
}

@test "env var overrides win over file" {
    mkdir -p "${XDG_CONFIG_HOME}/phonectl"
    echo "host=192.168.1.51" > "${XDG_CONFIG_HOME}/phonectl/config"
    PHONECTL_HOST=10.0.0.99 config_load
    [ "${PCTL_HOST}" = "10.0.0.99" ]
}

@test "comments and blank lines are ignored" {
    mkdir -p "${XDG_CONFIG_HOME}/phonectl"
    cat > "${XDG_CONFIG_HOME}/phonectl/config" <<EOF
# this is a comment
host=192.168.1.51

  # indented comment
ssh_port=8022
EOF
    config_load
    [ "${PCTL_HOST}" = "192.168.1.51" ]
    [ "${PCTL_SSH_PORT}" = "8022" ]
}

@test "whitespace around key and value is trimmed" {
    mkdir -p "${XDG_CONFIG_HOME}/phonectl"
    printf '   host  =   192.168.1.51   \n' > "${XDG_CONFIG_HOME}/phonectl/config"
    config_load
    [ "${PCTL_HOST}" = "192.168.1.51" ]
}

@test "malformed lines (no '=') are silently skipped" {
    mkdir -p "${XDG_CONFIG_HOME}/phonectl"
    cat > "${XDG_CONFIG_HOME}/phonectl/config" <<EOF
this is garbage
host=192.168.1.51
also bad
EOF
    config_load
    [ "${PCTL_HOST}" = "192.168.1.51" ]
}

@test "unknown keys in the file are ignored, recognized keys still load" {
    mkdir -p "${XDG_CONFIG_HOME}/phonectl"
    cat > "${XDG_CONFIG_HOME}/phonectl/config" <<EOF
host=192.168.1.51
made_up_key=hello
EOF
    config_load
    [ "${PCTL_HOST}" = "192.168.1.51" ]
}

# ---- get ---------------------------------------------------------------------

@test "config_get prints the right value" {
    mkdir -p "${XDG_CONFIG_HOME}/phonectl"
    echo "host=192.168.1.51" > "${XDG_CONFIG_HOME}/phonectl/config"
    config_load
    run config_get host
    [ "$status" -eq 0 ]
    [ "$output" = "192.168.1.51" ]
}

@test "config_get on unknown key returns non-zero with error" {
    config_load
    run config_get bogus
    [ "$status" -ne 0 ]
    [[ "$output" == *"unknown config key"* ]]
}

# ---- set ---------------------------------------------------------------------

@test "config_set creates the config dir and file when missing" {
    config_load
    config_set host 192.168.1.51
    [ -f "${XDG_CONFIG_HOME}/phonectl/config" ]
    grep -q '^host=192.168.1.51$' "${XDG_CONFIG_HOME}/phonectl/config"
}

@test "config_set roundtrips through config_load" {
    config_load
    config_set host 192.168.1.51
    config_set ssh_port 8022
    config_load
    [ "${PCTL_HOST}" = "192.168.1.51" ]
    [ "${PCTL_SSH_PORT}" = "8022" ]
}

@test "config_set replaces an existing key without duplicating" {
    config_load
    config_set host 192.168.1.51
    config_set host 192.168.1.99
    local count
    count=$(grep -c '^host=' "${XDG_CONFIG_HOME}/phonectl/config")
    [ "$count" -eq 1 ]
    grep -q '^host=192.168.1.99$' "${XDG_CONFIG_HOME}/phonectl/config"
}

@test "config_set preserves unrelated keys" {
    config_load
    config_set host 192.168.1.51
    config_set ssh_port 2222
    grep -q '^host=192.168.1.51$' "${XDG_CONFIG_HOME}/phonectl/config"
    grep -q '^ssh_port=2222$' "${XDG_CONFIG_HOME}/phonectl/config"
}

@test "config_set chmods the file 600" {
    config_load
    config_set host 192.168.1.51
    local mode
    mode=$(stat -c '%a' "${XDG_CONFIG_HOME}/phonectl/config")
    [ "$mode" = "600" ]
}

@test "config_set on unknown key returns non-zero with error" {
    config_load
    run config_set bogus value
    [ "$status" -ne 0 ]
    [[ "$output" == *"unknown config key"* ]]
}

@test "config_set expands leading ~/ to \$HOME" {
    config_load
    config_set backup_dir '~/my-backups'
    grep -q "^backup_dir=${HOME}/my-backups$" "${XDG_CONFIG_HOME}/phonectl/config"
}

# ---- require_host ------------------------------------------------------------

@test "config_require_host fails with hint when no host configured" {
    config_load
    run config_require_host
    [ "$status" -ne 0 ]
    [[ "$output" == *"phonectl init"* ]]
}

@test "config_require_host succeeds once host is set" {
    config_load
    config_set host 192.168.1.51
    config_load
    run config_require_host
    [ "$status" -eq 0 ]
}
