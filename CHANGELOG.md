# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
