---
title: 'bats-core: Bash Unit-Test Framework Conventions'
category: testing
tags: [bats, testing, unit-tests, bash, test-framework, fixtures]
related:
  - bash-strict-mode-pipefail-and-read.md
first_encountered: PhoneCTL v0.1
created: 2026-05-07
updated: 2026-05-07
---

# bats-core: Bash Unit-Test Framework Conventions

`bats-core` (the actively maintained successor of the original `bats`) is the de-facto bash test framework. Its conventions are small but specific: each `@test` runs in its own subprocess, `run` captures stdout and exit code, `load` sources helper files at parse time. Knowing the model up-front avoids the common "tests pass individually but fail when run together" frustration that comes from misunderstanding scope.

## Mental model

A `.bats` file is bash-with-extra-syntax. The `@test "name" { ... }` blocks are real bash functions; bats parses them, then runs each in its own subprocess so state (variables, working directory, exit traps) cannot leak between tests. The framework provides three primitives:

| Primitive | What it does |
|---|---|
| `run <cmd>` | Run a command, capturing stdout (and optionally stderr) into `$output`, lines into `${lines[@]}`, exit code into `$status`. The command's failure does NOT abort the test - only an explicit assertion does. |
| `load <helper>` | Source `<helper>.bash` at parse time (file-level), making its functions available in every `@test` of the file. |
| `setup() { ... }` and `teardown() { ... }` | Run before/after each test in the file. Use them for per-test fresh state. |

You write assertions with plain bash test syntax: `[ ... ]`, `[[ ... ]]`, `(( ... ))`. There's no special `expect` DSL.

## Why this exists

Pre-bats bash testing was: "write a script that runs your other scripts, check exit codes, manually grep their output, accumulate failures." Every test runner reinvented its own setup/teardown, output capture, and reporting. bats standardises:

- Output capture (no juggling `$(...)` and stderr redirects per test)
- Per-test isolation (subprocess per `@test` means no state bleed)
- Standard test counting and TAP-compatible output (CI-friendly)
- A consistent file extension and structure other tools can target

The original `bats` (Sam Stephenson, ~2011) was unmaintained for years; `bats-core` (community fork from 2017) is the active one. Most documentation and examples target `bats-core` even when they say `bats`.

## How it actually works

### File structure

```
test/
├── test_helper.bash          # functions used across .bats files
├── _stubs/                   # PATH-stubbed external binaries (convention, not required)
│   ├── adb
│   └── ssh
├── fixtures/                 # captured-output test data (convention)
│   └── ...
├── sanity.bats               # one .bats file per topic
└── cmd_status.bats
```

A `.bats` file looks like:

```bash
#!/usr/bin/env bats

load 'test_helper'

setup() {
    # runs before each @test below
    TEST_TMP="$(mktemp -d)"
}

teardown() {
    rm -rf "${TEST_TMP}"
}

@test "describes one specific behaviour" {
    run my_function arg1 arg2
    [ "$status" -eq 0 ]
    [ "$output" = "expected" ]
}
```

### File-level vs test-level scope

This is the most common bats stumble. Top-level code in a `.bats` file (variable assignments, function definitions, `load` calls) executes once at parse time, in the bats parent process. Then each `@test` is forked into its own child process, inheriting the parent's environment.

That means:

