# Phone as a Headless Home Server

`Last updated: 2026-05-06` - one-time setup of an Android phone (Realme GT Master, RMX3360, Android 13 in the v0.1 reference build) as a permanent SSH-and-ADB-reachable home server, ready for `phonectl`.

## How this all fits together

The end state is a phone that:

- Boots without anyone touching it, even after a power-cut.
- Comes up on a known, fixed LAN IP.
- Auto-starts an SSH server on TCP port 8022 (Termux's default).
- Doesn't aggressively kill background processes.

`phonectl` then talks to it like any other server in the homelab.

```
your laptop                  your phone (Termux + sshd + Termux:Boot)
+----------+                  +----------------------------------+
|          | --- adb ------>  | adbd            (TCP 5555, WiFi) |
|          |                  |                                  |
| phonectl | --- ssh ------>  | Termux sshd     (TCP 8022)       |
|          |                  |    |                             |
|          |                  |    `-> proot-distro Ubuntu       |
|          | --- scrcpy --->  | (optional, screen mirror)        |
+----------+                  +----------------------------------+
                              wlan0: 192.168.1.51 (DHCP-reserved)
```

Five layers add up to the experience above:

1. **USB debugging** - one-time enable in developer options. Lets `adb` talk to the phone.
2. **Wireless ADB** - kicks `adbd` onto TCP 5555 so the USB cable can come out.
3. **Static IP via router DHCP reservation** - phone gets the same IP forever.
4. **Termux + sshd** - Linux userland on Android, with an SSH server.
5. **Termux:Boot + wake-lock + auto-start script** - all of the above starts on boot, no human required.

## Prerequisites

| Thing | Why |
|---|---|
| A USB-A or USB-C cable that does **data**, not just power | One-time wireless-ADB initialization needs USB. Many phone-charging cables are power-only - test with `adb devices` first. |
| F-Droid (not Play Store) | The Play Store version of Termux has been frozen since 2020 and lacks current packages. F-Droid: https://f-droid.org/ |
| Router admin access | DHCP reservation lives there. Phone-side static IP toggles vary by ROM and can break on updates. |
| An SSH client on the laptop | OpenSSH on Linux/macOS by default; Windows ships it now too. |
| About 30 minutes | Mostly waiting on the phone, not typing. |

## Walkthrough

### Step 1 - Enable USB debugging on the phone

**Why:** `adb` needs an authorized channel to the phone. The first auth handshake happens over USB and pins the laptop's RSA key; later wireless connections inherit the trust.

```
Settings -> About phone -> tap "Build number" 7 times
Settings -> System -> Developer options -> USB debugging (toggle on)
```

Plug the phone in with a data USB cable. The phone shows an "Allow USB debugging?" dialog with the laptop's RSA fingerprint - tick "Always allow from this computer" and accept.

**Verify:**

```bash
adb devices
```

Should print:

```
List of devices attached
<device-id>    device
```

If it says `unauthorized`, the dialog wasn't accepted. Re-plug the cable or check the phone screen.

### Step 2 - Switch ADB to TCP and disconnect USB

**Why:** USB is fine to bootstrap, but for a headless server you don't want a cable hanging off forever. `adbd` can listen on TCP port 5555 over WiFi. Crucially, this **does not survive a phone reboot** on stock unrooted Android - we'll mitigate that with Termux:Boot in Step 5 (for SSH at least; wireless ADB after reboot needs a USB visit).

```bash
adb tcpip 5555
```

`adbd` is now listening on port 5555 of every interface, including wlan0.

Find the phone's IP:

```bash
adb shell ip addr show wlan0 | awk '/inet / { sub(/\/.*/, "", $2); print $2 }'
```

Disconnect the cable, connect over WiFi:

```bash
adb connect 192.168.1.51:5555
adb devices
```

Same device should now show up as `192.168.1.51:5555    device`.

### Step 3 - Reserve a static IP on the router

**Why:** Step 2's `adb connect` needs to know which IP to dial. If DHCP gives the phone a different lease tomorrow, every script breaks. **Pin the IP on the router**, not on the phone. (If "DHCP", "lease", and "reservation vs static" aren't fully solid concepts yet, see [home-networking-fundamentals](../docs/learnings/home-networking-fundamentals.md) for the why.)

Router admin UIs differ; the pattern is the same:

1. Find the phone's MAC: `adb shell ip link show wlan0` returns `link/ether xx:xx:xx:xx:xx:xx`.
2. In the router's DHCP / LAN client list, find the entry for that MAC.
3. Reserve / bind it to a chosen IP (e.g. `192.168.1.51`).

Router-side, not phone-side: phone-side static IP varies by ROM, can break on updates, and doesn't tell the rest of the LAN the address is claimed. Router-side is one place to manage all reservations.

**Verify:** reboot the phone, wait, run `adb shell ip addr show wlan0` - same IP.

### Step 4 - Install Termux from F-Droid and start sshd

**Why:** Termux gives you a real Linux userland on Android - bash, ssh, openssh-server, a package manager - without root. We point our SSH client at its sshd. Use F-Droid's build: the Play Store version was last updated in 2020 and lacks half the packages we need.

Install Termux from F-Droid, open it once. Then:

```bash
# in Termux on the phone
pkg update && pkg upgrade
pkg install openssh
```

Termux's sshd listens on **port 8022** (not 22 - Android reserves low ports for the system).

Set up key-based auth - don't bother with password auth, sshd will reject it by default and storing a Termux user password is a separate footgun:

```bash
# on the laptop
ssh-keygen -t ed25519              # skip if you already have a key
cat ~/.ssh/id_ed25519.pub | adb shell "cat >> /data/data/com.termux/files/home/.ssh/authorized_keys && chmod 600 /data/data/com.termux/files/home/.ssh/authorized_keys && chmod 700 /data/data/com.termux/files/home/.ssh"
```

Start sshd inside Termux:

```bash
sshd
```

Test from the laptop:

```bash
ssh -p 8022 192.168.1.51
```

Should drop into a Termux shell as `u0_a<NN>` (Android wraps each app in its own Linux user; that's normal).

### Step 5 - Termux:Boot for auto-start

**Why:** Steps 2 and 4 require manual commands. After every phone reboot, wireless adb and sshd would need to be re-run by hand. Termux:Boot is a small companion app that runs Termux scripts on device boot - it can re-acquire wake-locks and start daemons.

Install **Termux:Boot** from F-Droid (separate APK from Termux). Open it once after install so Android grants it the necessary permissions, otherwise it never fires.

Create the boot script:

```bash
# in Termux on the phone
mkdir -p ~/.termux/boot
cat > ~/.termux/boot/start-server.sh <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
termux-wake-lock
sshd
EOF
chmod +x ~/.termux/boot/start-server.sh
```

What each line does:

- `#!/data/data/com.termux/files/usr/bin/bash` - Termux's bash lives at this path, not `/bin/bash`. Android has no `/bin`.
- `termux-wake-lock` - acquires a partial wake-lock so Android doesn't kill Termux during deep-sleep.
- `sshd` - starts the SSH daemon. (No `nohup` or `&` needed - sshd daemonizes itself.)

You'll notice this script **does not** re-run `adb tcpip 5555`. That's intentional: stock unrooted Android exposes no programmatic way to flip adbd into TCP mode on boot. Options:

- USB-pair once and run `adb tcpip 5555` after each phone restart, or
- Use a third-party app (Shizuku-based) for unattended TCP-mode toggling - separate setup, out of scope here.

PhoneCTL leans on the SSH path for daily use, so the "wireless-ADB needs USB after reboot" gap is acceptable - reach for ADB when you need ADB-specific things (push/pull, install APK, dumpsys).

**Verify:** reboot the phone, wait 30 seconds, run from the laptop:

```bash
ssh -p 8022 192.168.1.51 'echo OK'
```

Should print `OK`. The phone is now genuinely headless.

### Step 6 - (optional) proot-distro Ubuntu inside Termux

**Why:** Termux's package set is good but limited. For the full Ubuntu apt ecosystem (.NET, certain Python wheels, server tooling that assumes glibc), `proot-distro` runs a real Ubuntu rootfs inside Termux. proot translates syscalls so it looks like a normal Ubuntu shell. PhoneCTL's eventual `phonectl proot` verb drops you straight in.

```bash
# in Termux
pkg install proot-distro
proot-distro install ubuntu
proot-distro login ubuntu
# you're now `root@localhost:~#` inside Ubuntu
```

Watch the disk usage - Ubuntu base is ~500MB, full dev tooling can balloon to 5GB+.

### Step 7 - (optional) Disable battery optimization for Termux

**Why:** Aggressive Doze and OEM-specific task killers can shut down backgrounded Termux even with a wake-lock held. Whitelisting it tells Android to leave it alone.

```
Settings -> Apps -> Termux -> Battery -> Don't optimize
```

Same for Termux:Boot. On Realme / OPLUS / Xiaomi ROMs there's often an extra "lock app in recent apps" toggle that helps too.

## Day-to-day commands

After setup, daily use is mostly through `phonectl`:

| Task | Command |
|---|---|
| Drop into a Termux shell | `phonectl ssh` |
| One-shot remote command | `phonectl ssh 'free -h'` |
| Wireless adb connect (post-reboot, after `adb tcpip 5555` over USB) | `phonectl connect` |
| Phone snapshot | `phonectl status` |
| Pull a file | `phonectl pull /sdcard/Download/foo /tmp/foo` |
| Push a file | `phonectl push /tmp/foo /sdcard/Download/foo` |
| Drop into Ubuntu proot | `phonectl proot` (v0.2) |

## Troubleshooting

Real issues hit during the v0.1 setup, not hypothetical ones:

| Symptom | Cause | Fix |
|---|---|---|
| `adb devices` shows `unauthorized` | RSA prompt was missed | Re-plug USB, accept the dialog on the phone |
| `adb connect` returns `failed to connect to ...:5555: Connection refused` | `adbd` not in TCP mode (most often after a phone reboot) | USB-pair, run `adb tcpip 5555`, retry |
| `ssh -p 8022 ... : Connection refused` | sshd not running in Termux | Reach the phone (USB adb shell or open Termux directly), run `sshd`. If Termux:Boot is configured but didn't fire, open the Termux:Boot app once to grant permissions. |
| `ssh: Permission denied (publickey)` | `authorized_keys` missing or wrong perms | In Termux: `chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys`, verify the public key is actually in the file (`cat`). |
| Termux gets killed in the background after a few hours | Battery optimization or OEM task killer | Whitelist Termux (Step 7); on Realme / OPLUS / Xiaomi also lock the app in recent apps |
| Phone reboots itself overnight | Degraded battery + load discharge spike, or an automatic Android update | Keep it plugged in; check battery health via `adb shell dumpsys battery`; turn off automatic system updates |

## Adding a second phone

The flow above is per-phone, but the laptop side scales cleanly:

- Each phone gets its own DHCP reservation (Step 3) on a unique LAN IP.
- Each phone's `authorized_keys` is populated with the same laptop public key - one key, many phones.
- PhoneCTL v0.1 is single-device. Multi-device profiles (`phonectl use <profile>`) are in the Someday backlog - until then, swap `~/.config/phonectl/config` between phones, or set `PHONECTL_HOST=` and `PHONECTL_SSH_PORT=` per call.
