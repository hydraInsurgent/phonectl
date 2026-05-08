---
title: 'Home Networking Fundamentals: IPs, DHCP, NAT, and Port Forwarding'
category: networking
tags: [ip, dhcp, nat, port-forwarding, lan, router, home-networking, private-ip]
related:
  - wifi-association-vs-dhcp-lease.md
first_encountered: PhoneCTL phone-as-homelab work
created: 2026-05-07
updated: 2026-05-08
---

# Home Networking Fundamentals: IPs, DHCP, NAT, and Port Forwarding

These four concepts interlock. You can't really understand port forwarding without NAT, you can't understand NAT without knowing why private IPs exist, and you can't understand DHCP without knowing what an IP is doing in the first place. Most "why doesn't my home server work" questions come down to one of these four ideas being slightly misunderstood. Worth learning them as a chain rather than four disconnected topics.

## Mental model

Your home network is a small LAN where every device has a **private** IP address (something like `192.168.1.51`) handed out by a **router**. The router itself has two faces:

- An internal face on the LAN, where it talks to your devices
- An external face to the public internet, where it has *one* **public** IP given to it by your ISP

When your laptop wants to fetch `google.com`, the request leaves your laptop with a private source IP. The router does **NAT**, rewriting that source to the router's public IP before it goes out to the internet. Google's response comes back addressed to the router's public IP; the router undoes the rewrite and delivers it to the right internal device. Many devices, one public IP, all sharing.

Inbound connections from the internet *don't* work this way by default. They have nowhere to go: the public IP is the router, and the router doesn't know which internal device should receive an unsolicited packet. **Port forwarding** is the explicit rule that says "incoming traffic to port 80 on my public IP, send it to `192.168.1.51:8080`" - it's how internal services become reachable from outside.

**DHCP** is the protocol that gives devices their private IPs in the first place. Router has a pool of addresses; device joins the network and asks; router assigns one and tracks it.

```
 Internet                                Your home LAN
 ────────────                            ─────────────────────────────
                                          192.168.1.0/24
                                          (private, RFC 1918)
                                          
 ┌─────────┐    public IP        ┌────────┐ private IPs ┌──────────┐
 │ Google  │ ◄──────────────► │ Router │ ◄────────► │ Laptop   │ 192.168.1.37
 │         │   e.g. 49.x.y.z    │        │             │ Phone    │ 192.168.1.51
 │ Discord │                    │        │             │ TV       │ 192.168.1.10
 │  ...    │                    └────────┘             │ ...      │
 └─────────┘                       │  │                └──────────┘
                                   │  │
                              NAT  │  │  DHCP
                              ─────┘  └────  
                              source IP    pool: 192.168.1.100 to .200
                              rewrite      lease: ~24h
```

## Why these concepts exist

### Private IPs and RFC 1918

IPv4 addresses are 32-bit, giving about 4.3 billion possible values. There are way more than 4.3 billion devices on Earth, so doling out one public IP per device was never going to work past the late 1990s.

The solution **RFC 1918** standardised in 1996: reserve three address ranges as "private". Anyone can use them internally, but they can't be routed on the public internet. The three ranges:

| Range | CIDR | Common use |
|---|---|---|
| `10.0.0.0` – `10.255.255.255` | `10.0.0.0/8` | Large corporate networks |
| `172.16.0.0` – `172.31.255.255` | `172.16.0.0/12` | Less common; some VPN tools |
| `192.168.0.0` – `192.168.255.255` | `192.168.0.0/16` | Almost every home network |

Your home router carves a `/24` slice (256 addresses) out of `192.168.0.0/16`, typically `192.168.1.0/24` or `192.168.0.0/24`. Within that slice, addresses go to your devices.

These addresses are "yours forever" in the sense that nobody else on the internet can reach them directly, and you can use them freely without coordinating with anyone. Two different homes can both have a `192.168.1.51` device; their packets never collide because they never leave their respective private LANs intact.

### CIDR notation, just enough to read

`192.168.1.0/24` has two parts. The `/24` is **CIDR notation** for "the first 24 bits of the address are the network prefix; the remaining 8 bits identify devices within that network". 32-bit address minus 24 bits of prefix leaves 8 bits = 256 possible hosts (`.0` through `.255`).

You'll see CIDR everywhere:

| Notation | Total addresses | Common use |
|---|---|---|
| `/8` | 16,777,216 | The whole `10.0.0.0/8` block |
| `/16` | 65,536 | A medium-sized network |
| `/24` | 256 | Typical home LAN |
| `/30` | 4 | Point-to-point links |
| `/32` | 1 | A single specific address |