- `export FOO=bar` at the top of a `.bats` file: visible in every test (inherited via fork)
- `FOO=bar` (no export) at the top: NOT visible in test bodies (variables don't inherit without export)
- Function definitions at the top: visible in every test
- `setup()` running `FOO=bar` (no export): visible only in the test that follows that setup call

Practical consequence: `load 'test_helper'` typically does its `export PATH=...` at top-level so it's set before any test runs. PhoneCTL's `test/test_helper.bash` follows this pattern.

### `run` semantics

```bash
run my_function arg1 arg2
```

Captures:

- `$status` - exit code
- `$output` - combined stdout (and stderr by default in older bats; configurable in 1.10+)
- `${lines[@]}` - same output split on newlines

After `run`, the test continues regardless of exit code. The test only fails if a subsequent assertion fails. Common patterns:

```bash
run cmd
[ "$status" -eq 0 ]                       # explicit success check
[[ "$output" == *"expected substring"* ]] # substring match
[ "${#lines[@]}" -eq 3 ]                  # 3 lines exactly
```

bats 1.5+ added `run -<exit-code>` to combine "run and assert exit code":

```bash
run -0 cmd        # run and assert exit code 0
run -1 cmd        # run and assert exit code 1
```

bats 1.10+ added `--separate-stderr`:

```bash
run --separate-stderr cmd
[ "$output" = "stdout content" ]
[ "$stderr" = "stderr content" ]
```

If you're targeting older bats (Termux pkg, distro package), you may not have these flags - check version.

### Skipping tests

```bash
@test "feature requires curl" {
    command -v curl >/dev/null || skip "curl not installed"
    run my_curl_function
    [ "$status" -eq 0 ]
}
```

`skip` aborts the current test with a "skipped" status, not a failure. CI counts it but doesn't error.

### Fixtures and stubs

Two complementary patterns for testing CLI parsers:

1. **PATH-stub binaries.** Drop a script named like the real binary into a directory; prepend that directory to `PATH`. The script reads env vars and emits canned output. PhoneCTL's `test/_stubs/adb` and `test/_stubs/ssh` follow this.
2. **Fixture files.** Save real-world output samples to `test/fixtures/foo.txt`. Tests `cat` the fixture into the parser-under-test (or set `STUB_*_OUTPUT_FILE=$fixture` and let the stub stream it). This is "capture-driven testing" - the parser is exercised against the exact bytes production sees.

Both patterns are conventions; bats itself doesn't know about them.

### Function-override pattern

When a function under test calls another function (not an external binary), and you want to control the inner function's behaviour per test:

```bash
@test "outer calls inner with right argv" {
    inner_called_with=""
    inner() { inner_called_with="$*"; }    # override

    outer "hello"

    [ "$inner_called_with" = "hello" ]
}
```

Because each test runs in its own process, the override is isolated. PhoneCTL's `cmd_init` tests use this to stub `_pctl_init_devices_list` and `_pctl_init_detect_ip`.

## Common misconceptions

- **"Tests share state."** They don't. Each `@test` is its own subprocess. Variable changes in one test do not affect others. Setup/teardown exist precisely because state can't carry over.
- **"`run cmd` runs `cmd` in the current shell."** It runs `cmd` in a subshell, captures output, and returns. The current shell's variables don't leak into `cmd`, and `cmd`'s side effects don't leak out (except via `$status`/`$output`).
- **"Failure inside `run` aborts the test."** No - it only captures the exit code. Continuing past a failure is intentional so the test can make multiple assertions. To abort early, add `[ "$status" -eq 0 ]` immediately after `run`.
- **"`load` is the same as `source`."** Almost. `load 'foo'` sources `foo.bash` (note the implicit extension) from a search path that includes the test file's directory. Plain `source` requires explicit paths.
- **"`bats foo.bats` runs only foo.bats."** It does, but watch out: when you have multiple `.bats` files in `test/`, `bats test/` runs them all *in alphabetical order* by default. If you depend on order (you shouldn't), tests can pass locally and fail in CI under different filesystem traversal.
- **"You need to assert `[ "$output" = "exact match" ]`."** Often substring matching with `[[ "$output" == *"keyword"* ]]` is more robust - it doesn't break when colour codes or trailing whitespace change.
- **"bats has assertions like `assertEqual`."** Not in bats-core proper. The optional `bats-assert` library adds them: `assert_equal`, `assert_output`, etc. PhoneCTL doesn't use it; plain bash test syntax is enough at this size.

## When it matters in practice

- **Testing parsing logic of CLI tools.** PhoneCTL's `cmd_status` parses `dumpsys battery`, `df /sdcard`, `/proc/uptime`, etc. With PATH-stubs and fixtures, every parser is exercised against realistic data on every commit, no real device needed.
- **Asserting argv construction in wrappers.** `STUB_<TOOL>_LOG=path` makes the stub write each invocation's argv to a log file. The test then `grep`s the log to assert the wrapper called the underlying binary with the right flags.
- **Testing wizards / interactive scripts.** Pipe a here-doc into `run` to drive prompts. Assert the resulting state (file written, config saved). PhoneCTL's `test/cmd_init.bats` does this.
- **Catching regressions in error paths.** `run -<n>` (or `run` + `[ "$status" -eq <n> ]`) is the assertion for "this command should exit non-zero with this hint". Easy to forget to test until something silently swallows an error.

## Configuration in common stacks

| Distribution method | Command |
|---|---|
| **npm (most projects)** | `npm install --save-dev bats` (the `bats-core` team owns the `bats` npm name) |
| **apt (Debian/Ubuntu)** | `sudo apt install bats` (often older - check version) |
| **brew (macOS)** | `brew install bats-core` (note: explicit `bats-core` here) |
| **From source** | Clone `https://github.com/bats-core/bats-core`, run `./install.sh /usr/local` |
| **Termux** | `pkg install bats` |

CI integration is straightforward because bats outputs TAP. Most CI systems have a TAP reporter built in; alternatively `bats --formatter junit test/` produces JUnit XML.

## Further reading

- **bats-core docs** - https://bats-core.readthedocs.io/. Reference for every flag and pattern.
- **bats-core GitHub** - https://github.com/bats-core/bats-core. Source, issues, and the canonical install path.
- **Optional helper libraries** - `bats-assert` (richer assertions), `bats-support` (shared infra for assert/file libraries), `bats-file` (filesystem assertions). All in the bats-core GitHub org.
- **TAP (Test Anything Protocol)** - the output format bats uses. https://testanything.org/
- **Aaron Maxwell's bats tutorial** - older but still valid as an introduction. https://github.com/sstephenson/bats (note: original repo, points to bats-core for active dev).
