# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0] - 2026-05-25

Five device-info verbs split out of `phonectl status` so each piece of device
state is addressable on its own (and scriptable). All reuse the SSH-based
data sources already wired in v0.2 - no new fixtures, no new dependencies,
no architecture drift. `phonectl status` is unchanged.

### Added

- `battery` - status-style panel: level / temp / status / plug / health, via
  `termux-battery-status` (Termux:API JSON).
- `info` - status-style panel: model + Android version, via `getprop`.
  Intentionally minimal - no kernel, serial, or build fingerprint.
- `ip` - bare one-line WiFi IP from `termux-wifi-connectioninfo`. Designed for
  capture: `IP=$(phonectl ip)`.
- `storage [<path>]` - status-style panel for any path via `df`. Default is
  `/storage/emulated/0`. The `termux` alias sends a literal `$PREFIX` over
  the wire so the phone-side bash expands it.
- `uptime` - bare one-line uptime string from the `uptime` command. Handles
  short (`1:09`) and long (`1 day, 3:45`) formats.
- New `DEVICE INFO` section in `phonectl help`.
- 15 new bats tests in `test/cmd_info.bats` covering all five verbs (104 → 119).

### Changed

- Uptime parser in both `cmd_status` and the new `cmd_uptime` re-anchored on
  `, load average:` (present in both Linux and Termux output). The v0.2 regex
  required a `, N user(s),` segment that Termux's `uptime` does not emit, so
  the previous parser would have started failing the moment we hit non-Linux
  output. Strip a trailing `, N user(s)` if present (Linux but not Termux).
- `test/cmd_meta.bats` version assertions now read `package.json` dynamically
  instead of hard-coding `0.1.0`, so future version bumps don't need a test
  edit.
- `package.json` version: `0.2.0` → `0.3.0`.

### Notes

- Verified live on Realme GT Master Edition (RMX3360, Android 13) at
  `192.168.1.51:8022`: battery 100% FULL 45.6°C, info RMX3360 / Android 13,
  ip 192.168.1.51, uptime 2:59, storage (default + `termux` alias + `/`).
  `status` regression-clean.
- 119 bats tests (up from 104 in v0.2). All green.
- Format split is intentional: multi-field verbs (`battery`, `info`,
  `storage`) get status-style panels so they look at home next to `status`;
  single-value verbs (`ip`, `uptime`) print the bare value so they pipe
  cleanly into shell variables.

[0.3.0]: https://github.com/hydraInsurgent/phonectl/releases/tag/v0.3.0

## [0.2.0] - 2026-05-25

SSH-default architecture refactor + new `pair` verb. Driven by the realisation
during production use that Android 11+ rotates the wireless-ADB connect port
on every phone reboot AND turns wireless debugging off on every reboot, so
v0.1's ADB-default flow was fragile. SSH on Termux (port 8022, Termux:Boot
+ runit-supervised) survives reboots cleanly and is now the daily driver
for `status`, `pull`, `push`. ADB is reserved for `pair` and `connect`.

### Added

- `pair` verb - wizard for Android 11+ wireless-debugging pair flow. Prompts
  for the pair port + 6-digit code shown on the phone, runs `adb pair`,
  parses the connect port from the success line, writes it to
  `~/.config/phonectl/config` as `adb_port`.
- `connect [<port>]` - optional port positional arg. With it, updates
  `adb_port` then reconnects (the "trust persists, port changed"
  post-reboot recovery case). Without it, runs USB-first / wireless-fallback
  via new `adb_select_device`.
- `lib/core/adb.sh::adb_select_device` - USB-first, wireless-fallback
  selector. `adb_run` and `adb_shell` route through it; verbs no longer
  encode `-s host:port` themselves.
- `lib/core/ssh.sh::ssh_pull` / `ssh_push` - scp wrappers (with `-P` capital
  port flag, BatchMode).
- `lib/core/ssh.sh::ssh_battery_status` - `termux-battery-status` wrapper
  with install-hint fallback when `termux-api` is missing.
- `test/_stubs/scp` - PATH-stub for unit tests.
- 10 real-phone fixtures + 4 synthetic fixtures for new code paths.

### Changed

- `init` rewritten as pure manual prompts (no `adb devices` calls, no
  USB requirement). Side effect: fixes the v0.1 deferred bug where init
  hung after the first prompt under piped stdin.
- `status` rewritten to SSH-only. Battery from `termux-battery-status` JSON,
  network from `termux-wifi-connectioninfo` JSON (replaces blocked-by-app-uid
  `ip addr show wlan0`), uptime from `uptime` command (replaces blocked
  `/proc/uptime`), df from `/storage/emulated/0`, model + Android from
  `getprop`. Bonus fields surfaced: RSSI, link speed, frequency.
- `pull` / `push` use scp instead of adb pull/push. Works post-reboot
  without re-pair.
