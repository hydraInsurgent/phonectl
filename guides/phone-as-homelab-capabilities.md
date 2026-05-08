# Phone as a Homelab Server: What You Can and Can't Run

`Last updated: 2026-05-07` - reference for which services this Realme/Termux/proot phone-server can practically host, which it can't, and the workarounds for the constraints inherent to running on non-rooted Android.

This guide assumes the phone is already set up per [phone-server-setup.md](phone-server-setup.md). That covers the mechanics of getting SSH and ADB online; this guide covers what to do with them after.

## How this all fits together

A phone-as-server is not a Linux box. It is a Linux userland (Termux, optionally proot Ubuntu) **running inside a sandboxed Android app**. Most things that work on a Pi work here; some things don't, and the reason is almost always one of three constraints stacking:

```
+-----------------------------------------------------------+
| Service you want to run                                   |
+-----------------------------------------------------------+
       |                |                |
       v                v                v
+-------------+  +-------------+  +-------------------+
| Network     |  | OS sandbox  |  | Hardware envelope |
+-------------+  +-------------+  +-------------------+
| Ports < 1024|  | Termux runs |  | Degraded battery  |
| restricted  |  | as an app   |  | High internal R   |
| ADB rotates |  | uid u0_aXXX |  | Heat is the enemy |
| port + off  |  | No root,    |  | Thermal envelope  |
| on reboot   |  | no kernel   |  | matters a lot     |
|             |  | extension   |  |                   |
+-------------+  +-------------+  +-------------------+
```

Each constraint cuts off a category of services. The trick is recognising which constraint a service hits, and reaching for the right workaround. Most of the time there is one.

## The three persistent constraints

These are the same on any non-rooted modern Android device, not specific to Realme. Recognising them by name makes diagnosing "why won't this work" much faster.

### 1. Ports under 1024 require privileges

Linux convention: TCP/UDP ports below 1024 are reserved for privileged processes. Android inherits this. Termux runs as an app user (`u0_aXXX`), so it cannot bind 22, 80, 443, 53, 25, etc. directly.

This is what forces SSH onto 8022, and what would force any HTTP server onto a high port if you tried to host on the phone alone.

### 2. ADB wireless port rotates per pair, debugging auto-off on reboot

Android 11+ replaced the legacy `adb tcpip 5555` model with a pair-with-code flow that uses a **dynamic** connect port. Every fresh pair gets a new port. The wireless debugging toggle also turns itself off on every reboot, requiring re-pair to re-enable. Without root, neither behaviour can be made persistent.

This bites the diagnostic workflow (`phonectl status`, `phonectl pull/push`) but not the production workflow (SSH on 8022 stays up across reboots once Termux:Boot is configured).

### 3. Termux is sandboxed; it is not real Linux

Termux can install a remarkable amount of software (`pkg install` covers ~1000 packages, `proot-distro install ubuntu` gives you apt). But it cannot:

- Load kernel modules
- Use `iptables` / `nftables`
- Open raw sockets (no ICMP, no custom packet capture)
- Mount NFS / SMB shares
- Run real Docker (containerd needs cgroups + privileged kernel features it cannot reach)
- Bind privileged ports (constraint 1, restated at the OS level)

Every "won't work" item in Tier 3 below is a corollary of constraint 3.

## Capability tiers

Three tiers, by how cleanly the service runs.

### Tier 1 - works cleanly

