---
title: 'Bash Strict Mode: `set -euo pipefail` and Its Carve-Outs'
category: bash
tags: [bash, error-handling, pipefail, strict-mode, edge-cases, signals]
related: []
first_encountered: PhoneCTL v0.1 wizard piped-input bug
created: 2026-05-07
updated: 2026-05-07
---

# Bash Strict Mode: `set -euo pipefail` and Its Carve-Outs

The shebang-and-strict-mode trio `set -euo pipefail` is the bash equivalent of "treat warnings as errors" - it converts a class of silent footguns into hard failures. But strict mode has known carve-outs where the script keeps running after a failure you'd expect it to stop on. PhoneCTL's `phonectl init` wizard hit one of these (the wizard hangs after the first prompt under pure piped stdin), so it's worth understanding the *exact* boundaries.

## Mental model

Three independent options doing different work:

| Option | Trips on | What it catches |
|---|---|---|
| `set -e` | Any unchecked command returning non-zero | Silent failures from wrong arg, missing file, broken pipe |
| `set -u` | Any expansion of an unset variable | Typos in variable names |
| `set -o pipefail` | Any command in a pipeline returning non-zero | Failures hidden by a successful final stage (e.g. `tr`, `tee`, `head`) |

Together they cover most bash bug classes. Individually each has subtle exceptions; combined, they have *more* exceptions because the rules interact.

## Why each option exists

### `set -e` (errexit)

Default bash behaviour: every command's exit code is yours to check, but if you don't, the script keeps going. For a script that's fundamentally a sequence of "do this, then this", that means a failure leaves the script half-applied with later commands operating on the wrong state. `set -e` flips the default: unchecked non-zero exit aborts the whole script.

### `set -u` (nounset)

Default bash: `echo "$undefined"` prints empty string. That hides typos like `${MAX_RETIRES}` (intended `MAX_RETRIES`). `set -u` makes the typo a hard error.

### `set -o pipefail`

Default bash: a pipeline's exit code is the *last* command's exit code. So `false | true` exits 0. Any failure in an earlier pipeline stage is silently swallowed. `pipefail` changes the rule to "the rightmost non-zero, or 0 if all succeed", so a broken left-side command surfaces.

## How they actually behave (and where they don't)

### `set -e` carve-outs

`set -e` does NOT trip in these situations - this is by design and documented:

1. **Inside a conditional context.** `if cmd; then` doesn't trip on cmd failing - that's the whole point of the `if`. Same for `while`, `until`, `&&`, `||`, and the left side of `!`.
2. **Inside a function called from a conditional.** `if my_func; then` suppresses `set -e` *inside* `my_func` too. This is the most common surprise. Workaround: factor out the failure-meaningful logic from the failure-not-meaningful parts.
3. **Command substitution in a declaration line.** `local x=$(failing_cmd)` does NOT trip `set -e` - because `local` is the actual command, and `local` itself succeeds even when its argument substitution failed. **Workaround:** split the declaration: `local x; x=$(failing_cmd)` - now `set -e` sees the assignment failing.
4. **Last command of a function returning non-zero.** Same applies to a function called from a context where its return value is being inspected.

### `set -o pipefail` carve-out

`pipefail` reports the rightmost non-zero exit, but: an `EPIPE` from a downstream command closing early can cause an upstream command to exit non-zero with `141` (`SIGPIPE`). Example: `seq 1 1000000 | head -1` with pipefail can return 141 if `seq` is still writing when `head` closes the pipe. `head` succeeds, so without pipefail you get 0; *with* pipefail you can get 141. Workaround: trap or check for 141 specifically, or filter through a tool that handles SIGPIPE gracefully.

### `read` interaction

`read` returns:

- 0 if it read at least one character before the line terminator
- non-zero (typically 1) if it hit EOF before reading anything

Under `set -e`, `read` hitting EOF will abort the script. That's usually right - but for a wizard that prompts and reads, with input piped from a here-doc or shell pipeline, EOF can come earlier than expected (or the buffering layer interacts badly with `printf` outputs that don't have trailing newlines).