- Help text reorganised into CONNECTION / FILE TRANSFER / ADB / CONFIG /
  META sections to make the new transport split obvious.
- `package.json` version: `0.1.0` → `0.2.0`.

### Fixed

- Bug in `adb_select_device`'s wireless-already-connected branch: original
  `grep -qE "^<target>[[:space:]]+device$"` missed when `adb devices` 
  appended `product:/model:` columns after `device`. Switched to
  `awk '$1==target && $2=="device"'` which is robust to trailing columns.
- v0.1 piped-stdin hang in `init` (resolved by `init` rewrite, not patched
  in the old code path).

### Removed

- `lib/core/adb.sh::adb_device` and `adb_connect` helpers (superseded by
  `adb_select_device` which handles both USB selection and wireless
  fallback uniformly).

### Notes

- Verified live on Realme GT Master Edition (RMX3360, Android 13) at
  `192.168.1.51:8022`: status, ssh one-shot, push/pull round-trip, connect
  with port arg, version, help. All passing.
- 104 bats tests (up from 86 in v0.1).
- `termux-api` package + Termux:API APK are now hard prerequisites on the
  phone (documented in `guides/phone-server-setup.md`).
- The bare `sshd` line in the boot script was removed (sshd is now
  runit-supervised). Backport to the Tasklog repo's
  `scripts/setup-phone-boot.sh` is pending.

[0.2.0]: https://github.com/hydraInsurgent/phonectl/releases/tag/v0.2.0

## [0.1.0] - 2026-05-06

First milestone of PhoneCTL. Foundation, scaffold, and the first 9 verbs working
end-to-end against the test device. Not yet on npm - that lands at v1.0.0.

### Added

- 9 verbs working end-to-end: `init`, `ssh`, `connect`, `status`, `pull`, `push`,
  `config`, `help`, `version`.
- Bash dispatcher (`bin/phonectl`) with strict mode and `readlink -f` so an
  `npm link` install resolves the in-repo `lib/` correctly.
- Core helpers in `lib/core/`:
  - `output.sh` - colored `info` / `success` / `warn` / `error` / `header` / `kv`,
    with `NO_COLOR` and non-TTY support.
  - `deps.sh` - `require_deps` with distro-aware install hints
    (`apt` / `dnf` / `pacman` / `brew`); `/etc/os-release` reader is testable
    via `PCTL_OS_RELEASE_PATH` override.
  - `config.sh` - `~/.config/phonectl/config` parsed line-by-line (never
    sourced), env-var overrides via `PHONECTL_*`, atomic `chmod 600` writes,
    tilde expansion in set values.
  - `adb.sh` / `ssh.sh` - wrappers that pre-fill `-s host:port` / `-p port host`,
    plus `ssh_check` with `BatchMode`, `ConnectTimeout=3`, and `accept-new`
    for reachability probes.
  - `help.sh` - the grouped command-list help text.
- Command groups in `lib/commands/`: `init`, `connection` (ssh / connect / status),
  `transfer` (pull / push), `config`.
- bats-core test harness:
  - `test/_stubs/adb` and `test/_stubs/ssh` driven by `STUB_<TOOL>_OUTPUT` /
    `_OUTPUT_FILE` / `_STDERR` / `_EXIT` / `_LOG` env vars.
  - `test/test_helper.bash` prepends stubs to `$PATH` and isolates
    `XDG_CONFIG_HOME` / `HOME` per test.
  - `test/fixtures/` - 15 real-output captures from the test phone for
    fixture-driven parser development.
  - 86 tests covering parsing, argv construction, config roundtrips,
    distro-hint dispatch, wizard prompt sequences, and the `cmd_status`
    panel rendered against real fixtures.
- `SMOKE.md` manual checklist for live-phone validation.
- `README.md` - install, configure, verb list, why, roadmap.
- `docs/architecture.md`, `docs/product-design.md`,
  `docs/engineering-guidelines.md`, `docs/backlog.md` - project foundation docs.
- `guides/phone-server-setup.md` - 7-step walkthrough of the one-time phone
  setup PhoneCTL assumes (USB debugging, wireless ADB, DHCP reservation,
  Termux + sshd + key auth, Termux:Boot auto-start, optional proot Ubuntu).

### Notes

- `package.json` is `private: true` to block accidental `npm publish` until v1.0.0.
- Local install via `npm link` from source is the only supported install path
  in v0.1.
- Verified live on Realme GT Master Edition (RMX3360, Android 13) at
  `192.168.1.51:8022`.

### Known issues (deferred to v0.2)

- `phonectl init` hangs after the first prompt under pure piped stdin (works
  correctly interactively; bats covers the logic via heredocs).
- `init` wizard does not prompt for `adb_port` (defaulted to `5555`; can be
  changed via `phonectl config adb_port <port>`).

[0.1.0]: https://github.com/hydraInsurgent/phonectl/releases/tag/v0.1.0
