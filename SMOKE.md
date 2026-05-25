# PhoneCTL Smoke Checklist

Manual end-to-end checklist run against a real phone before considering a
release "done". Run with the device awake and reachable on the configured
host / port.

**Test device for v0.2:** Realme GT Master (RMX3360, Android 13) at
`192.168.1.51`, SSH `8022`, Termux + sshd (now runit-supervised) + Termux:API.

Tick each box only after the listed expectation matches what you actually
see. If a step fails, stop and fix in code rather than ticking through.

---

## Pre-conditions

- [ ] `phonectl` on `$PATH` (`npm link` from repo root if not)
- [ ] `~/.config/phonectl/config` exists with valid `host`, `ssh_port`, `adb_port`
- [ ] Phone awake, on WiFi, reachable via `ping <host>`
- [ ] `termux-api` package installed on phone + Termux:API APK sideloaded
  (`phonectl ssh 'command -v termux-battery-status'` returns a path)

---

## Verbs

### `phonectl help`
- [ ] Prints the grouped verb list with CONNECTION / FILE TRANSFER / ADB / CONFIG sections
- [ ] `pair` and `connect [<port>]` appear under ADB
- [ ] Exit code `0`

### `phonectl version`
- [ ] Prints `phonectl 0.2.0`
- [ ] Exit code `0`

### `phonectl init` (NEW v0.2 - pure manual prompts, no USB / ADB needed)
- [ ] Prompts for: Phone IP (required), SSH port (default 8022), ADB wireless port (default 5555), proot distro (default ubuntu), Backup dir
- [ ] **Piped stdin completes** (regression test for v0.1 hang): `printf '192.168.1.51\n\n\n\n\n' | phonectl init` writes config and exits cleanly
- [ ] Writes `~/.config/phonectl/config` with `chmod 600`
- [ ] No `adb` calls anywhere in the flow (verify via `strace` if curious)

### `phonectl config`
- [ ] No args: prints current config (one `key=value` per line)
- [ ] `phonectl config host`: prints just the value
- [ ] `phonectl config host 192.168.1.51`: writes and re-reads correctly

### `phonectl pair` (NEW v0.2 - Android 11+ wireless debugging wizard)
- [ ] Prints "On the phone: Settings -> Developer options -> Wireless debugging -> Pair device with pairing code"
- [ ] Validates pair port is numeric (reject "abc")
- [ ] Validates code is exactly 6 digits (reject "123" or "abcdef")
- [ ] On success: parses the connect port from `Successfully paired to <host>:<port>` and writes it to `adb_port` in config
- [ ] Verifies wireless ADB is reachable post-pair (calls `adb_select_device`)
- [ ] On wrong code: clear hint mentioning ~30s expiry + re-tap "Pair device"

### `phonectl connect`
- [ ] No args: tries USB-first then wireless at saved adb_port; reports which path won
- [ ] `phonectl connect 41267`: updates `adb_port` to 41267, then reconnects (post-reboot recovery case where trust is still good but port changed)
- [ ] `phonectl connect notaport`: rejects with `adb_port must be a number` hint
- [ ] Failure surfaces all three recovery hints (USB, port change, pair)

### `phonectl status` (NEW v0.2 - SSH-only path)
- [ ] Prints Device + Battery + Storage + Uptime + Network sections
- [ ] Battery values from `termux-battery-status` JSON (level / temp °C / status / plug / health)
- [ ] Network from `termux-wifi-connectioninfo`: IP, RSSI, link speed, frequency. SSID + MAC are randomized by Android privacy - that's expected.
- [ ] Uptime parsed from `uptime` command (not `/proc/uptime` - that's blocked)
- [ ] SSH unreachable failure: clear error, cross-links to `docs/issues/wifi-lan-inbound-drops.md`

### `phonectl ssh`
- [ ] No args: drops into interactive Termux shell over SSH on `:8022`
- [ ] One-shot: `phonectl ssh 'echo OK; whoami'` returns `OK` + `u0_a322`
- [ ] `exit` returns control to host shell

### `phonectl pull <remote> <local>` (NEW v0.2 - scp instead of adb pull)
- [ ] Pulls a known file from `/sdcard/` to the local path (silent success, scp's default)
- [ ] Missing remote file: scp error visible, exit non-zero
- [ ] Missing args: prints usage hint, exit non-zero

### `phonectl push <local> <remote>` (NEW v0.2 - scp instead of adb push)
- [ ] Pushes a local file to `/sdcard/`
- [ ] Round-trip (push then pull) yields byte-identical content
- [ ] Missing args: prints usage hint, exit non-zero

---

## Post-test cleanup

- [ ] Remove `/sdcard/Download/phonectl-test.txt` (or whatever you pushed)
- [ ] All bats tests pass: `npm test`
- [ ] If pair was tested with a fresh phone: connect port persists across `phonectl connect` (no immediate re-pair needed)
