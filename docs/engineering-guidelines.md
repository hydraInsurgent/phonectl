# PhoneCTL Engineering Guidelines

This document describes how the codebase is currently structured and why.
It is not a rulebook - it is context. When something deviates from these patterns,
that is worth a conversation, not necessarily a blocker.

Read `docs/architecture.md` first to understand the system structure.

---

## Core Principle

Every command is a thin wrapper. The dispatcher routes; `lib/core/` provides
shared helpers; `lib/commands/` files only translate user intent into a single
`adb` / `ssh` / `scrcpy` call (or a small sequence). No command should grow
its own parsing, networking, or state-management logic - if it needs to, that
logic belongs in `lib/core/`.

---

## CLI

### Current Patterns

- **Strict mode in every script.** Top of every `.sh` file: `set -euo pipefail`.
  Catches typos and unbound variables before they cause cryptic adb errors.
- **One file per command group** in `lib/commands/`, named after the group
  (e.g. `info.sh`, `transfer.sh`). Each defines functions named `cmd_<verb>`
  (e.g. `cmd_battery`, `cmd_pull`).
- **Helpers live in `lib/core/`** and never call other helpers' private state -
  they communicate via function arguments and return values only.
- **Naming.**
  - Files: `lower-with-no-spaces.sh` (single-word preferred: `info.sh`).
  - Functions: `snake_case`. Public command functions: `cmd_<verb>`.
  - Local variables: `snake_case`. Globals / constants: `UPPER_SNAKE_CASE`.
- **Quote every variable expansion.** `"$host"` not `$host`. Prevents word
  splitting on IPs that contain spaces (rare) and silent failure on empty values.
- **Config access goes through `lib/core/config.sh`.** Commands never `cat` the
  config file directly. Env-var overrides are applied centrally.
- **All user-facing output goes through `lib/core/output.sh`.** Colours, prefixes,
  and error formatting live in one place so the look stays consistent.
- **Dependency check before adb / ssh / scrcpy use.** `lib/core/deps.sh` is
  sourced and called at the top of any command that uses an external binary;
  it prints a one-line install hint on failure and exits non-zero.
- **No magic strings.** Ports, paths, and binary names come from config or
  named constants - never inline literals scattered across files.
- **Errors fail loud.** Non-zero exit + a one-line message starting with `error:`
  on stderr. Never swallow an adb error and pretend success.

### Patterns Not Yet In Use - and When to Consider Them

- **Argument parsing library (e.g. `getopts` patterns or `argbash`).** Add when
  a single command needs more than two positional args or any flags; for v1
  the verbs are simple enough.
- **Logging to a file.** Add when commands grow long enough that scrollback
  is not enough (e.g. when `deploy` lands).
- **Plugin loader (`lib/plugins/`).** Add when user-defined commands ship.
- **JSON output mode (`--json`).** Add when scripting against PhoneCTL becomes
  a real use case.

---

## Testing

- **Framework:** `bats-core` (Bats Automated Testing System for bash). The
  npm package name is `bats`, installed as a devDependency. Run with `npm test`.
- **One test file per command group** in `test/` (e.g. `test/cmd_connection.bats`).
- **Mock external binaries via PATH-prepended stubs.** `test/_stubs/adb` and
  `test/_stubs/ssh` are bash scripts that take their behavior from env vars
  set per test. The stubs are added to `$PATH` once at file-load time by
  `test/test_helper.bash`. Tests never hit a real phone.
- **Stub control via env vars.** Each stub honors:
  - `STUB_<TOOL>_OUTPUT`: literal text to print on stdout
  - `STUB_<TOOL>_OUTPUT_FILE`: path to a file whose contents go to stdout
    (this is how parser tests stream real-phone fixtures into the parser)
  - `STUB_<TOOL>_STDERR`: literal text to print on stderr
  - `STUB_<TOOL>_EXIT`: exit code (default 0)
  - `STUB_<TOOL>_LOG`: append-the-argv path; lets a test assert that the
    real argv was constructed correctly (regex-grep the log file)
- **Real-output fixtures in `test/fixtures/`.** Captured directly from the
  test phone (via `adb shell ...`, `ssh ...` and friends). Parsers are
  exercised against the exact byte stream they will see in production -
  catches Android-shell `\r\n` line endings, OPLUS-specific `dumpsys battery`
  layouts, and Android 13 `df /sdcard` device naming (`/dev/fuse`) which a
  hand-rolled fixture would miss.
- **Function-override pattern for non-stub-able paths.** When a verb makes
  multiple distinct calls (e.g. `cmd_status` calling `adb_shell` for getprop,
  dumpsys, df, ip-addr, uptime), expose the helpers as top-level functions
  and override them inside the test - one switch-on-argv function dispatches
  to the right fixture file. Keeps the stub minimal and the test obvious.
- **Test names describe behaviour:** `@test "battery prints level when adb returns dumpsys output"`.
- **What to test:** parsing logic, argument validation, config-loading,
  exit codes. Skip "does adb exist on this machine" - that is the host's job.
  Real-device validation lives in `SMOKE.md` (manual checklist).
- **Per-test isolation.** `phonectl_test_setup` allocates a fresh tmp dir
  and points `XDG_CONFIG_HOME` and `HOME` at it, so config writes never
  touch the user's real `~/.config/phonectl/config`.

---

## Security Baseline

- Quote all expansions (`"$@"`, `"$2"`) before passing user input to `adb`,
  `ssh`, or `scrcpy` - prevents accidental word splitting and command injection
  from filenames containing spaces.
- Use `--` to terminate flag parsing where the wrapped binary supports it
  (e.g. `adb -s "$device" shell -- "$cmd"`).
- Never log config values from inside commands; the only place that prints
  config is `cmd_config` itself.
- The config file is `chmod 600` on first write (private to the user).

---

## Known Deviations

These are open issues - areas where the current code does not yet match the patterns above.

| Issue | What's Not Yet In Place |
|-------|------------------------|
| - | None identified yet |

---

## When Adding a Feature

A useful checklist - not a gate:

- [ ] Command lives in the right `lib/commands/<group>.sh` file (or a new group is justified)
- [ ] Function is named `cmd_<verb>` and called from the dispatcher
- [ ] Config / paths read via `lib/core/config.sh`, not hardcoded
- [ ] User-facing output goes through `lib/core/output.sh`
- [ ] Dependency check (`require_deps adb` etc.) runs before any external call
- [ ] At least one bats test for the parsing / argument logic
- [ ] `phonectl help` text updated to include the new verb
- [ ] `docs/backlog.md` updated; `docs/architecture.md` still accurate
