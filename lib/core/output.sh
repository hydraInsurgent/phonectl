# lib/core/output.sh - colored, structured output helpers.
#
# Sourced (not executed) by bin/phonectl and lib/commands/*.sh. Every
# user-facing print should go through one of these so the CLI's voice stays
# consistent and respects NO_COLOR / non-TTY environments.

# ANSI codes. Cleared below when colors should be disabled.
PCTL_RED='\033[0;31m'
PCTL_GREEN='\033[0;32m'
PCTL_YELLOW='\033[1;33m'
PCTL_BLUE='\033[0;34m'
PCTL_CYAN='\033[0;36m'
PCTL_BOLD='\033[1m'
PCTL_NC='\033[0m'

# Disable colors when NO_COLOR is set or when stdout is not a terminal
# (e.g. piped into another command, captured by tests).
if [[ -n "${NO_COLOR:-}" ]] || ! [[ -t 1 ]]; then
    PCTL_RED='' PCTL_GREEN='' PCTL_YELLOW='' PCTL_BLUE='' PCTL_CYAN='' PCTL_BOLD='' PCTL_NC=''
fi

info()    { printf '%b%s%b\n' "${PCTL_BLUE}"  "$*" "${PCTL_NC}"; }
success() { printf '%b%s%b\n' "${PCTL_GREEN}" "$*" "${PCTL_NC}"; }
warn()    { printf '%b%s%b\n' "${PCTL_YELLOW}" "$*" "${PCTL_NC}"; }

# Errors are the only thing that goes to stderr. Always prefixed with
# `error:` so scripts and test harnesses can grep for it reliably.
error()   { printf '%berror:%b %s\n' "${PCTL_RED}" "${PCTL_NC}" "$*" >&2; }

# Section header used by `phonectl status` (and any future multi-section view).
header()  { printf '%b%s%b\n' "${PCTL_BOLD}${PCTL_CYAN}" "── $* ──" "${PCTL_NC}"; }

# Aligned key:value line for status panels.
kv()      { printf '  %-13s %b%s%b\n' "$1:" "${PCTL_BOLD}" "$2" "${PCTL_NC}"; }
