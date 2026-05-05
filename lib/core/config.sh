# lib/core/config.sh - load, read, and write ~/.config/phonectl/config.
#
# The config file is plain `key=value` text, one entry per line, with `#`
# comments and blank lines allowed. It is **parsed line-by-line, never
# sourced** - eliminating the command-injection vector that `source ~/.config/...`
# would otherwise create if the file got hand-edited or corrupted.
#
# Every value can also be overridden per-call via PHONECTL_<KEY> env vars.

# ---- defaults ----------------------------------------------------------------

PCTL_DEFAULT_SSH_PORT=8022
PCTL_DEFAULT_ADB_PORT=5555
PCTL_DEFAULT_BACKUP_DIR="${HOME}/phone-backup"
PCTL_DEFAULT_PROOT_DISTRO=ubuntu

# Set by config_load. Treat as read-only after loading.
PCTL_HOST=
PCTL_HOST_ALT=
PCTL_SSH_PORT=
PCTL_ADB_PORT=
PCTL_BACKUP_DIR=
PCTL_PROOT_DISTRO=

# Recognized keys. Anything else is rejected by config_set / get and
# silently ignored when reading the file (to keep forward-compat painless).
_pctl_known_keys=(host host_alt ssh_port adb_port backup_dir proot_distro)

# ---- helpers -----------------------------------------------------------------

config_path() {
    printf '%s/phonectl/config\n' "${XDG_CONFIG_HOME:-${HOME}/.config}"
}

# True if $1 is in _pctl_known_keys.
_pctl_is_known_key() {
    local k
    for k in "${_pctl_known_keys[@]}"; do
        [[ "${k}" = "$1" ]] && return 0
    done
    return 1
}

# Trim leading and trailing whitespace from $1 (echoed result).
_pctl_trim() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

# ---- load --------------------------------------------------------------------

# Populate PCTL_* globals from defaults, then file, then env-var overrides.
# Idempotent: safe to call multiple times.
config_load() {
    local path
    path="$(config_path)"

    PCTL_HOST=
    PCTL_HOST_ALT=
    PCTL_SSH_PORT="${PCTL_DEFAULT_SSH_PORT}"
    PCTL_ADB_PORT="${PCTL_DEFAULT_ADB_PORT}"
    PCTL_BACKUP_DIR="${PCTL_DEFAULT_BACKUP_DIR}"
    PCTL_PROOT_DISTRO="${PCTL_DEFAULT_PROOT_DISTRO}"

    if [[ -r "${path}" ]]; then
        local line key value
        while IFS= read -r line || [[ -n "${line}" ]]; do
            # Skip blanks and comments.
            local trimmed
            trimmed="$(_pctl_trim "${line}")"
            [[ -z "${trimmed}" || "${trimmed}" = \#* ]] && continue

            # Split on first '='. No '=' = malformed, ignore.
            [[ "${trimmed}" != *=* ]] && continue
            key="$(_pctl_trim "${trimmed%%=*}")"
            value="$(_pctl_trim "${trimmed#*=}")"

            case "${key}" in
                host)         PCTL_HOST="${value}" ;;
                host_alt)     PCTL_HOST_ALT="${value}" ;;
                ssh_port)     PCTL_SSH_PORT="${value}" ;;
                adb_port)     PCTL_ADB_PORT="${value}" ;;
                backup_dir)   PCTL_BACKUP_DIR="${value}" ;;
                proot_distro) PCTL_PROOT_DISTRO="${value}" ;;
                *) ;; # silently ignore unknown keys
            esac
        done < "${path}"
    fi

    # Env-var overrides win over file values.
    PCTL_HOST="${PHONECTL_HOST:-${PCTL_HOST}}"
    PCTL_HOST_ALT="${PHONECTL_HOST_ALT:-${PCTL_HOST_ALT}}"
    PCTL_SSH_PORT="${PHONECTL_SSH_PORT:-${PCTL_SSH_PORT}}"
    PCTL_ADB_PORT="${PHONECTL_ADB_PORT:-${PCTL_ADB_PORT}}"
    PCTL_BACKUP_DIR="${PHONECTL_BACKUP_DIR:-${PCTL_BACKUP_DIR}}"
    PCTL_PROOT_DISTRO="${PHONECTL_PROOT_DISTRO:-${PCTL_PROOT_DISTRO}}"
}

# ---- get / set / print -------------------------------------------------------

# Print one config value to stdout (after config_load has been called).
config_get() {
    local key="$1"
    case "${key}" in
        host)         printf '%s\n' "${PCTL_HOST}" ;;
        host_alt)     printf '%s\n' "${PCTL_HOST_ALT}" ;;
        ssh_port)     printf '%s\n' "${PCTL_SSH_PORT}" ;;
        adb_port)     printf '%s\n' "${PCTL_ADB_PORT}" ;;
        backup_dir)   printf '%s\n' "${PCTL_BACKUP_DIR}" ;;
        proot_distro) printf '%s\n' "${PCTL_PROOT_DISTRO}" ;;
        *) error "unknown config key: ${key}"; return 1 ;;
    esac
}

# Write or replace a single key in the on-disk config file.
# Other keys are preserved. The file is created with chmod 600 and an
# atomic mktemp+mv so a partial write cannot corrupt the file.
config_set() {
    local key="$1" value="$2"
    if ! _pctl_is_known_key "${key}"; then
        error "unknown config key: ${key}"
        return 1
    fi

    # Expand leading ~/ to $HOME so callers can pass shell-style paths.
    case "${value}" in
        '~/'*) value="${HOME}/${value:2}" ;;
        '~') value="${HOME}" ;;
    esac

    local path
    path="$(config_path)"
    mkdir -p "$(dirname "${path}")"

    local tmp
    tmp="$(mktemp "${path}.XXXXXX")"
    local found=0
    if [[ -r "${path}" ]]; then
        local line k
        while IFS= read -r line || [[ -n "${line}" ]]; do
            k="$(_pctl_trim "${line%%=*}")"
            if [[ "${k}" = "${key}" ]]; then
                printf '%s=%s\n' "${key}" "${value}" >> "${tmp}"
                found=1
            else
                printf '%s\n' "${line}" >> "${tmp}"
            fi
        done < "${path}"
    fi
    if [[ "${found}" -eq 0 ]]; then
        printf '%s=%s\n' "${key}" "${value}" >> "${tmp}"
    fi

    mv -f "${tmp}" "${path}"
    chmod 600 "${path}"
}

# Pretty-print the loaded config in `key=value` form (the same shape as
# the on-disk file).
config_print() {
    printf 'host=%s\n' "${PCTL_HOST}"
    printf 'host_alt=%s\n' "${PCTL_HOST_ALT}"
    printf 'ssh_port=%s\n' "${PCTL_SSH_PORT}"
    printf 'adb_port=%s\n' "${PCTL_ADB_PORT}"
    printf 'backup_dir=%s\n' "${PCTL_BACKUP_DIR}"
    printf 'proot_distro=%s\n' "${PCTL_PROOT_DISTRO}"
}

# Hard requirement check: a phone host must be configured before any
# command that talks to the device.
config_require_host() {
    if [[ -z "${PCTL_HOST:-}" ]]; then
        error "no host configured. Run \`phonectl init\` to set up your phone, or set PHONECTL_HOST."
        return 1
    fi
    return 0
}
