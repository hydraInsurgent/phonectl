#!/usr/bin/env bats
# test/core_deps.bats - lib/core/deps.sh

load 'test_helper'

setup() {
    phonectl_test_setup
    source "${PHONECTL_ROOT}/lib/core/output.sh"
    source "${PHONECTL_ROOT}/lib/core/deps.sh"
}
teardown() { phonectl_test_teardown; }

# ---- require_deps ------------------------------------------------------------

@test "require_deps returns 0 when all binaries are present" {
    run require_deps adb ssh
    [ "$status" -eq 0 ]
}

@test "require_deps returns non-zero when a binary is missing" {
    run require_deps absolutely_no_such_binary_phonectl_test
    [ "$status" -ne 0 ]
    [[ "$output" == *"missing required tool"* ]]
}

@test "require_deps lists every missing binary in the error" {
    run require_deps not_a_real_one not_a_real_two
    [ "$status" -ne 0 ]
    [[ "$output" == *"not_a_real_one"* ]]
    [[ "$output" == *"not_a_real_two"* ]]
}

@test "require_deps prints an install hint after the error" {
    fake="${TEST_TMP}/os-release"
    printf 'ID=ubuntu\n' > "$fake"
    PCTL_OS_RELEASE_PATH="$fake" run require_deps no_such_phonectl_bin
    [[ "$output" == *"sudo apt install"* ]]
}

# ---- distro detection --------------------------------------------------------

@test "distro id reads from PCTL_OS_RELEASE_PATH override" {
    fake="${TEST_TMP}/os-release"
    printf 'ID=fedora\nVERSION_ID=39\n' > "$fake"
    PCTL_OS_RELEASE_PATH="$fake" run _pctl_distro_id
    [ "$output" = "fedora" ]
}

@test "install hint for ubuntu uses apt" {
    fake="${TEST_TMP}/os-release"
    printf 'ID=ubuntu\n' > "$fake"
    PCTL_OS_RELEASE_PATH="$fake" run _pctl_install_hint adb
    [ "$output" = "sudo apt install adb" ]
}

@test "install hint for fedora uses dnf" {
    fake="${TEST_TMP}/os-release"
    printf 'ID=fedora\n' > "$fake"
    PCTL_OS_RELEASE_PATH="$fake" run _pctl_install_hint adb
    [ "$output" = "sudo dnf install adb" ]
}

@test "install hint for arch uses pacman" {
    fake="${TEST_TMP}/os-release"
    printf 'ID=arch\n' > "$fake"
    PCTL_OS_RELEASE_PATH="$fake" run _pctl_install_hint adb
    [ "$output" = "sudo pacman -S adb" ]
}

@test "install hint for unknown distro is generic" {
    fake="${TEST_TMP}/os-release"
    printf 'ID=plan9\n' > "$fake"
    PCTL_OS_RELEASE_PATH="$fake" run _pctl_install_hint adb
    [[ "$output" == *"install adb with your package manager"* ]]
}

@test "install hint handles multiple package names" {
    fake="${TEST_TMP}/os-release"
    printf 'ID=ubuntu\n' > "$fake"
    PCTL_OS_RELEASE_PATH="$fake" run _pctl_install_hint "adb scrcpy"
    [ "$output" = "sudo apt install adb scrcpy" ]
}