You don't need to memorise the math. You need to recognise that `/24` means "this little network", `/8` means "a huge network", and the slash followed by a smaller number means a bigger network.

### DHCP

Without DHCP, every device joining the network would need its IP, subnet mask, gateway, and DNS server set by hand. DHCP (Dynamic Host Configuration Protocol) automates it.

The exchange is four messages, often abbreviated **DORA**:

```
Device → broadcast: "DHCP Discover" - "I'm new, anyone running DHCP?"
Router → device:    "DHCP Offer"    - "I am, here's 192.168.1.123, valid for 24h"
Device → router:    "DHCP Request"  - "OK I'll take it"
Router → device:    "DHCP Ack"      - "Confirmed, you're 192.168.1.123 until tomorrow"
```

The **lease time** is how long the assignment holds. Default is usually 12-24 hours. The device renews automatically before the lease expires; if the device disappears (powered off, leaves the network), the lease expires and the address goes back into the pool.

A **DHCP reservation** is a router-side rule that says "the device with MAC address `xx:xx:xx:xx:xx:xx` always gets IP `192.168.1.51`". The device still uses DHCP to acquire the address (so the protocol flow is unchanged), but the answer is deterministic. This is the right way to give a server a stable address.

The "static IP" alternative is configuring the address on the device itself, bypassing DHCP entirely. Works, but has problems: phones and laptops move between networks (a static IP set for home doesn't work in a coffee shop), the router doesn't know the device claimed the address (so DHCP could assign it to someone else, causing a conflict), and the configuration lives in the wrong place (on each device instead of in one central admin UI).

**Reservation > static for almost every case.** The only place static IP wins is if the DHCP server itself is broken or unreachable.

### NAT

NAT (Network Address Translation) was originally a 1994 hack to let multiple devices share one IP address. It's now universal. There are several variants; the one your home router does is called **PAT** or **NAPT** (Port Address Translation), but everyone calls it NAT.

The mechanism, simplified:

```
1. Laptop opens connection to google.com:443
   Laptop sends packet:
     source: 192.168.1.37:54321  →  dest: 142.250.190.46:443
   
2. Router intercepts before sending out to ISP. Rewrites source:
     source: 49.205.18.7:62000   →  dest: 142.250.190.46:443
   Router records mapping in NAT table:
     [49.205.18.7:62000] ↔ [192.168.1.37:54321]
   
3. Google responds:
     source: 142.250.190.46:443  →  dest: 49.205.18.7:62000
   
4. Router looks up :62000 in NAT table, finds laptop.
   Rewrites destination back:
     source: 142.250.190.46:443  →  dest: 192.168.1.37:54321
   Delivers to laptop.
```

The router maintains a table mapping `(public IP, public port)` ↔ `(private IP, private port)`. Each new outbound connection adds an entry. Idle entries time out after a few minutes.

**Why incoming connections fail by default**: an unsolicited packet arriving at `49.205.18.7:443` doesn't match any NAT table entry. The router doesn't know which internal device wanted it, so it drops it. This is what makes NAT incidentally a security feature: random scanners and attackers can't reach inside without an explicit rule.

### Port forwarding (DNAT)

To make an internal service reachable from outside, you tell the router: "for this specific public port, *always* send the traffic to this internal device". This is a static NAT entry in the opposite direction (Destination NAT, or DNAT).

```
Rule:  external port 80  →  internal 192.168.1.51:8080  (TCP)

Incoming from internet:
  source: random_external_ip:54321  →  dest: 49.205.18.7:80
  
Router applies the rule, rewrites dest:
  source: random_external_ip:54321  →  dest: 192.168.1.51:8080
  
Phone receives, responds. Router NAT-translates the response source IP back to 49.205.18.7:80 on the way out.
```

The rule has four fields:

- **External port**: what the public internet sends to (often the well-known port for the service: 80 for HTTP, 443 for HTTPS)
- **Internal IP**: which device on the LAN should receive (must be a stable IP, hence the DHCP reservation)
- **Internal port**: where the service is actually listening (often a high port because of privileged-port restrictions; see [TCP/UDP and ports](tcp-udp-and-ports.md) when written)
- **Protocol**: TCP, UDP, or both

The mismatch between external and internal port is what fixes the "Termux can't bind port 80" problem from the [phone-as-homelab-capabilities](../../guides/phone-as-homelab-capabilities.md) guide. Outside the world sees port 80; inside, the service runs on 8080 where unprivileged users can bind it.

### Typical home network topology

```
 ISP cable / fibre
        │
        ▼
   ┌────────┐
   │ Modem  │   converts ISP signal (DOCSIS, GPON, etc.) to Ethernet
   └────┬───┘
        │ (ethernet)
        ▼
   ┌────────────┐
   │   Router   │   does: NAT, DHCP, Wi-Fi AP, firewall, port-forward, DNS forwarding
   │ (gateway)  │   has:  one public IP (WAN side), one LAN IP (typically 192.168.1.1)
   └─────┬──────┘
         │
         ├─── Wi-Fi  ────  laptop, phone, tablet
         ├─── Wi-Fi  ────  smart bulbs, speakers
         └─── Ethernet ──  desktop, NAS, TV
```

In most homes the modem and router are the same physical box (an "all-in-one" supplied by the ISP). Some power users separate them, putting their own router behind a bridged-mode modem - more flexibility, more configuration. Either way, the diagram above is the logical picture.

The router does *all* the interesting jobs: DHCP for the LAN, NAT for outbound, firewall for inbound, Wi-Fi access point, sometimes DNS caching. That's why the router admin UI has so many tabs - each one corresponds to one of these jobs.

## Common misconceptions

- **"My phone has a public IP."** Almost never. Your router has the public IP. Your phone has a private IP. Several websites confuse this by showing "your IP is 49.205.18.7" - they're showing your router's public IP, which all your devices share when going outbound. From the internet's perspective, your laptop and phone look identical.

- **"NAT is a security feature."** It's incidentally one, but that's not what it's for. NAT exists because IPv4 ran out of addresses. The "incoming connections are blocked" property is a side-effect that has security benefits, but real security is the *firewall*, which is a separate function (often built into the router). On IPv6 networks, where every device has its own public address, NAT mostly doesn't apply, and security comes purely from firewalling.

- **"Port forwarding is the same as opening a firewall port."** Related but distinct. Port forwarding is a NAT mapping (where to send incoming traffic). Firewall rules decide whether to allow traffic at all. Most home routers do both at once when you "forward a port", but conceptually they're separate. On a Linux server you'd do them separately too: `iptables` for NAT (DNAT rule), then a separate `iptables` rule allowing the traffic through the firewall.

- **"My public IP is forever."** For most residential ISPs, no. Public IPs are typically *dynamic*: your ISP can give you a different one when your connection re-establishes (router reboot, modem renegotiation, sometimes daily). To run a server reliably you need either a *static IP* (paid upgrade with most ISPs) or **Dynamic DNS** (a service that updates a hostname like `myhome.duckdns.org` to point to whatever your current public IP is). Many home routers have DDNS clients built in.

- **"DHCP reservation and static IP are the same thing."** Both give a device a stable IP, but the configuration lives in different places. **Reservation** is on the router, in the DHCP table. **Static IP** is on the device itself, bypassing DHCP. Reservation wins because: device is portable (works on other networks too), router knows the IP is taken (no conflicts), one central place to see all your reservations.

- **"NAT works the same in both directions."** It does not. Outbound NAT (PAT) is automatic and stateful - the router builds a mapping when the connection starts, tears it down when idle. Inbound NAT (port forwarding / DNAT) requires an explicit static rule because the router has no way to guess which internal device should receive an unsolicited packet.

- **"If I'm on the same Wi-Fi as the server, I can always reach it via the public IP."** This is **loopback NAT** (also called NAT hairpinning), and not all home routers support it. If yours doesn't, accessing your home server's public IP from inside the LAN fails, while accessing it via private IP works. Annoying for testing port-forwards from inside the same network. Solution: test from a phone on cellular data, or use the private IP for inside-LAN access.

## When it matters in practice

Concrete situations where understanding these saves debugging time:

- **"My port forward isn't working."** Three things to check, in order: (1) is the internal IP still correct? DHCP may have given the device a different IP if you didn't reserve. (2) is the service actually listening on the internal port? `ssh phone -p 8022 'curl -v localhost:8080'` from elsewhere on the LAN tells you. (3) is the ISP blocking that public port? Indian and many residential ISPs block port 25 (SMTP) and sometimes 80/443. Test by using a non-standard port temporarily.

- **"My phone can't reach my server when I'm on cellular."** Cellular networks usually NAT you too, sometimes through **CGNAT** (carrier-grade NAT) where many subscribers share one public IP. The connection out to your home router should still work - the issue is more often DDNS not updating, your home public IP changing, or the ISP blocking the port. Diagnostic: `nslookup yourhome.duckdns.org` from cellular - does it return your current home public IP?

- **"Two devices keep getting the same IP and conflicting."** DHCP misconfigured, or someone set a static IP inside the DHCP pool range. Either expand the pool to avoid the static, or move the static device outside the pool, or replace the static with a reservation.

- **"I want to access service X from inside AND outside my LAN."** The cleanest answer is *not* to mess with loopback NAT - it's [Tailscale or similar mesh VPN](../../guides/phone-as-homelab-capabilities.md). Devices on the tailnet reach each other by name regardless of where they physically are. NAT hairpinning becomes irrelevant; cellular vs Wi-Fi becomes irrelevant; public IP changes become irrelevant.

- **"My server is reachable from outside but kicks me out after a few minutes."** NAT translation entries on the router time out for idle connections. SSH session that idles long enough loses its NAT entry; the next packet doesn't match anything in the table. Fix: keep-alive (in `~/.ssh/config`, set `ServerAliveInterval 60`) so the connection sends a tiny packet every minute and stays in the NAT table.

## How home networking differs from corporate or cloud

Recognising the differences helps you read tutorials that assume different contexts:

| Aspect | Home network | Corporate network | Cloud (AWS / GCP / Azure) |
|---|---|---|---|
| Address allocation | Router DHCP, single LAN | Multiple VLANs, IPAM tooling | VPC subnets, you design them |
| NAT | One public IP, PAT | Often per-subnet rules, sometimes 1:1 NAT | Outbound via NAT Gateway, inbound via load balancer / EIPs |
| Firewall | Router built-in, simple | Dedicated firewall appliance, complex zoned policy | Security groups (instance-level) + NACLs (subnet-level) |
| Inbound services | Port forwarding | Reverse proxy in DMZ | Public load balancer or specific public-subnet hosts |
| Device discovery | Manual, MAC-based reservations | Active Directory, DHCP servers with naming | DNS records, service discovery |
| IPv6 usage | Often disabled or invisible | Sometimes enabled for internal | Common for cloud-internal traffic |

The mechanics are the same protocols (DHCP, NAT, IP routing), but the interfaces and the sophistication scale up dramatically. Cloud especially is where home-lab muscle memory pays off: AWS VPCs, security groups, NAT gateways, route tables - they're all the same five concepts you just learned, with a different UI.

## Configuration in common stacks

For reference - how these concepts manifest in tools you'll touch:

| Tool / context | Where these concepts appear |
|---|---|
| Home router admin (web UI) | "LAN/DHCP" tab (DHCP pool + reservations), "NAT/Port Forwarding" tab (DNAT rules), "WAN" tab (public IP info) |
| Linux server | `ip addr` (interface IPs), `ip route` (routing table), `iptables -t nat` (NAT rules), `dhclient` (DHCP client) |
| Docker | Default bridge network does NAT between containers and host; `docker run -p 80:8080` is essentially port forwarding |
| Kubernetes | `Service` resources are basically port-forward / load-balance abstractions; `ClusterIP`, `NodePort`, `LoadBalancer` are different routing modes |
| AWS / cloud | VPC = your LAN equivalent, security groups = firewall rules, NAT gateway = NAT, Elastic IP = static public IP, Route 53 = DNS |
| OpenWRT / pfSense | Power-user router OSes that expose all of the above as first-class config files instead of vendor-locked web UIs |

## Further reading

Authoritative sources, ordered roughly by depth:

- **RFC 1918** - "Address Allocation for Private Internets". The 5-page spec that defines the private address ranges. Short, readable. https://datatracker.ietf.org/doc/html/rfc1918
- **RFC 5735** - "Special Use IPv4 Addresses". Comprehensive list of all reserved IPv4 ranges (loopback, multicast, link-local, etc.). Useful when you encounter `169.254.x.x` or `224.x.x.x` and wonder where they fit.
- **RFC 2131** - "Dynamic Host Configuration Protocol". The DHCP spec. Longer, but the first 10 pages give you the protocol flow clearly.
- **Linux Kernel Documentation: networking** - https://www.kernel.org/doc/Documentation/networking/. The authoritative reference for how Linux handles all of this.
- **Kurose & Ross, "Computer Networking: A Top-Down Approach"** - the standard university textbook. Chapter 4 covers the network layer including NAT and addressing comprehensively. Worth borrowing or buying if you want one cohesive reference.
- **Cisco "How NAT Works"** - vendor docs but well-written and language-agnostic. https://www.cisco.com/c/en/us/support/docs/ip/network-address-translation-nat/26704-nat-faq-00.html