| Service | Where it runs | Notes |
|---|---|---|
| **SSH server** | Termux native, port 8022 | Already part of `phone-server-setup`. Stable across reboots via Termux:Boot. The primary access channel. |
| **Tailscale** | Tailscale Android app + ACL in their dashboard | The single biggest unlock for accessing the phone from outside your LAN. Bypasses port-forwarding and TLS issues entirely - your phone gets a hostname like `realme.tail-scale.ts.net` and other devices on your tailnet just reach it. |
| **Static web server** (Caddy, nginx, lighttpd) | proot Ubuntu, listen on 8080 | Router forwards public 80 -> phone:8080. Caddy in particular handles auto-HTTPS via Let's Encrypt if you also have a public hostname pointed at the IP. |
| **Git remote** (Gitea, Forgejo) | proot Ubuntu, plus `git` over SSH on 8022 | Git-over-SSH needs no extra port-forwarding because it rides on 8022 which you already have. |
| **`code-server`** (VS Code in browser) | proot Ubuntu | High port + Tailscale to reach it. Lets you edit on the phone from any laptop browser. |
| **Backup target** (rsync over SSH) | Termux native | rsync to `phone:8022:/some/path`. Works out of the box. |
| **Cron jobs** | Termux: `pkg install cronie` | Persistent if the boot script also starts cronie. |
| **Database** (SQLite, Postgres, MySQL) | proot Ubuntu | Local to the phone or accessed via SSH tunnel from a client. Not exposed publicly without good reason. |
| **API server** (Node, .NET 8 ASP.NET, Python Flask, Go) | proot Ubuntu | High port + reverse proxy + Tailscale. .NET on this device is comfortable for a self-taught .NET dev's homelab projects. |
| **Reverse proxy with auto-HTTPS** (Caddy) | proot Ubuntu | Caddy auto-issues Let's Encrypt certs given a public hostname. Handles TLS termination so your app servers don't have to. |
| **Static file hosting / personal site** | Caddy serving a directory | Plus router port-forward 80 -> 8080. |

### Tier 2 - works with caveats

| Service | The caveat |
|---|---|
| **Home Assistant** | Runs in proot Ubuntu via the pip path. Most integrations work; some that rely on direct mDNS multicast send (Sonos, certain Apple-ecosystem devices) may misbehave because Termux's networking abstraction is one layer removed from the host adapter. Light HASS use is fine; running HASS as the family's primary smart-home brain is not the use case the device is best at. |
| **Media server** (Jellyfin) | Direct file serving works fine. **Live transcoding does not** - it pegs the CPU at 100% and the degraded battery's thermal envelope can't sustain it. Solution: pre-transcode media into formats your clients play directly (`-c copy` mux to a friendly container), serve those files, never let Jellyfin auto-transcode. |
| **VPN endpoint** | Tailscale: clean install, works perfectly. WireGuard direct: needs root. Use Tailscale. |
| **Game server** (Minecraft Java, Factorio, etc.) | Works on a high port + router forward. The thermal caveat dominates - a server with many players holds CPU in the 50-100% band, which heats the cell continuously. Acceptable for short sessions; a permanent always-on game server is risky for the battery. |
| **Mail receiving** (SMTP on 25, IMAP on 143/993) | Inbound mail from a residential IP is essentially impossible regardless of phone vs Pi: ISPs block port 25 inbound, the IP is on RBLs, and big providers (Gmail, Outlook) reject mail from un-warmed residential ranges. Use a transactional email service (Postmark, Resend, ForwardEmail) for any "I want a custom domain mailbox" use case. |
| **DNS server on port 53** | Privileged port, plus most home routers don't let you forward 53 inbound cleanly. AdGuard Home or Pi-hole on a high port works for clients you can configure manually but is not transparent to the rest of the LAN. |

### Tier 3 - won't work without root

Don't try these on this device. Each one fails for a kernel or sandbox reason that no userland workaround can fix.

| Service | Why it fails |
|---|---|
| **Docker / containerd** | Needs cgroups v2, namespaces, and privileged kernel features that Termux can't access. proot-distro is the *not-quite-Docker* substitute - good enough for "I want a real Ubuntu environment", not good enough for "I want to run containerized services". |
| **NFS server** | Kernel module + privileged port. |
| **Samba / SMB server** | Privileged ports (139, 445), kernel-level filesystem hooks. |
| **Pi-hole on port 53** | Privileged port. (See Tier 2 for the high-port partial workaround.) |
| **Custom packet capture, ICMP responders, raw sockets** | All need `CAP_NET_RAW`. |
| **`iptables` / firewall rules** | Need root + kernel access. |
| **USB peripheral hosting** (phone *as* a USB drive on your laptop) | Needs root + custom kernel module. |
| **Bluetooth profile servers** | App permissions plus typically root. |

## Workarounds for the inherent constraints

Three workarounds together cover the realistic majority of "things you might want to do".

### Workaround A: Router port-forward for the privileged-port problem

External port 80 -> internal `192.168.1.51:8080`. Configure once in the router's admin UI; every Termux/proot service that listens on 8080 is now reachable at `http://your-public-ip/`. Same trick for 443 -> 8443 if you want HTTPS without going through a tunnel service.

