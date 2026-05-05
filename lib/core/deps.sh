# lib/core/deps.sh - external-binary dependency checking.
#
# Every command that shells out to adb / ssh / scrcpy must call
# `require_deps <names...>` before doing so. On a missing tool we exit
# non-zero with a clear message that includes a distro-aware install hint.
#
# `_pctl_distro_id` is testable: set PCTL_OS_RELEASE_PATH to a fake file
# (e.g. one written into the per-test tmp dir) and the helper reads from
# there instead of /etc/os-release.

# Returns the OS distribution ID: ubuntu, debian, pop, fedora, arch, darwin, ...
# Falls back to "unknown" when nothing matches.
_pctl_distro_id() {
    local os_release="${PCTL_OS_RELEASE_PATH:-/etc/os-release}"
    if [[ -r "${os_release}" ]]; then
        # Sourcing in a subshell so the caller's environment is untouched.
        # shellcheck disable=SC1090
        ( . "${os_release}" && printf '%s\n' "${ID:-unknown}" )
    elif [[ "$(uname 2>/dev/null)" = "Darwin" ]]; then
        printf 'darwin\n'
    else
        printf 'unknown\n'
    fi
}

# Returns the install command for the host distro for one or more package names.
# Caller passes the names as a single space-separated string.
_pctl_install_hint() {
    local names="$1"
    case "$(_pctl_distro_id)" in
        ubuntu|debian|pop|linuxmint|elementary)
            printf 'sudo apt install %s' "${names}" ;;
        fedora|rhel|centos|rocky|almalinux)
            printf 'sudo dnf install %s' "${names}" ;;
        arch|manjaro|endeavouros)
            printf 'sudo pacman -S %s' "${names}" ;;
        darwin)
            printf 'brew install %s' "${names}" ;;
        *)
            printf 'install %s with your package manager' "${names}" ;;
    esac
}

# Verify each named binary is on PATH. On missing, print the names and a
# distro-aware install hint, return non-zero.
require_deps() {
    local missing=()
    local cmd
    for cmd in "$@"; do
        if ! command -v "${cmd}" >/dev/null 2>&1; then
            missing+=("${cmd}")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        error "missing required tool(s): ${missing[*]}"
        info "  hint: $(_pctl_install_hint "${missing[*]}")"
        return 1
    fi
    return 0
}
