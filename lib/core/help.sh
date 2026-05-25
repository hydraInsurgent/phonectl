# lib/core/help.sh - the user-facing help text.
#
# Kept in core so verbs added across multiple lib/commands/*.sh files
# can all be reflected here from one place. v0.2 splits the verbs by
# transport: connect / pair are ADB-purpose, everything else is SSH.

help_text() {
    cat <<'EOF'
phonectl - manage an Android phone as a headless home server

USAGE
  phonectl <verb> [args...]

CONNECTION (SSH)
  ssh [cmd...]              SSH into Termux on the configured phone, or
                            run a one-shot remote command
  status                    One-panel device status via SSH (battery,
                            storage, uptime, WiFi). Requires `termux-api`
                            installed on the phone.

FILE TRANSFER (SCP)
  pull <remote> <local>     Copy a file from the phone to this machine
  push <local> <remote>     Copy a file from this machine to the phone

ADB
  pair                      First-time Android 11+ wireless-debugging
                            pair wizard. Writes the connect port to
                            ~/.config/phonectl/config.
  connect [<port>]          Connect ADB. Tries USB first, then wireless
                            at the saved adb_port. With <port>, updates
                            adb_port first (post-reboot recovery: trust
                            is still good, only the port changed).

CONFIG
  init                      First-run wizard: pure manual prompts (no
                            ADB or USB required)
  config                    Show current config (key=value lines)
  config <key>              Print one config value
  config <key> <value>      Set a config value
                            (host, host_alt, ssh_port, adb_port,
                            backup_dir, proot_distro)

META
  help                      Show this message
  version                   Print version

CONFIG FILE
  ~/.config/phonectl/config (key=value, one per line, chmod 600)

ENV OVERRIDES (per-call, win over the config file)
  PHONECTL_HOST       PHONECTL_HOST_ALT
  PHONECTL_SSH_PORT   PHONECTL_ADB_PORT
  PHONECTL_BACKUP_DIR PHONECTL_PROOT_DISTRO

DOCS
  https://github.com/hydraInsurgent/phonectl
EOF
}