This is the cheapest, most homelab-standard solution. No phone changes, no extra software.

If the IP / DHCP / NAT / port-forwarding chain isn't fully intuitive yet, read [home-networking-fundamentals](../docs/learnings/home-networking-fundamentals.md) first. It explains why the public-port-to-internal-port mapping is necessary and what it doesn't fix.

### Workaround B: Tailscale for "reach this phone from anywhere"

Install the Tailscale Android app, sign in. The phone joins your tailnet. From any other device signed into the same tailnet (laptop, other phone, server in a different city), you reach the phone via its tailnet hostname - no port-forwarding, no public IP, no DDNS, no TLS to set up.

This is the right answer for any service you want to reach yourself but not expose publicly. Most homelab services fall in this bucket: code-server, internal dashboards, file shares, dev databases.

For services you do want to expose to the public internet, Tailscale Funnel (built into Tailscale, free for hobby use) gives you a public TLS-terminated URL that proxies to the phone.

### Workaround C: SSH-based production, ADB only when you need it

Production traffic (services, automation, day-to-day) goes over SSH on 8022, which is stable across reboots once Termux:Boot is configured. ADB is reserved for diagnostic and dev tasks (`phonectl status`, `phonectl pull/push`, dumpsys queries), used from your laptop when you happen to be sat at it.

This separation means the dynamic-port and reboot-off behaviour of ADB only impacts the dev workflow, not the running services. The PhoneCTL backlog item `phonectl pair` automates the re-pair dance for the dev workflow, removing the only real friction.

## Battery and thermal envelope (specific to this degraded cell)

Generic phone-as-server advice would say "don't worry about CPU, it's a phone, it idles fine". With this specific Realme GT Master and its degraded battery (BMS rejects high-current charge, ~30-50% lost capacity, elevated internal resistance), the thermal advice is non-trivial.

**The rule**: anything that pegs CPU at 100% for sustained minutes will accumulate heat in the cell over time, which accelerates further degradation. Light services running mostly idle are perfect.

Avoid:

- Live video transcoding (Jellyfin auto-transcoding, Plex, ffmpeg in real time)
- ML inference / on-device TensorFlow / Stable Diffusion
- Compiling large projects regularly (full Linux kernel, Chromium, large Rust workspaces)
- Crypto mining (obviously)
- Cellular hotspot mode while on duty (radio + CPU heat)
- Heavy gaming server with many players (sustained CPU bands)

OK to run:

- Static web hosting
- Git operations (occasional clones / pushes)
- SSH session multiplexing
- Light database queries (a few thousand records, indexed)
- File shuffling, rsync backups
- Monitoring / metrics collection
- API serving low-traffic endpoints
- Home Assistant automation rules (idle most of the time)
- Tailscale relay
- The PhoneCTL battery logger itself (negligible)

The phone case should stay off and the device should sit on an elevated stand for airflow. Both directly observed in this project: `temp_c` in the battery log dropped 2-4 degrees consistently after we removed the case and elevated the phone, with no other change.

For the heavy workloads you actually want to run someday, plan to graduate to a Raspberry Pi 4/5 (~$60-80) or a cheap used mini-PC ($100-200). Not a today problem; a "when you outgrow this" problem.

## Recommended install order for the homelab kit

After [phone-server-setup.md](phone-server-setup.md) is complete, install these in order. Six items, all free except Tasker (which is optional and listed last).

1. **Termux:Boot** (F-Droid APK). Already covered by phone-server-setup.md Step 5. Listed here for completeness because everything below depends on services surviving reboots.

2. **`termux-api` package + Termux:API app** (F-Droid APK). Grants Termux access to Android's BatteryManager, sensors, notifications, location, audio. Relevant for the eventual phone-side battery logger and on-device alerting. Install both: the package alone is just CLI wrappers around Intent calls to the app.
   ```bash
   pkg install termux-api    # in Termux
   # plus install Termux:API APK from F-Droid
   ```
   <!-- TODO when phone-side battery logger ships: link the script + tmux/Termux:Boot wiring here. -->

3. **proot-distro + Ubuntu** (`pkg install proot-distro`). Already covered by phone-server-setup.md Step 6. Gives you the apt ecosystem inside Termux. Most server software in Tier 1/2 above assumes this environment.

