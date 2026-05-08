---
title: 'WiFi Association vs DHCP Lease: Why a Connected Device Can Be Unreachable'
category: networking
tags: [arp, dhcp, wifi, association, mac-randomization, wifi-psm, android-power, doze, lan, ping]
related:
  - home-networking-fundamentals.md
  - termux-and-proot-on-android.md
first_encountered: PhoneCTL phone-as-homelab debugging session
created: 2026-05-08
updated: 2026-05-08
---

# WiFi Association vs DHCP Lease: Why a Connected Device Can Be Unreachable

A device's WiFi UI says "Connected", you can play YouTube on it, but `ssh user@<its-IP>` from another machine on the same LAN fails with `No route to host`. This is one of those situations where every component looks fine in isolation and the bug lives in the gaps between them. Three different layers can be silently broken under one "connected" label, and a router's admin UI usually shows you two of them in different tabs without being explicit that they mean different things.

## Mental model

Reaching a device on your LAN is a chain of state, and the chain has more links than the wireless UI suggests:

1. **Physical** - radio is powered, signal is strong enough.
2. **WiFi association** - the device has handshaked with the access point. The AP keeps a per-MAC table of currently-associated clients.
3. **IP assignment** - the device has an IP, either from a DHCP exchange or set statically. The router's DHCP server has a separate table of outstanding leases.
4. **L2 reachability** - the LAN's bridge knows which port a given MAC is on, so frames addressed to that MAC get delivered. ARP is the protocol that maps an IP to its MAC on the LAN.
5. **L3 / app reachability** - the device's OS routes the packet to the listening process.

A device can have internet access (links 1-3 working enough to reach the WAN) while breaking link 2 or 4 from a *different* LAN client's perspective. The WiFi UI on the phone only knows about links 1-3. Your laptop's `ssh` cares about links 1-5.

## The two router-side tables (and why they disagree)

A typical router admin shows two tables that look similar but mean very different things:

| Table | What it actually says | Stale-able? |
|---|---|---|
| **DHCP "Active Clients" / lease list** | "I (the DHCP server) promised IP X to MAC Y for N more seconds" | Yes - persists for the full lease (often 24 hours) even after the device disconnects |
| **WLAN "Associated Clients"** | "Right now, MAC Z is currently associated to my radio" | Real-time - drops the moment the device disassociates |

A device can sit in the first table without being in the second. That state means: "the router has not forgotten about this device's IP reservation, but the device is not actually on the radio at this moment." Causes range from screen-off radio sleep, to the device having walked out of range, to it having moved to mobile data.

Your laptop's `ssh` cares only about whether the device is reachable now. The DHCP table tells you what *was* true. The association table tells you what *is* true. When they disagree, trust the association table.

## ARP `<incomplete>` is the smoking gun

When you `ping 192.168.1.51` from another LAN host, the kernel doesn't put `192.168.1.51` into the ethernet frame; it needs the MAC. So it broadcasts an ARP request: "who has `192.168.1.51`? tell me." If a device is alive on the LAN with that IP, it answers with its MAC. The kernel caches the mapping (`arp -an` on Linux, `arp -a` on macOS / Windows) and uses it for actual delivery.

`<incomplete>` in the ARP table means: "I asked, and nobody answered." Three meaningful causes:

- The IP is genuinely unclaimed - no device currently has it on this LAN.
- A device has it but is not on the LAN at the link layer (disassociated, sleeping radio, moved bands).
- There's an L2 filter between you and the device (AP isolation, VLAN split, port-based ACL) that drops the broadcast or its reply.

It is *not* an authentication or firewall problem at the destination - those would manifest at higher layers. ARP is below all of that.

The diagnostic value: ARP `<incomplete>` rules things out. If ARP works (returns a MAC), the problem is higher up the stack - sshd not running, port closed, host firewall. If ARP fails, you have a link-layer problem and there's no point checking sshd yet.

## WiFi Power Save Mode (PSM): the latency signature

When a wireless client has been idle, its radio enters Power Save Mode. The radio sleeps and only briefly wakes at fixed beacon intervals (typically 100-300 ms) to check for queued traffic. Symptoms when you `ping` a PSM-asleep device:

```
ping -c 5 192.168.1.51
64 bytes ... time=65.5 ms
64 bytes ... time=75.7 ms
64 bytes ... time=5.94 ms
64 bytes ... time=2.31 ms
64 bytes ... time=2.18 ms
```

The first reply or two are slow because the AP queued the request and delivered it on the next wake interval. After the radio "notices" there's traffic, it stays awake and subsequent latency drops to normal LAN values (single-digit ms). This pattern is a strong signal that:

- The device is associated (otherwise replies wouldn't come at all).
- It was just sleeping, not gone.
- It is not in deep "disassociated" state.

If pings simply time out with no replies, the device is in a different state - probably disassociated, or genuinely off the LAN.

## MAC randomization on modern phones

Recent Android, iOS, and Windows phone modes implement **per-network MAC randomization** for privacy: the device generates a fake MAC per SSID instead of using its hardware MAC. The fake MAC has the locally-administered bit set in its first byte - the second-to-last bit of the first octet equals 1, so values whose first byte is `9a:`, `b2:`, `e6:`, `c2:`, `36:` etc. are giveaways. Real vendor OUIs almost always have that bit clear (`10:`, `b8:`, `7c:`, `00:`).

Implementations vary in *when* they re-randomize:

- Reuse the same fake MAC every time you join the same SSID. (Most common.)
- Generate a new fake MAC every time you join, even to the same SSID.
- Generate a new fake MAC every time you switch between bands (e.g., 5 GHz `<->` 2.4 GHz on the same router).
- Time-rotated re-randomization on a schedule.

The implication for a phone-as-server use case is that **DHCP reservations and firewall rules pinned to a MAC address can silently break** when the device picks a new MAC. The lease-by-MAC promise the router made yesterday no longer applies, and the device gets a fresh dynamic IP from the pool. Symptoms: phone "appears connected" but is at a different IP than expected, or has the same IP but the router's reservation no longer matches its current MAC.

Fix at the device side: turn off MAC randomization for the SSID(s) the phone uses as a server. On Android this is per-SSID under the network's settings, often labeled "Privacy" with a toggle between "Use randomized MAC" and "Use device MAC". After flipping, *forget the network and rejoin* to ensure a clean association under the real MAC.

## Android's separate power domains

Android has multiple independent "wakelock" types because the power domains are independently switchable:

| Power domain | What it controls | Wakelock type |
|---|---|---|
| CPU | whether processes can run | `PARTIAL_WAKE_LOCK` |
| Screen | display backlight | `FULL_WAKE_LOCK` |
| WiFi radio | the WiFi chip's transmit/receive state | `WIFI_LOCK` (separate API) |

The Termux "wakelock held" persistent notification is a `PARTIAL_WAKE_LOCK`: the CPU stays on, the shell process keeps state. This is *not* the same as a `WIFI_LOCK`. The radio can sleep, drop to low-power state, or even fully **disassociate** from the AP, all while the CPU is happily running.

For an "always-reachable" use case, the phone needs all of:

- A CPU wakelock (Termux's, or equivalent for the relevant app).
- Battery-optimization / Doze override for that app, since Doze can ignore wakelocks beyond a threshold.
- Either an OS-level "WiFi keep-on" policy (removed from user-facing Settings since Android 10 on most skins) **or** a periodic outbound traffic source (any small packet every minute keeps the radio active).

Even with all three in place, OEM "smart power saver" features (separate from AOSP Doze) can still kill the radio. Each manufacturer's UI exposes these toggles in different places.

## Diagnostic ladder

When `ssh phone` fails on the LAN, walk this in order:

```
1. arp -an | grep <phone-ip>
   ├─ <incomplete>  → link-layer problem; go to step 2
   └─ real MAC      → ARP works, problem is higher up. Check sshd, port, firewall.

2. Walk to phone, toggle WiFi off and on.
   └─ Re-run step 1. If now reachable, the phone had silently disassociated.

3. Router admin: DHCP lease table.
   └─ Phone's MAC has a different IP than expected? MAC randomization changed something.
   └─ Phone's MAC absent from lease table? Phone may never have re-registered after a power event.

4. Router admin: WLAN associated-clients table.
   └─ Phone's current MAC is not in this list? Phone is not on the radio right now.

5. From the phone, try outbound traffic to the laptop.
   └─ If the phone can reach the laptop but not vice versa, you have asymmetric isolation -
      check AP-isolation / client-isolation toggles on the router (often per-band).

6. ARP works, ping works, but TCP fails.
   └─ Now it's a host-side problem: sshd not running, port closed, app firewall.
```

Most home-server cases stop at step 2 or 3.

## Durable-fix recipes

Once you've identified which layer broke, the fixes cluster.

**Stable identity at the link / network layer** - for any device that should always be reachable at a known IP:

- Disable MAC randomization on the device for that SSID. It now presents its real hardware MAC.
- Either configure a static IP on the device, or set a DHCP reservation on the router, or do both for belt-and-suspenders. Static IP makes the device immune to a temporarily-unavailable DHCP server; the reservation prevents another device from racing for the same IP.

**Always-on radio** - for a server that must survive overnight:

- Disable battery optimization for the server app (Termux, Tasker, etc.).
- If the OS exposes "Keep WiFi on during sleep", set it to "always". On Android 10+ this toggle is hidden from Settings on most skins; check developer options or accept that you need a keepalive.
- Schedule an outbound keepalive (a 64-byte ping to `1.1.1.1` once a minute) from the device. This is the most reliable cross-platform way to prevent radio-level sleep that escalates to disassociation. Cost is negligible (~250 KB/day) and it dominates over any battery saving from sleep, since avoided reconnect storms are themselves expensive.

**Visibility** - log the state so you don't have to dig later:

- Snapshot the router's DHCP lease table and WLAN associated-clients table side-by-side when things are working. The MAC mapping you see there is the contract you want to preserve.
- Note the `arp` output for the device on a working day. If it changes, MAC randomization is in play even when you thought you'd disabled it.

## When this isn't the right diagnosis

Worth ruling out cases that look similar but require different fixes:

- **Different LANs**: laptop and phone are on different SSIDs that happen to use the same `192.168.x.x` range but route through different APs. Your packet never reaches the right LAN. Check which AP each device is associated to.
- **AP / client isolation**: the router has a setting (called "AP Isolation", "Client Isolation", "Wireless Isolation", "Relay Blocking", or "WLAN Partition" depending on vendor) that prevents WiFi clients from talking to each other or to the wired LAN. ARP would still fail with `<incomplete>` from the wired side - identical symptoms to disassociation. The give-away is that ARP from another *wireless* client also fails, and the phone is provably online on the radio.
- **DHCP pool exhaustion**: rare on home routers but possible. New device joins, no lease available, gets stuck in DHCP-discover loop. Phone shows "Connecting..." in the WiFi UI rather than "Connected".

## Source of confusion

The single biggest reason this class of bug exists is that "connected" on a phone's WiFi UI is a flag that means *the phone successfully completed steps 1-3 at some point in the recent past*. It does not mean *steps 1-3 are still true now*. Android (and iOS, and Windows) all keep showing "Connected" through brief disassociations because re-association is usually fast and surfacing the dropouts would be UX noise. The cost of that UX choice is exactly this debugging session: a phone that says "connected" while everything below the surface has gone quiet.
