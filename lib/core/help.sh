# lib/core/help.sh - the user-facing help text.
#
# Kept in core so future verbs added across multiple lib/commands/*.sh
# files can all be reflected here from one place. The formatting is
# intentionally plain (no colors); the dispatcher pipes through
# `output.sh` only when something is dynamic.

help_text() {
    cat <<'EOF'
phonectl - manage an Android phone as a headless home server

USAGE
  phonectl <verb> [args...]

CONNECTION
  ssh                       SSH into Termux on the configured phone
  connect                   Wireless ADB connect (with host_alt fallback)
  status                    One-panel device status (model, battery, IP, ...)

FILE TRANSFER
  pull <remote> <local>     Copy a file from the phone to this machine
  push <local> <remote>     Copy a file from this machine to the phone

CONFIG
  init                      First-run wizard: detect device + write config
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
