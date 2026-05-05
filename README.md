# phonectl

A bash CLI to manage an Android phone repurposed as a headless home server, via `adb`, `ssh`, and `scrcpy`. Distributed (eventually) via npm.

> **Status: v0.1 in development.** 9 verbs working end-to-end against the test device. Not yet published to npm — that lands at v1.0.0 once the full 22-verb set is in.

```
phonectl ssh                    Drop into a Termux shell on the phone
phonectl connect                Wireless ADB connect (with host_alt fallback)
phonectl status                 Model, battery, storage, IP, SSH reachability - one panel
phonectl pull <remote> <local>  Copy a file from the phone to this machine
phonectl push <local> <remote>  Copy a file from this machine to the phone
phonectl init                   First-run wizard to write ~/.config/phonectl/config
phonectl config <key> <value>   Set a single config value
phonectl help                   Command list
phonectl version                Print version
```

## Install (from source, while v0.1 is unpublished)

Requires `adb`, `ssh`, and Node.js (for `npm link`). Linux and macOS only for now.

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

- **v0.1 (current):** foundation, scaffold, the demo-able 9 verbs, `bats-core` test infra, local install via `npm link`. **No npm publish yet.**
- **v0.2 → v0.X:** remaining 13 verbs land across multiple plans — `battery`, `ip`, `storage`, `uptime`, `info`, `stats`, `backup`, `reboot`, `wake`, `scrcpy`, `install`, `exec`, `proot`, `about`.
- **v1.0.0:** full set, README polish, `npm publish` as `phonectl`.

## License

MIT
