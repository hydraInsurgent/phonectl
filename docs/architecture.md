# PhoneCTL Architecture

This document describes the current system structure.
It is the primary reference for any AI assistant or contributor working in this repo.

---

## System Overview

PhoneCTL is a single-binary bash CLI distributed as an npm package. The
entrypoint (`bin/phonectl`) is a thin dispatcher: it parses the subcommand,
loads shared helpers from `lib/core/`, and delegates to one of the command
files in `lib/commands/`. Each command file is a small bash module that wraps
`adb`, `ssh`, or `scrcpy` against the device described by the user's config
file. There is no daemon, no server process, and no persistent state beyond
`~/.config/phonectl/config`.

```
User shell
    │
    ▼
bin/phonectl                  (dispatch by $1)
    │
    ├──► lib/core/config.sh   (load host, port, paths)
    ├──► lib/core/deps.sh     (verify adb / ssh / scrcpy)
    ├──► lib/core/output.sh   (colours, formatting)
    │
    ▼
lib/commands/<group>.sh       (e.g. info.sh, transfer.sh)
    │
    ▼
adb / ssh / scrcpy            (host binaries)
    │
    ▼
Phone (Termux + sshd)
```

---

## Repository Layout

```
phonectl/
├── bin/
│   └── phonectl              Main CLI entrypoint (bash dispatcher)
├── lib/
│   ├── commands/             One file per command group
│   │   ├── init.sh           init (first-run wizard, pure manual prompts)
│   │   ├── pair.sh           pair (Android 11+ wireless-debugging wizard)
│   │   ├── connection.sh     ssh, connect, shell, status
│   │   ├── info.sh           battery, info, ip, storage, uptime (stats: planned)
│   │   ├── transfer.sh       pull, push, backup
│   │   ├── control.sh        reboot, wake, scrcpy, install
│   │   ├── termux.sh         exec, proot
│   │   └── config.sh         config get / set
│   └── core/
│       ├── config.sh         load + write config, env-var overrides
│       ├── adb.sh            adb wrapper (-s <device> pre-filled)
│       ├── ssh.sh            ssh wrapper (-p <port> pre-filled)
│       ├── deps.sh           dependency check + clear error hints
│       ├── output.sh         colour codes, status formatters
│       └── help.sh           help text builder
├── test/                     bats-core test files
├── package.json              npm metadata, bin entry, postinstall chmod
├── README.md                 Human-facing project overview + install
├── LICENSE                   MIT
├── docs/
│   ├── architecture.md       This file
│   ├── engineering-guidelines.md
│   ├── product-design.md
│   ├── backlog.md
│   ├── plans/                Implementation plans
│   └── tests/                Test coverage tracking
├── CLAUDE.md                 Instructions for AI assistants
└── LESSONS.md                Session learnings log
```

---

## CLI Layer

**Runtime:** Bash 4+ (Linux / macOS)
**Entrypoint:** `bin/phonectl`

### Structure

```
bin/phonectl                 dispatcher: parses $1, sources core helpers,
                             calls into lib/commands/<group>.sh

lib/commands/*.sh            one file per command group; each defines
                             functions named cmd_<verb> (e.g. cmd_battery)

lib/core/*.sh                pure helpers, no side effects beyond their job;
                             sourced by both the dispatcher and command files
```

### Data Model

PhoneCTL has no database. The only persisted state is the config file:

```
~/.config/phonectl/config    (key=value, one per line)

host=192.168.1.51            Phone IP (required)
host_alt=192.168.1.50        Optional fallback IP for `connect`
ssh_port=8022                Termux sshd port (default 8022)
adb_port=5555                Wireless adb port (default 5555)
backup_dir=~/phone-backup    Destination for `phonectl backup`
proot_distro=ubuntu          Distro name passed to `proot-distro login`
```

Any value can be overridden per-call via `PHONECTL_<KEY>` env vars
(e.g. `PHONECTL_HOST=192.168.1.99 phonectl ssh`).

---

## How a Command Flows End to End

Example: `phonectl battery`

```
1. User runs `phonectl battery`
2. bin/phonectl sources lib/core/{config,deps,output,ssh}.sh + lib/commands/info.sh
3. deps.sh confirms `ssh` and `jq` are installed; aborts with hint if not
4. config.sh loads ~/.config/phonectl/config + applies env overrides
5. bin/phonectl dispatches to lib/commands/info.sh::cmd_battery
6. cmd_battery calls ssh_battery_status (SSH + termux-battery-status JSON)
7. jq parses level / temperature / status / plugged / health
8. output.sh formats the result as a `── Battery ──` panel with kv rows
9. Exit code: 0 on success, non-zero with message on any failure
```

Two transport layers are in use across the verb set:
- **SSH** is the default for daily verbs (`status`, `battery`, `info`, `ip`,
  `storage`, `uptime`, `ssh`, `pull`, `push`). Survives Android 11+ reboots.
- **ADB** is reserved for verbs whose purpose is ADB (`pair`, `connect`).
  No `--ssh` / `--adb` flag layer.

---

## Known Architectural Limitations

These are tracked as GitHub issues:

| Issue | Description |
|-------|-------------|
| - | None identified yet |

---

## What Does Not Exist Yet

These are planned but not built:

- Node-based dispatcher for Windows support (Someday)
- Multi-device profiles (`phonectl use <profile>`) (Someday)
- Service management (`service nginx start/stop/status`) (Someday)
- Application deployment (`deploy`, `logs`, `tunnel`) (Someday)
- Plugin system for user-defined commands (Someday)
