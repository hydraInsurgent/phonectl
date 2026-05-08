---
title: 'Termux and proot: Linux Userland on Android Without Root'
category: android
tags: [termux, proot, android, sandboxing, userland, no-root, app-environment]
related:
  - adb-shell-line-endings.md
  - wifi-association-vs-dhcp-lease.md
first_encountered: PhoneCTL v0.1 / phone-as-homelab work
created: 2026-05-07
updated: 2026-05-08
---

# Termux and proot: Linux Userland on Android Without Root

Termux gives you bash, ssh, openssh-server, a package manager, and ~1000 packages on a stock unrooted Android phone. `proot-distro` adds a full Ubuntu rootfs on top. Both work entirely within Android's app sandbox - no root, no kernel modules, no firmware unlock. Understanding *why* the stack works (and where its boundaries are) is the difference between productive use and chasing impossible workarounds.

## Mental model

Two different mechanisms stacked:

```
+--------------------------------------------------------------+
| proot-distro Ubuntu (apt, dpkg, full Linux userland feel)    |
| + proot rewrites filesystem syscalls so / looks like Ubuntu  |
+--------------------------------------------------------------+
| Termux app (bash, sshd, package manager, /data/data/...)    |
| + linker hacks so binaries find their libs, not Bionic libc |
+--------------------------------------------------------------+
| Android app sandbox (uid u0_aXXX, no privileged operations) |
| + Android's Linux kernel underneath - normal kernel,         |
|   abnormal userland conventions on top                       |
+--------------------------------------------------------------+
```

Termux is the bottom layer: it rebuilds Linux userland binaries (bash, openssh, python, etc.) targeted at Android's bionic-libc and packages them as a normal Android app. proot is the top layer: it intercepts a Termux process's filesystem syscalls and rewrites them so the process believes its root filesystem is the one Termux extracted from a Ubuntu rootfs tarball.

Neither needs root. Termux works because Android allows apps to run arbitrary executables in their private storage. proot works because it uses `ptrace`, which is allowed for tracing your own processes.

## Why this exists

Android's userland is not the GNU Linux userland. The C library is **bionic** (a smaller, BSD-derived libc), not glibc. `/bin`, `/usr`, `/etc` largely don't exist. The shell is a stripped Toybox `sh`, not bash. Most prebuilt Linux software won't run as-is.

Termux fixes layer 1: rebuild common Linux software against bionic, package it for Android, store it under the app's data directory. The result is a meaningful userland but with non-standard paths (`$PREFIX = /data/data/com.termux/files/usr` instead of `/usr`).

proot fixes layer 2: for software that won't compile against bionic or that hardcodes Linux FHS paths, run it under a "real" Linux rootfs. Since you can't `chroot` without root, proot uses `ptrace` to intercept and rewrite the syscalls instead. The traced process believes it's at `/`; proot is silently translating to a Termux-relative directory.

