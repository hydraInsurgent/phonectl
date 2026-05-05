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

- **Framework:** `bats-core` (Bats Automated Testing System for bash).
- **One test file per command group** in `test/` (e.g. `test/info.bats`).
- **Mock external binaries** by prepending a stub directory to `PATH` in
  `setup()`. Tests never hit a real phone.
- **Test names describe behaviour:** `@test "battery prints level when adb returns dumpsys output"`.
- **What to test:** parsing logic, argument validation, config-loading,
  exit codes. Skip "does adb exist on this machine" - that is the host's job.

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
