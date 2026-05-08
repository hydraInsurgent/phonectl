# Learnings

Project-independent concepts captured as standalone files. Things that came up while building PhoneCTL but apply to any future project.

These are different from `guides/`:

- **Guides** explain *how something was done in this project* and *why those specific choices*.
- **Learnings** explain *what a concept is* and *how it works in general*, independent of the project.

A guide may reference a learning rather than inlining 100 lines of theory.

## Frontmatter schema

Every learning starts with YAML frontmatter:

```yaml
---
title: '<Human title; single-quoted to allow backticks and colons>'
category: <single bucket: networking | android | bash | testing | packaging | ...>
tags: [<keywords, lowercase, hyphenated>]
related:
  - <relative path to a sibling learning or to a guide>
first_encountered: <project context, e.g. "PhoneCTL v0.1">
created: YYYY-MM-DD
updated: YYYY-MM-DD
---
```

- `category` is one bucket per file, used for top-level grouping in this index.
- `tags` are many keywords for cross-cutting search (`grep -l 'tags:.*android' *.md` style).
- `related` lists explicit cross-links - other learnings, or guides that touch the concept.
- `created` / `updated` so a stale entry can be detected at a glance.

The H1 inside the file is allowed to repeat the title - it's used by markdown renderers that don't read frontmatter. The previous "Last updated:" backtick line is now redundant and has been removed.

## Index by category

### Networking

| Concept | First encountered in | Summary |
|---|---|---|
| [home-networking-fundamentals](home-networking-fundamentals.md) | Phone-as-homelab work | The IP / DHCP / NAT / port-forwarding chain that any homelabber needs solid intuition on. |
| [wifi-association-vs-dhcp-lease](wifi-association-vs-dhcp-lease.md) | Phone-as-homelab debugging (2026-05-08) | Why a "connected" device can be unreachable: WiFi association vs DHCP lease, ARP `<incomplete>`, MAC randomization, WiFi PSM, Android power domains. |

### Android

| Concept | First encountered in | Summary |
|---|---|---|
| [adb-shell-line-endings](adb-shell-line-endings.md) | PhoneCTL v0.1 | Why `adb shell` output has `\r\n` line terminators and the parser implications. |
| [termux-and-proot-on-android](termux-and-proot-on-android.md) | PhoneCTL v0.1 | Linux userland on Android without root: how Termux and proot do it, and where they stop. |

### Bash

| Concept | First encountered in | Summary |
|---|---|---|
| [bash-strict-mode-pipefail-and-read](bash-strict-mode-pipefail-and-read.md) | PhoneCTL v0.1 wizard piped-input bug | `set -euo pipefail` semantics and the carve-outs that bite robust bash CLIs. |

### Testing

| Concept | First encountered in | Summary |
|---|---|---|
| [bats-core-test-conventions](bats-core-test-conventions.md) | PhoneCTL v0.1 | The bats bash test framework: per-test process model, `run` / `load` / `setup`, fixture and stub patterns. |

### Packaging

| Concept | First encountered in | Summary |
|---|---|---|
| [npm-bin-and-npm-link](npm-bin-and-npm-link.md) | PhoneCTL v0.1 | How `package.json`'s `bin` field plus `npm link` puts a script on global `$PATH`. |