Both approaches were originally designed for high-performance computing clusters (where users couldn't get root but needed reproducible environments). Android happened to be a good fit for the same reasons.

## How it actually works

### Termux internals

Each Android app gets:

- A unique Linux uid in the range `u0_a0` to `u0_a9999`
- A private writable directory at `/data/data/<package-name>/`
- Standard app permissions: network, storage (with consent), no kernel-level access

Termux uses its private directory as `$PREFIX`:

```
/data/data/com.termux/files/
├── home/                    # user home, ~ inside Termux
└── usr/                     # PREFIX
    ├── bin/                 # bash, sshd, vim, ...
    ├── etc/
    ├── lib/                 # bionic-linked .so files
    ├── share/
    └── ...
```

`pkg install foo` is a thin wrapper around `apt install` (Termux uses Debian-derived tooling), but the package manager points at Termux's own repository at `https://packages.termux.dev/`. Packages there are recompiled-for-bionic versions of upstream Debian packages. Most things "just work"; some have to be skipped (anything that hardcodes `/usr/bin/foo` paths in scripts).

### proot

`proot-distro install ubuntu` does:

1. Download an Ubuntu rootfs tarball (from official Ubuntu Cloud Images, prebuilt for `arm64`/`armhf`)
2. Extract to `$PREFIX/var/lib/proot-distro/installed-rootfs/ubuntu/`
3. Set up a wrapper that launches `proot` with the right flags

`proot-distro login ubuntu` invokes:

```
proot \
  -r <ubuntu-rootfs-path> \
  -b /sys -b /proc -b /dev \
  -w /root \
  /usr/bin/env -i HOME=/root TERM=$TERM PATH=/usr/local/sbin:... \
  /bin/sh
```

`proot` then forks-and-execs the shell, attaching itself as a `ptrace` parent. Every syscall the child makes that takes a path argument (`open`, `stat`, `chdir`, `execve`, ...) gets intercepted: proot rewrites the path from "Ubuntu's view" (e.g. `/etc/passwd`) to "Android's view" (`<rootfs-path>/etc/passwd`) before letting the real syscall through. The child sees Ubuntu paths everywhere; the kernel sees Termux-private paths.

### What both layers can't do

Both Termux and proot run at the **app uid level**. Things they can't do:

- Bind privileged TCP ports (< 1024)
- Load kernel modules
- Use `iptables`/`nftables` (no kernel-side capability)
- Mount additional filesystems (NFS, SMB, FUSE - except via system services)
- Open raw sockets (no ICMP `ping`, no packet capture)
- Run a full container runtime (cgroups + namespaces require kernel support that Android disables for non-system apps)

Some of these have approximate workarounds (`tsu` to escalate inside a rooted Termux, Tailscale-userspace for VPN-like networking, `tcpip` for an unprivileged ping replacement). Most of the time the right move is "design around the constraint" rather than fight it.

## Common misconceptions

- **"Termux gives you root."** No. Termux is just an app like any other. The `pkg install root-repo` exists for *rooted* devices to add packages that need root; on stock devices it does nothing useful.
- **"proot is a virtual machine."** No. There is no VM. The kernel is the same Android kernel; the CPU runs the same instructions. proot only translates filesystem-related syscalls. Performance overhead is real but small for I/O-light workloads (~5-15%) and large for I/O-heavy ones.
- **"Anything that runs in Ubuntu runs in proot Ubuntu."** Most things do. Exceptions: kernel-module-loading software (out, no kernel access), software that needs `/proc/sys/...` write access for sysctls, software that uses `keyring`-style kernel APIs, and anything that relies on `setuid` binaries (proot can't elevate).
- **"Termux:Boot autostart works for any app."** Only for Termux scripts. Other apps have their own boot mechanisms. Termux:Boot specifically runs scripts in `~/.termux/boot/` after device boot, with the Termux runtime.
- **"Battery-optimization whitelisting prevents all app kills."** It greatly reduces them but is not absolute. Aggressive OEM kernels (OPLUS, MIUI, OneUI to a lesser degree) can still kill background apps under memory pressure. The wake-lock acquired by `termux-wake-lock` keeps the CPU from sleeping but doesn't prevent OOM kills.
- **"Termux's sshd listens on port 22."** It listens on **8022** by default. Android reserves ports below 1024 for the system; non-system uids cannot bind them.
- **"proot-distro install ubuntu gives me a real `apt` mirror configuration."** It gives a working but minimal one. You may want to `sed -i` a closer mirror or enable `universe`/`multiverse` repos depending on what you're installing.

## When it matters in practice

- **Choosing where to run a service.** A Node.js HTTP API on port 8080: works fine in Termux (no rootfs needed). A .NET 8 server: better in proot Ubuntu (Termux's .NET packaging lags). nginx on port 80: doesn't work directly (privileged port); router-side port-forward 80→8080 fixes it. Docker: doesn't work at all without root and kernel features.
- **Diagnosing "permission denied" inside Termux.** Most often the error is from Android's app sandbox, not Termux. Reaching for `chmod +x` won't help if the actual issue is the kernel refusing the syscall. Workaround: stop trying to do that thing on Android.
- **Persisting state across phone reboots.** Termux's `~/` (= `/data/data/com.termux/files/home`) survives. Some `/sdcard/` paths survive but with different uid/gid semantics. Termux:Boot script lives at `~/.termux/boot/start-server.sh` and re-runs on every reboot, which is how PhoneCTL's setup keeps sshd alive.
- **Sharing files between Android apps and Termux.** `/sdcard/` is the bridge. Termux can read/write it (with storage permission granted via `termux-setup-storage`). Other apps see the same files through the standard Android file picker.

## Configuration in common stacks

| Need | Termux native | proot Ubuntu |
|---|---|---|
| **bash, ssh, git** | `pkg install` | `apt install` (after `apt update`) |
| **Python + pip wheels** | `pkg install python python-pip` (some C-extension wheels missing for bionic) | `apt install python3 python3-pip` (full PyPI compatibility) |
| **.NET / C#** | Limited; older versions only | `apt install dotnet-sdk-8.0` works cleanly |
| **Node.js** | `pkg install nodejs-lts` | `apt install nodejs npm` |
| **Docker** | Not available | Not available |
| **systemd services** | Not available; use `~/.termux/boot/start-server.sh` | Not available; proot can't init systemd |
| **iptables / nftables** | Not available | Not available |
| **Compile from source (gcc, make)** | `pkg install build-essential` | `apt install build-essential` |

For PhoneCTL specifically: the test phone runs Termux + sshd at the bottom layer (auto-started via Termux:Boot), with a proot Ubuntu installed but only entered when a workload needs the apt ecosystem. PhoneCTL's `proot` verb (v0.2) drops you straight in.

## Further reading

- **Termux Wiki** - https://wiki.termux.com/wiki/Main_Page. The "Differences from Linux" page is essential reading.
- **proot project** - https://proot-me.github.io/. Original docs and the technical paper from the HPC research that produced it.
- **Android app sandbox docs** - https://source.android.com/docs/security/app-sandbox. Authoritative reference for what apps can and cannot do.
- **proot-distro** - https://github.com/termux/proot-distro. Source of the Ubuntu / Debian / Alpine / Arch installers.
- **bionic vs glibc** - https://android.googlesource.com/platform/bionic/+/master/docs/status.md. Lists exactly which functions bionic implements differently or omits, useful when porting Linux software.
- **Android's `/proc` filesystem** - same kernel, same `/proc`, but app-uid restrictions apply. `man 5 proc` for the canonical reference; what's *readable by an app* is the practical filter.
