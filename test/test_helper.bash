# test/test_helper.bash - common bats setup for PhoneCTL.
#
# Each .bats file should `load 'test_helper'` near the top. The helper
# prepends the stubs directory to PATH so any `adb` / `ssh` resolves to
# our test/_stubs/ scripts, not the real binaries.
#
# Tests that need a clean per-test state should call:
#     setup() { phonectl_test_setup; }
#     teardown() { phonectl_test_teardown; }
# which gives each test its own tmp dir + XDG_CONFIG_HOME and clears any
# stub-control env vars between runs.

# Resolve the repo root from BATS_TEST_DIRNAME (the directory of the .bats
# file currently executing). Fall back to the helper's own location if
# BATS_TEST_DIRNAME is unset (defensive only).
PHONECTL_ROOT="$(cd "${BATS_TEST_DIRNAME:-$(dirname "${BASH_SOURCE[0]}")}/.." && pwd)"
export PHONECTL_ROOT

# Make sure stubs are discovered before any real adb/ssh on PATH.
export PATH="${PHONECTL_ROOT}/test/_stubs:${PATH}"

# Common setup: per-test tmp dir, isolated XDG_CONFIG_HOME so that
# `~/.config/phonectl/config` writes never touch the user's real config.
phonectl_test_setup() {
    TEST_TMP="$(mktemp -d)"
    export TEST_TMP
    export XDG_CONFIG_HOME="${TEST_TMP}/.config"
    export HOME="${TEST_TMP}/home"
    mkdir -p "${XDG_CONFIG_HOME}" "${HOME}"
}

phonectl_test_teardown() {
    if [[ -n "${TEST_TMP:-}" && -d "${TEST_TMP}" ]]; then
        rm -rf "${TEST_TMP}"
    fi
    unset STUB_ADB_OUTPUT STUB_ADB_OUTPUT_FILE STUB_ADB_STDERR STUB_ADB_EXIT STUB_ADB_LOG
    unset STUB_SSH_OUTPUT STUB_SSH_OUTPUT_FILE STUB_SSH_STDERR STUB_SSH_EXIT STUB_SSH_LOG
}

# Run phonectl with a controlled environment. Use this from tests instead of
# bare `run phonectl` so that the call always points at the in-repo bin.
run_phonectl() {
    run "${PHONECTL_ROOT}/bin/phonectl" "$@"
}

# Path to the real-output fixtures captured from the test phone. Tests can
# point STUB_ADB_OUTPUT_FILE at one of these to feed realistic data through
# the parser under test.
PHONECTL_FIXTURES="${PHONECTL_ROOT}/test/fixtures"
export PHONECTL_FIXTURES
