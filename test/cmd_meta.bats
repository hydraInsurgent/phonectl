#!/usr/bin/env bats
# test/cmd_meta.bats - help, version, unknown-command behavior of bin/phonectl.

load 'test_helper'

setup() { phonectl_test_setup; }
teardown() { phonectl_test_teardown; }

@test "phonectl with no args prints help and exits 0" {
    run_phonectl
    [ "$status" -eq 0 ]
    [[ "$output" == *"phonectl - manage"* ]]
    [[ "$output" == *"USAGE"* ]]
    [[ "$output" == *"CONNECTION"* ]]
}

@test "phonectl help prints help" {
    run_phonectl help
    [ "$status" -eq 0 ]
    [[ "$output" == *"USAGE"* ]]
}

@test "phonectl --help works" {
    run_phonectl --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"USAGE"* ]]
}

@test "phonectl -h works" {
    run_phonectl -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"USAGE"* ]]
}

@test "phonectl version prints package.json version" {
    run_phonectl version
    [ "$status" -eq 0 ]
    # Compare against whatever package.json currently has - avoids
    # bumping this test on every version increment.
    local expected
    expected=$(grep -E '"version"[[:space:]]*:' "${PHONECTL_ROOT}/package.json" \
        | head -1 \
        | sed -E 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')
    [ "$output" = "phonectl ${expected}" ]
}

@test "phonectl --version works" {
    run_phonectl --version
    [ "$status" -eq 0 ]
    # Compare against whatever package.json currently has - avoids
    # bumping this test on every version increment.
    local expected
    expected=$(grep -E '"version"[[:space:]]*:' "${PHONECTL_ROOT}/package.json" \
        | head -1 \
        | sed -E 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')
    [ "$output" = "phonectl ${expected}" ]
}

@test "phonectl -V works" {
    run_phonectl -V
    [ "$status" -eq 0 ]
    # Compare against whatever package.json currently has - avoids
    # bumping this test on every version increment.
    local expected
    expected=$(grep -E '"version"[[:space:]]*:' "${PHONECTL_ROOT}/package.json" \
        | head -1 \
        | sed -E 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')
    [ "$output" = "phonectl ${expected}" ]
}

@test "unknown command exits non-zero with helpful error" {
    run_phonectl notarealverb
    [ "$status" -ne 0 ]
    [[ "$output" == *"unknown command: notarealverb"* ]]
    [[ "$output" == *"phonectl help"* ]]
}
