---
title: 'Why `adb shell` Output Has `\r\n` Line Endings'
category: android
tags: [adb, terminal, pty, line-endings, shell, scripting]
related:
  - termux-and-proot-on-android.md
first_encountered: PhoneCTL v0.1
created: 2026-05-07
updated: 2026-05-07
---

# Why `adb shell` Output Has `\r\n` Line Endings

A surprisingly common gotcha when scripting against Android: `adb shell <cmd>` returns output with `\r\n` line terminators, not `\n`. Awk and grep see "extra" carriage returns at the end of every line. The fix is one character (`tr -d '\r'`), but knowing *why* tells you when you can avoid it entirely.

## Mental model

When you run `adb shell uname -a`, the host's `adbd` does not just exec the command and stream its bytes back. By default it allocates a **pseudo-terminal (PTY)** on the device, attaches the command's stdout to that PTY, and the PTY in turn applies normal terminal-line-discipline rules: among them, `\n` (line feed) on the way out becomes `\r\n` (CRLF). The host receives the cooked PTY output, not the raw command output.

The fix has three forms, in order of cleanliness:

1. Use `adb exec-out <cmd>` - same idea but no PTY; output is raw bytes.
2. Use `adb shell -T <cmd>` - explicitly suppress PTY allocation.
3. Pipe the output through `tr -d '\r'` and accept the small overhead.

## Why it exists

Terminals are an old abstraction. They expect line-oriented output where each "newline" actually moves the cursor to the start of the next line - on real hardware terminals, that needed two control codes: carriage return (`\r` = move cursor to column 0) and line feed (`\n` = move down one line). Unix kernels and TTY drivers preserve that history through the **terminal line discipline**, which by default applies `OPOST | ONLCR` (post-process output, map `\n` to `\r\n`).

Android's `adbd` allocates a PTY for `adb shell` so interactive sessions feel right (line editing, signals, job control all work). The same PTY happens to mangle output for non-interactive uses too. `exec-out` was added later (around `adb` 1.0.32) precisely to provide a non-PTY channel.

## How it actually works

```
host (adb client)                                phone (adbd + cmd)
─────────────────                                ──────────────────────────────
adb shell uname -a    ─── connect ────────►      adbd forks bash with a PTY
                                                  bash exec uname -a
                                                  uname writes "Linux\n"
                      ◄── "Linux\r\n" ──────     PTY line discipline (ONLCR)
                                                  rewrote \n to \r\n on output
adb client prints
"Linux\r\n" verbatim
```

`adb exec-out`:

```
adb exec-out uname -a ─── connect ────────►      adbd forks bash, NO PTY
                                                  bash exec uname -a
                                                  uname writes "Linux\n"
                      ◄── "Linux\n" ───────     raw stream, no rewriting
```

The output bytes leave the device differently because the kernel-side TTY driver isn't in the path.

## Common misconceptions

- **"`\r\n` means Windows."** No. CRLF is the on-the-wire standard for many protocols (HTTP, SMTP, IRC, SMTP) and the default cooked-mode TTY output on every Unix system. Windows files happen to also use CRLF, but that's coincidence; the line-discipline mechanism is older than Windows.
- **"`adb shell -T` always avoids it."** `-T` (no PTY) was added in newer adb. On older adb (`< 1.0.40` or so) it isn't available; `exec-out` works further back.
- **"Stripping `\r` is enough for any binary content."** It is for text. If you `adb shell cat /sdcard/photo.jpg > local.jpg`, PTY line discipline can corrupt the binary stream beyond just `\r\n`. Use `adb exec-out` (or better, `adb pull`) for binary data.
- **"It only happens on the last line."** No. Every `\n` written by the remote command becomes `\r\n` in the stream. Multi-line output has a `\r` before every newline, including in the middle.

## When it matters in practice

Any time you're parsing `adb shell` output with tools that don't auto-trim trailing whitespace:

- **`awk` matching specific lines.** A pattern like `/^level:/` may match the line, but `$2` extracts a value with a trailing `\r` baked in. Bash variable comparison `[ "$x" = "53" ]` then fails because `$x` is actually `53\r`.
- **`grep | head -1`-style pipelines feeding into a shell variable.** The variable gets the trailing `\r`. You don't see it in `echo "$x"` (terminal eats CR) but `printf '|%s|' "$x"` shows `|53\r|`.
- **`bash` arithmetic on parsed numbers.** `n=$(adb shell ...)` then `$((n + 1))` gives `bash: 53\r: syntax error`.
- **JSON output written by an Android tool.** Some Android tools (`dumpsys`, `cmd`) can emit JSON. Without `tr -d '\r'`, your `jq` parse fails on what looks like correct JSON.

PhoneCTL handles this in two places:

- `cmd_status` in `lib/commands/connection.sh` pipes every `adb_shell` capture through `tr -d '\r'` before parsing.
- The fixtures captured at `test/fixtures/` were generated via the same `adb -s ... shell ...` invocations production uses, so parsers are exercised against the real CRLF byte stream.

## Configuration in common stacks

| Stack | How CRLF appears |
|---|---|
| `bash` | Pipe through `tr -d '\r'` immediately after capture; or use `adb exec-out` |
| `python` | `subprocess.run(['adb', 'exec-out', ...]).stdout.decode()` returns clean lines; `adb shell` does not |
| `node` | `child_process.execFileSync('adb', ['exec-out', ...])` returns clean Buffer; `'shell'` returns CRLF |
| `go` | Same: `exec.Command("adb", "exec-out", ...)` for clean output |
| `Linux serial / minicom` | The same PTY/ONLCR layer applies to any TTY-attached process; `stty -onlcr` disables it |

## Further reading

- **POSIX `termios(3)`** - the line-discipline knobs. The relevant flag is `ONLCR` in `c_oflag`. https://pubs.opengroup.org/onlinepubs/9699919799/functions/termios.html
- **Linux `pty(7)`** - how pseudo-terminals work, who creates them, who controls them.
- **Android adb `--help`** - the `shell -T` and `exec-out` flags. The man page for `adb` itself is sparse; the source at https://android.googlesource.com/platform/packages/modules/adb/ is the canonical reference.
- **`man tr`** - the `\r`-stripping fix. The actual portable form is `tr -d '\r'`; older `tr` may not accept `\r`-style escapes, in which case `tr -d $'\r'` (bash) or `sed 's/\r$//'` works.
