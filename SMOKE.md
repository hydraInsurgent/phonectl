# PhoneCTL Smoke Checklist

Manual end-to-end checklist run against a real phone before considering a
release candidate "done". Run with the device awake and reachable on the
configured host / port.

**Test device for v0.1:** Realme GT Master (RMX3360, Android 13) at
`192.168.1.51`, SSH `8022`, ADB `5555`, Termux + sshd active.

Tick each box only after the listed expectation matches what you actually
see. If a step fails, stop and fix in code rather than ticking through.

---

## Pre-conditions

- [ ] `phonectl` is on `$PATH` (run `npm link` from the repo root if not)
- [ ] `~/.config/phonectl/config` exists with valid `host`, `ssh_port`, `adb_port`
- [ ] Phone is awake, on WiFi, and connectable via `ping <host>`

---

## Verbs

### `phonectl help`
- [ ] Prints the grouped command list
- [ ] Exit code `0`

### `phonectl version`
- [ ] Prints the version from `package.json` (e.g. `0.1.0`)
- [ ] Exit code `0`

### `phonectl init`
- [ ] Detects the connected adb device (or prints a clear hint when none)
- [ ] Proposes IP from `ip addr show wlan0` parsing
- [ ] Prompts for SSH port (default `8022`), proot distro (`ubuntu`), backup dir
- [ ] Writes `~/.config/phonectl/config` with `chmod 600`
- [ ] Re-running `phonectl init` does not corrupt existing values

### `phonectl config`
- [ ] No args: prints current config (one `key=value` per line)
- [ ] `phonectl config host`: prints just the value
- [ ] `phonectl config host 192.168.1.51`: writes and re-reads correctly

### `phonectl connect`
- [ ] Successfully runs `adb connect <host>:5555`
- [ ] Prints the `adb devices` list with the phone shown as `device`
- [ ] Falls back to `host_alt` when primary is unreachable (if `host_alt` set)

### `phonectl status`
- [ ] Prints model, battery (level + temp), storage (used/free), uptime, IP, SSH reachability
- [ ] Each section labeled, output coloured
- [ ] On unreachable phone: surfaces the raw adb error and exits non-zero

### `phonectl ssh`
- [ ] Drops into an interactive Termux shell over SSH on port `8022`
- [ ] `exit` returns control to the host shell with exit code `0`

### `phonectl pull <remote> <local>`
- [ ] Pulls a known file from `/sdcard/` to the local path
- [ ] Missing remote file: surfaces `adb: error: failed to stat ...`, exit non-zero
- [ ] Missing args: prints usage hint, exit non-zero

### `phonectl push <local> <remote>`
- [ ] Pushes a local file to `/sdcard/`
- [ ] Round-trip (push then pull) yields identical content
- [ ] Missing args: prints usage hint, exit non-zero

---

## Post-test cleanup

- [ ] Remove `/sdcard/phonectl-test.txt` from the phone
- [ ] All bats tests still pass: `npm test`
