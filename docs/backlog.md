# PhoneCTL Backlog

This is the single source of truth for all planned, in-progress, and recently completed work.

It is updated by the workflow commands:
- `/create-issue` adds items to Feature or Bug backlog
- `/start-feature` moves an item to Active
- `/fix` marks a bug as fixed
- `/ship` moves an item to Closed

**Scope check rule:**
When a new request comes in, check the Active section first.
- If there is an active plan: anything outside that plan's stated scope goes to backlog, not into the active branch.
- If there is no active plan: new items go directly to the appropriate backlog section.
- Slight deviations from an active plan still go to backlog. Scope creep compounds even when each addition seems small.

---

## Active

What is currently being planned or built:

| Plan file | Issue | Branch | Status |
|-----------|-------|--------|--------|
| - | - | - | - |

---

## Feature Backlog

Future features - not yet started. Add GitHub issue number when created.

| # | Title | Priority | Notes |
|---|-------|----------|-------|
| - | - | - | - |

---

## Bug Backlog

Known bugs not yet fixed. Add GitHub issue number when created.

| # | Title | Priority | Notes |
|---|-------|----------|-------|
| - | - | - | - |

---

## Closed

Recently completed work (keep last 10):

| # | Title | Type | Closed |
|---|-------|------|--------|
| - | - | - | - |

---

## Someday / Maybe

Untracked ideas - not estimated, not prioritized, not committed to. Just things worth remembering.

- **Windows support** via a Node-based dispatcher that shells out to `adb` / `ssh` (no bash dependency)
- **Multi-device profiles** - `phonectl use <profile>` to switch between phones / tablets
- **Service management** - `phonectl service nginx start|stop|status` for services running inside Termux or proot
- **Application deployment** - `phonectl deploy <project>` to build, push, and restart .NET / Node apps on the phone; companion `phonectl logs <service>` for tailing
- **Port tunnelling** - `phonectl tunnel <local-port> <remote-port>` over SSH
- **Plugin system** for user-defined custom commands (drop a script into `~/.config/phonectl/commands/`)
- **JSON output mode** (`--json`) for scripting / piping into other tools
- **mDNS / Bonjour auto-discovery** of the phone's IP on the LAN (drop the `host=` requirement for first run)
- **Wake-lock helpers** - check / acquire / release `termux-wake-lock` over SSH
- **Audio mirroring** in `scrcpy` (newer scrcpy versions support `--audio`)
- **Termux package management passthrough** - `phonectl pkg install <pkg>` runs `pkg install` over SSH
- **VS Code Remote launcher** - `phonectl code <path>` opens a project on the phone via VS Code Remote SSH (`code --remote ssh-remote+phone <path>`); assumes the user has configured the Remote SSH host once and has `code` in their PATH
