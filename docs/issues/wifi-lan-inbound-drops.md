# Phone disappears from the LAN (ARP `<incomplete>`) after idle

| Field | Value |
|---|---|
| Status | **Mitigation in place** (keepalive ping loop in Termux:Boot script); reproducible if mitigation fails |
| First observed | 2026-05-08 |
| Last verified missing | 2026-05-09 (LAN reachable, keepalive appears to be working) |
| Severity | Medium - blocks all inbound LAN services (sshd, tasklog-web, tasklog-api) until phone WiFi is cycled |
| Affects | Realme GT Master (RMX3360) running ColorOS / Realme UI 13 on Android 13. May affect other ColorOS / aggressive-PSM ROMs the same way. |
| Related learning | [home-networking-fundamentals](../learnings/home-networking-fundamentals.md), [wifi-association-vs-dhcp-lease](../learnings/wifi-association-vs-dhcp-lease.md) |

## Symptom

After an idle period (sometimes minutes, sometimes hours), the phone vanishes from the LAN even though it's still associated to the AP and outbound traffic from the phone works fine.

- Outbound from phone: cloudflared tunnel stays up, browsers reach LAN sites fine, the phone has internet.
- Inbound from laptop on same LAN: all ports time out / "No route to host".
- Cycling WiFi off and on on the phone immediately restores reachability for some period, then it dies again.

Note: no SIM in the phone, so any internet activity on the phone proves WiFi is genuinely working from the phone's perspective. The failure is purely the inbound L2 path from the LAN.

## Confirming it is THIS issue (diagnostic chain)

Run from the laptop (or another LAN host):

```bash
ping -c 3 -W 2 192.168.1.51            # expect: Destination Host Unreachable from <laptop-ip>
arp -an | grep 192.168.1.51            # expect: ? (192.168.1.51) at <incomplete> on <iface>
nc -zv 192.168.1.51 8022 -w 3          # expect: timeout / No route to host
nc -zv 192.168.1.51 3000 -w 3          # expect: same
```

The signature is **all four failing**, and specifically `arp -an` showing `<incomplete>`. That `<incomplete>` is what distinguishes this issue from "sshd died" or "port not bound" (where ARP would resolve cleanly to the real MAC `10:82:d7:96:67:fd` but the TCP port would return `Connection refused`).