PhoneCTL's wizard issue is in this family: under interactive use, `read -r host` on stdin works correctly. Under `printf '\n\n\n\n' | phonectl init`, the wizard prints the first prompt and exits with code 1 before printing the next prompt - meaning the script aborted somewhere between the first `read` and the second `printf`. The exact cause is still under investigation (deferred to v0.2). The general lesson: when `set -e` is on AND you have a sequence of `read`s after `printf` prompts AND your stdin is pipe-buffered, exit-code subtleties can stop the script unexpectedly.

## Common misconceptions

- **"`set -e` means the script stops on any error."** Only on *unchecked* errors. Errors in conditional contexts are explicitly OK.
- **"`local x=$(cmd)` is the same as `local x; x=$(cmd)`."** They behave the same when `cmd` succeeds. Under `set -e` they behave differently when `cmd` fails: the first form continues, the second aborts.
- **"`set -e` and `||` together are belt-and-braces."** They are - and that's correct. `set -e` is the default; `|| true` or `|| handle_failure` is the per-call escape hatch.
- **"`pipefail` is on by default in modern bash."** No. All three options are still off by default in every bash version. They have to be enabled explicitly.
- **"`set -u` is annoying because it breaks `${VAR:-default}` patterns."** It does not. `${VAR:-default}` and `${VAR:=default}` and `${VAR:?error}` are all designed to coexist with `set -u`. The bare `$VAR` is what trips it.

## When it matters in practice

- **CLIs that wrap external tools.** Without `set -e`, a failed `adb` or `curl` mid-script leaves you in a half-state. With it, the user gets a clear "the script aborted on line 47" instead of a confusing partial result.
- **Functions that compute and check.** `if my_check; then` accidentally suppresses `set -e` inside `my_check`. Refactor: have `my_check` do only the cheap test; do the actual side-effect work outside the conditional.
- **Capturing tool output for parsing.** `local out=$(tool)` is the common idiom; switch to `local out; out=$(tool)` whenever the tool failure is meaningful.
- **Long pipelines where the last stage is `tr`, `tee`, or `head`.** Without pipefail, only the last stage's exit code is checked, hiding earlier failures. `pipefail` is essentially mandatory once you start wrapping external tools whose failures you care about.

## Configuration in common stacks

| Tool | Equivalent of `set -e` |
|---|---|
| `bash` | `set -e` (errexit) |
| `zsh` | `setopt err_exit` (default off, opt-in) |
| `fish` | Fish does not propagate exit codes the same way; `or return` is the per-call equivalent |
| `python` | Exceptions by default; need `try`/`except` to suppress |
| `node` | Promise rejections + `process.on('unhandledRejection', ...)` for the equivalent net |

For shell scripts specifically: `set -euo pipefail` plus `IFS=$'\n\t'` (set IFS to only newline + tab) is sometimes called "unofficial bash strict mode" (Aaron Maxwell's coinage). PhoneCTL uses the first three; we leave IFS alone because the codebase doesn't depend on word splitting in ways IFS affects.

## Further reading

- **`man bash`** - search for `errexit`, `nounset`, `pipefail`, and the section "SHELL BUILTIN COMMANDS / set". The official semantics live here.
- **Aaron Maxwell, "Use the Unofficial Bash Strict Mode"** - the coining article. http://redsymbol.net/articles/unofficial-bash-strict-mode/
- **Greg's Bash FAQ #105** - "Why doesn't `set -e` (or `trap ERR`) do what I expected?" Explains the carve-outs in detail. https://mywiki.wooledge.org/BashFAQ/105
- **Mendel Cooper, "Advanced Bash-Scripting Guide"** - older but free, comprehensive. The "Exit codes and exit status" chapter is the most relevant. https://tldp.org/LDP/abs/html/
- **`shellcheck`** - static analyser. Catches many of the carve-outs by warning on patterns like `local x=$(cmd)`, unset-variable use, and unchecked pipe stages. https://www.shellcheck.net/