4. **Caddy in proot Ubuntu**. Reverse proxy with auto-HTTPS, listens on 8080 (port-forward target) or 8443. <!-- TODO when first deployed: capture Caddyfile snippet here, plus the systemd-style autostart inside proot (since proot doesn't have systemd, this needs a custom approach - a startup script invoked from the proot login command). -->
   ```bash
   proot-distro login ubuntu
   apt install caddy
   ```

5. **Tailscale (optional)**. Android app, free for personal use. Recommended for any "reach the phone from outside your LAN" use case. Skip if all your access stays on your home network and you've handled it via DHCP reservation already.

6. **`code-server` in proot Ubuntu (optional)**. <!-- TODO when first installed: capture the install command (their published Linux script), the port chosen, and the Caddy reverse-proxy config that fronts it. --> Lets you edit code on the phone from any browser.

## Day-to-day: pick a service, find the path

A quick lookup for "I want to run X, how does it reach me?".

| Want to run | Listens on | Reach it via |
|---|---|---|
| Personal static site | Caddy:8080 | Router forward 80 -> 8080, public DNS A record |
| Internal dashboard (Grafana etc.) | App on high port | Tailscale - never expose internal dashboards publicly |
| Git remote | sshd:8022 | `git clone manu@phone:8022/path` (on tailnet or LAN) |
| Code editing from your laptop | code-server:8443 | Tailscale, or Caddy reverse-proxy + Tailscale Funnel |
| Backup target | sshd:8022 | `rsync -av src/ manu@phone:8022:dest/` |
| API for a project you're building | App on high port | Tailscale for dev, router-forward + Caddy for production |
| Home Assistant | hass:8123 | Tailscale; HA companion app uses the tailnet hostname |

Pattern: **internal use -> Tailscale; public use -> router-forward + Caddy + DNS.**

## What changes if you root

Rooting unlocks all three constraints simultaneously:

- Persistent `adb tcpip 5555` across reboots (via Magisk module, fixed port)
- Bind privileged ports directly (no router forward needed for 80/443)
- Real Docker, Pi-hole on 53, NFS/Samba, iptables firewall

Cost: bootloader unlock voids warranty, wipes all data on unlock, breaks SafetyNet/Play Integrity (banking apps, UPI, Netflix, some games stop working), and is risky to attempt with a degraded battery (a power drop mid-flash can brick the device).

For PhoneCTL's current scope, rooting is not worth it. The router-forward + Tailscale + SSH-based production combo handles ~95% of realistic homelab needs without rooting. Revisit only if you hit a specific Tier 3 use case you can't live without.

## What changes on a Pi or mini-PC

When you eventually graduate to a Raspberry Pi 4/5 or a used mini-PC for serious self-hosting, the patterns transfer cleanly:

- Same Tailscale tailnet, same hostname conventions
- Same Caddy config, same Caddyfile
- Same SSH keys
- All Tier 3 services unblock (Docker, Samba, NFS, Pi-hole on 53, real container orchestration)
- Privileged ports just work (no router forward needed for 80/443 - though most homelabs forward to high ports anyway as a security choice)
- Battery considerations evaporate (Pi runs from a wall PSU; the mini-PC has a real PSU)

The phone-as-server work isn't wasted in that future. It's the same architecture, just with one of the three constraints class evaporated. PhoneCTL stays useful as a phone-specific dev tooling layer; everything else (Tailscale, Caddy config, SSH workflow, service setup) carries over.

## Future expansion of this guide

When the items below land, fill in the relevant `<!-- TODO -->` markers above:

<!-- TODO when phonectl battery / battery log verbs ship: add a row in the "what to install" section pointing at them; remove the standalone ~/battery-logger.sh reference. -->

<!-- TODO when first real production service is deployed (e.g. personal site, code-server): add a "first deployment walkthrough" section here, OR split this guide into two with the operational walkthrough as a separate file. -->

<!-- TODO when Caddy is installed and configured: capture the Caddyfile, the autostart approach inside proot, and the router port-forward UI screenshot or text instructions. -->

<!-- TODO when you decide to attempt Cloudflare Tunnel or Tailscale Funnel for a public-exposure use case: document the chosen path and why over the alternative. -->
