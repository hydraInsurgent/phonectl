# PhoneCTL Product Design

This document describes what PhoneCTL is today and the principles behind it.
It is a reference point, not a constraint. If a proposed feature or direction
differs from what is written here, that is a signal to have a conversation
and update this document - not to automatically reject the idea.

---

## What PhoneCTL Is

A command-line tool for people who run an Android phone as a headless home server.
Talking to the phone over `adb` and `ssh` works, but every action means recalling
long flags, the device IP, and which port goes where. PhoneCTL collapses that into
one consistent verb-style CLI (`phonectl ssh`, `phonectl battery`, `phonectl pull`),
so the phone behaves like any other server in your toolkit. It is opinionated for
the Termux + sshd home-server workflow specifically: connection, device health,
file moves, and entering the proot Linux environment where real work happens.

---

## The User

A self-taught developer and homelabber who repurposed an old phone (dead screen,
degraded battery, otherwise fine) into a permanent home server running Termux
with sshd on boot. They live mostly in Pop!_OS / Linux, use the phone to host
side projects and learn .NET / Node services from a proot Ubuntu inside Termux.
Their main frustration is the death-by-a-thousand-papercuts of adb and ssh:
remembering `-s 192.168.1.51:5555` for every adb call, retyping the SSH port,
re-running `adb connect` after every network blip. They want one memorable
command surface that hides that complexity and grows alongside the homelab.

---

## Product Principles

- **One verb at a time.** Every action is `phonectl <verb> [args]`. No flag soup,
  no chained subcommands, no implicit modes. *(suggested - keeps the CLI
  discoverable and easy to grep in shell history)*
- **Sensible defaults, explicit overrides.** A first-time user runs
  `phonectl config` once and never thinks about IP / port again; advanced users
  can override per-call via env vars (`PHONECTL_HOST`, `PHONECTL_SSH_PORT`).
  *(suggested)*
- **Wrap, do not reinvent.** Every command is a thin layer over `adb`, `ssh`,
  or `scrcpy`. If a feature needs a new protocol or a daemon on the phone, it
  does not belong in v1.
- **Fail loudly, never silently.** If the phone is unreachable, a dependency
  is missing, or args are wrong, the user sees a clear error with a fix hint -
  not a half-completed action or a cryptic adb stack trace. *(suggested)*
- **Termux-aware, not Termux-locked.** The tool assumes Termux + sshd on the
  phone (that is the home-server workflow), but the pure ADB commands still
  work against any unrooted Android.

---

## Current Scope

This is what PhoneCTL does today. Items here are not permanent limits - they
reflect where the product is right now and what assumptions the code makes.

- CLI only, distributed via npm (`npm install -g phonectl`), runs on Linux and macOS
- Single device - one phone configured at a time, stored in `~/.config/phonectl/config`
- Bash implementation - relies on `adb`, `ssh`, `scrcpy` installed on the host
- Connection: `ssh`, `connect`, `shell`, `status`
- Device info: `battery`, `ip`, `storage`, `uptime`, `info`, `stats` (one-shot CPU/RAM/temp via adb)
- File transfer: `pull`, `push`, `backup`
- Device control: `reboot`, `wake` (screen on), `scrcpy`, `install <apk>`
- Termux helpers: `exec <cmd>` (one-shot SSH command), `proot` (SSH then auto-enter proot Ubuntu)
- Config + meta: `init` (first-run wizard), `config`, `about`, `help`, `version`

**v1 explicitly does NOT include:**
- Windows support (no bash; Node-wrapper rewrite is Someday)
- Multiple device profiles or LAN auto-discovery (mDNS / Bonjour)
- User-defined custom commands / plugins
- Service management (`nginx`, `pihole`, `dotnet`) - Someday
- Application deployment (`deploy`, `logs`, `tunnel`) - Someday

---

## How Features Currently Work

### Connection
`phonectl ssh` opens an interactive SSH session to Termux on the configured host
and port. `phonectl connect` runs `adb connect <host>:5555` (with the alt IP as
fallback) and prints the device list. `phonectl shell` opens an interactive
`adb shell`. `phonectl status` prints one coloured panel: model, battery level
and temperature, storage, uptime, IP, and SSH reachability.

### Device info
`phonectl battery | ip | storage | uptime | info` each print one section of the
status panel. Useful in scripts and quick checks. Battery parses `dumpsys battery`,
storage parses `df /sdcard`, info reads `getprop`.

### System stats
`phonectl stats` is a one-shot performance snapshot via `adb shell`: CPU model
and core count (parsed from `/proc/cpuinfo`, `nproc`), RAM total + available
(parsed from `/proc/meminfo`), SoC temperature
(`/sys/class/thermal/thermal_zone0/temp`, divided by 1000), and uptime + load
(`/proc/uptime`, `/proc/loadavg`). Same kernel data Termux would see — adb is
faster and avoids the SSH handshake. v1 deliberately does not do live
monitoring; for interactive views, `phonectl exec htop` works after
`pkg install htop` inside Termux.

### File transfer
`phonectl pull <on-phone> <on-pc>` and `phonectl push <on-pc> <on-phone>` wrap
`adb pull` / `push` with the device flag pre-filled. `phonectl backup` pulls
`/sdcard/` to `~/phone-backup/` (path overridable in config).

### Device control
`phonectl reboot` reboots via adb. `phonectl wake` wakes the screen by sending
`adb shell input keyevent 224` - useful when the dead-screen / headless phone
needs its display briefly on. `phonectl scrcpy` launches `scrcpy --tcpip=<host>`.
`phonectl install <apk>` runs `adb install` against the configured device.

### Termux helpers
`phonectl exec "<cmd>"` runs a one-shot command in Termux over SSH and prints
the output - no manual quoting around IP and port. `phonectl proot` opens an
SSH session and immediately runs `proot-distro login ubuntu` so the user lands
inside their proot Linux environment in one step.

### Config + meta
`phonectl init` is the first-run wizard: it lists currently-connected adb
devices, prompts for SSH port (default 8022) and proot distro name, then
writes `~/.config/phonectl/config`. Removes the "edit a config file by hand
before first use" friction.
`phonectl config` with no args prints current config; `phonectl config <key> <value>`
writes to `~/.config/phonectl/config` (e.g. `phonectl config host 192.168.1.51`).
`phonectl about` prints the project name, version, author, and repo URL.
`phonectl help` shows the full command list grouped by section. `phonectl version`
prints the version from `package.json`.