If ARP resolves but ports refuse: a different issue (process down on the phone, not LAN reachability). See [the sshd-down note](#related-but-distinct-sshd-down-while-other-services-up) at the bottom.

## Root cause (two layered effects)

1. **Android WiFi Power Save (PSM) on ColorOS is aggressive.** The radio's TX path stays warm enough for outbound (cloudflared QUIC keepalives, etc.) to wake it briefly. RX path drops into deep sleep where wake intervals stretch out so far that incoming ARP and TCP-SYN packets are dropped.
2. **Router bridge MAC-table aging.** The router learns "MAC X is on WiFi port Y" only when the phone sends a frame. Default aging is ~5 minutes. If the phone goes radio-quiet for that long, the router forgets which port owns the MAC, so an ARP "who has 192.168.1.51?" arriving from the wired LAN has nowhere to be relayed.

The "WiFi toggle fixes it" pattern is consistent with both: forced re-association sends frames immediately, re-teaching the router's bridge AND waking the radio's RX path.

Why we can't fix it the obvious way:

- The Android UI toggle "Keep WiFi on during sleep" that older versions had is **removed in ColorOS / Realme UI 13 + Android 13**.
- `WifiManager.WifiLock` is the Android API for keeping the radio fully active, but Termux:API does not expose it.
- Without root we cannot change PSM behaviour at the OS level.

## Mitigations tried

### v1: ping the router every 30s (read gateway via `ip route`) - DID NOT WORK

Initial keepalive script:

```bash
while true; do
  GW=$(ip route | awk '/^default/ {print $3; exit}')
  if [ -n "$GW" ]; then
    ping -c 1 -W 2 "$GW" >/dev/null 2>&1 || true
  fi
  sleep 30
done
```

**No-op for 22 hours.** Every iteration logged:

```
Cannot bind netlink socket: Permission denied
```

Both `ip route` AND `cat /proc/net/route` are locked down on Android without root - the unprivileged Termux process can't read the routing table at all. So `$GW` was always empty and the conditional ping never fired.

For reference: `ping 192.168.1.1` from Termux works fine (Android allows unprivileged ICMP datagrams to specific hosts; netlink access for routing-table reads is what's blocked).

### v2: ping with hardcoded gateway + logging - IN PLACE (mitigation)

Current keepalive script (runit-supervised at `$PREFIX/var/service/tasklog-keepalive/run`):

```bash
#!/data/data/com.termux/files/usr/bin/bash
exec 2>&1
TARGET="${KEEPALIVE_TARGET:-192.168.1.1}"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] starting, target=$TARGET"
while true; do
  if ping -c 1 -W 2 "$TARGET" >/dev/null 2>&1; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ping ok"
  else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ping FAIL"
  fi
  sleep 30
done
```

Logs at `$HOME/log/tasklog-keepalive/current` (svlogd auto-rotates).

**Status: appears to be working** as of 2026-05-09 - LAN reachability has held since the v2 script was started. Watch the logs over a longer window to confirm.

### Fallback if v2 isn't enough: Tasker periodic WiFi toggle

Not yet built. The plan if v2 fails:

- Build a Tasker profile that toggles WiFi off-and-on every N minutes (15-30 candidate). Crude but it's the only thing that's been observed to fully restore reachability when the radio is fully asleep.
- Or: a Tasker profile that monitors "no inbound TCP connection in last X minutes" (somehow) and toggles WiFi only when needed.

## When the issue recurs - quick playbook

1. **Run the diagnostic chain above** to confirm it's this issue (not sshd dead, not some other process down, not router-side).
2. **Check the keepalive log on the phone**: `tail -50 $HOME/log/tasklog-keepalive/current`.
   - If full of `ping FAIL` lines: the radio's TX path is dead too. Mitigation is insufficient. Escalate to Tasker toggle.
   - If full of `ping ok`: outbound works but inbound is still blocked. The bridge-table-aging theory doesn't fit. Look elsewhere - possibly **AP isolation got toggled on at the router** ([Network → WLAN → Advanced](../../assets/Router/MAP.md#network-tab) on the SY-GPON router; verify both bands). Or some new firmware behavior.
3. **Immediate recovery**: physically toggle WiFi off/on on the phone (Quick Settings tile). Fast, reliable.
4. **If you can't reach the phone physically** and SSH is also dead: nothing remote works. The phone has fallen completely off the LAN at L2. No SIM = no cellular wake. Wait for re-association or get to the phone.

## Why we cannot do it from outside (when it's stuck)

Tried during a failure window:

```
ssh -p 8022 192.168.1.51 'termux-wifi-enable false; sleep 2; termux-wifi-enable true'
```

Returned `No route to host` because SSH itself cannot reach the phone (same ARP-incomplete problem prevents the SSH handshake too). Any "remote fix from laptop" only works if there's already a working L3 path; once that's gone the laptop has nothing.

## Open questions worth investigating later

- Does an Android app that *just* holds `WifiManager.WifiLock` (a tiny sideloaded APK) prevent the radio's RX from sleeping at all? Would make the keepalive script redundant.
- Is there a Termux package or APK already shipping such a `WifiLock` holder?
- Does ColorOS / Realme UI 13 have hidden flags (via `adb shell settings put global ...` keys) that control PSM aggressiveness without root? Some older Android keys (`wifi_sleep_policy`) may still work, may not.
- Can a gratuitous ARP be sent from the phone-side without root or raw sockets? (Probably no - but worth confirming.)

## Related but distinct: sshd down while other services up

Observed 2026-05-09 alongside the LAN-reachability verification: ports 3000 (tasklog-web) and 5115 (tasklog-api) were both reachable, but port 8022 (sshd) returned `Connection refused`. ARP resolved fine - so this is NOT the LAN-reachability issue; sshd specifically is not listening.

Per `docs/setup-state.md`, sshd is started directly by the Termux:Boot script (not under runit), so it's not auto-restarted on failure. Likely fixes when the issue recurs:

- Open Termux on the phone, run `sshd`.
- Or reboot the phone (Termux:Boot will re-run the start script).
- Or migrate sshd into runit supervision (separate cleanup task; the `sv status sshd` entry that's currently DOWN in runit is the disabled stub - would need re-enabling and the boot-script sshd line removed).

If this recurs too, it's worth its own issue doc and a runit-supervision migration.
