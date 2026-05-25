# phonectl

A bash CLI to manage an Android phone repurposed as a headless home server, via `adb`, `ssh`, and `scrcpy`. Distributed (eventually) via npm.

> **Status: v0.2 in development.** 10 verbs working end-to-end against the test device. Not yet published to npm — that lands at v1.0.0 once the full v1 verb set is in.

```
phonectl ssh [cmd...]           SSH into Termux (interactive or one-shot)
phonectl status                 SSH-based snapshot: model, battery (Termux:API),
                                storage, uptime, WiFi info, SSH reachability
phonectl pull <remote> <local>  Copy a file from the phone to this machine (via scp)
phonectl push <local> <remote>  Copy a file from this machine to the phone (via scp)

phonectl pair                   Android 11+ wireless-debugging pair wizard
phonectl connect [<port>]       Connect ADB (USB-first / wireless-fallback).
                                With <port>, updates adb_port first
                                (post-reboot recovery when trust persists).

phonectl init                   First-run wizard - pure manual prompts
phonectl config <key> <value>   Set a single config value
phonectl help                   Command list
phonectl version                Print version
```

**Architecture in v0.2 (set after WiFi-debugging in production):** SSH is the daily driver (survives Android 11+ reboots since Termux + sshd + Termux:Boot keep it up). ADB is reserved for `pair` and `connect` since their whole purpose is ADB. No `--adb` / `--ssh` flag layer — verbs default to whichever transport makes sense.

## Install (from source, until v1.0.0 npm publish)

Requires `adb`, `ssh`, `scp`, `jq`, and Node.js (for `npm link`). On the phone side: Termux + sshd + Termux:API package + Termux:API APK. Linux and macOS only for now.

```bash
git clone https://github.com/hydraInsurgent/phonectl.git
cd phonectl
npm install
npm link
```

`npm link` symlinks `phonectl` onto your `$PATH`. Undo with `npm unlink -g phonectl` from anywhere.

## Configure

The interactive wizard works when a phone is connected (USB or wireless ADB):

```bash
phonectl init
```

It detects the device, parses the WiFi IP from `ip addr show wlan0`, and asks for the SSH port (default `8022`), proot distro (default `ubuntu`), and backup directory. The config lands at `~/.config/phonectl/config` with `chmod 600`.

If you'd rather skip the wizard:

```bash
phonectl config host 192.168.1.51
phonectl config ssh_port 8022
phonectl config adb_port 5555
```

Per-call overrides via env vars are also supported (`PHONECTL_HOST`, `PHONECTL_SSH_PORT`, etc.).

## Run the tests

```bash
npm test
```

`bats-core` runs the suite (86 tests in v0.1). Tests use PATH-stubbed `adb` / `ssh` and real-phone outputs captured in `test/fixtures/`, so parsers are exercised against the exact data they will see in production.

## Why this exists

Built for an old Realme GT Master with a dead screen, repurposed as a permanent home server (Termux + sshd on boot, with a `proot-distro` Ubuntu inside for `.NET` and Node experiments). Each `adb` and `ssh` interaction needed flag-juggling - `phonectl` collapses it into one verb-style CLI.

Built collaboratively with Claude. Design decisions and direction are mine; AI helped me iterate faster.

## Background

There is an unrelated Rust CLI at [github.com/Sanjai-Shaarugesh/phonectl](https://github.com/Sanjai-Shaarugesh/phonectl) — different domain (call control, contacts, audio routing via ADB). The npm name `phonectl` is currently free.

## Roadmap

- **v0.1 (shipped):** foundation, scaffold, 9 verbs, `bats-core` test infra, local install via `npm link`.
- **v0.2 (current):** SSH-default refactor + `pair` verb. `status` / `pull` / `push` now go over SSH (survive Android 11+ reboots, no re-pair needed). `pair` walks the Android 11+ pair flow. `connect` takes an optional `<port>` arg for the "trust persists, port changed" recovery case. `init` rewritten as pure manual prompts (fixes v0.1 piped-stdin hang).
- **v0.3 → v0.X:** remaining 14 verbs across multiple plans — `battery`, `ip`, `storage`, `uptime`, `info`, `stats`, `backup`, `reboot`, `wake`, `scrcpy`, `install`, `exec`, `proot`, `about`.
- **v1.0.0:** full set, README polish, `npm publish` as `phonectl`.

## License

MIT
