#!/bin/bash
################################################################################
## Envoy Shared Foundation Library — envoy_common.sh
##
## Provides logging, color, version, temp-file, and config helpers shared
## across all Envoy tools.  Sourcing this file is OPTIONAL — every tool can
## still run standalone without it.
##
## Requires bash 4.0+.
##
## Usage:
##   source "$(dirname "$0")/../lib/envoy_common.sh"
##
################################################################################

# Guard against double-sourcing
[[ -n "${_ENVOY_COMMON_LOADED:-}" ]] && return 0
_ENVOY_COMMON_LOADED=1

################################################################################
## Logging
##
## Four severity levels.  INFO and DEBUG are gated by ENVOY_VERBOSE and
## ENVOY_DEBUG respectively.  All output goes to stderr so it never
## contaminates piped data.
################################################################################

_log_error() {
    printf '%s\n' "ERROR: $*" >&2
    [[ "${ENVOY_LOG_CENTRAL:-0}" == "1" ]] && _log_to_central "ERROR" "$*"
}
_log_warn() {
    printf '%s\n' "WARNING: $*" >&2
    [[ "${ENVOY_LOG_CENTRAL:-0}" == "1" ]] && _log_to_central "WARN" "$*"
}
_log_info()  { [[ "${ENVOY_VERBOSE:-0}" == "1" ]] && printf '%s\n' "INFO: $*" >&2; }
_log_debug() { [[ "${ENVOY_DEBUG:-0}" == "1" ]] && printf '%s\n' "DEBUG: $*" >&2; }

################################################################################
## Centralized Logging
##
## _log_to_central writes log entries to ~/.envoy/logs/<toolname>.log when
## ENVOY_LOG_CENTRAL=1 is set.  Auto-rotates when log exceeds 1MB (keeps
## max 10 rotated files).
##
## @param  $1  string  Log level (ERROR, WARN, INFO, DEBUG)
## @param  $2  string  Log message
## @return void
################################################################################

_log_to_central() {
    local level="$1"
    local msg="$2"
    local log_dir="$HOME/.envoy/logs"
    local toolname
    toolname="$(basename "${0:-envoy}")"
    local logfile="${log_dir}/${toolname}.log"

    # Create log directory if needed
    [[ -d "$log_dir" ]] || mkdir -p "$log_dir" 2>/dev/null || return 0

    # Auto-rotate if log file exceeds 1MB (1048576 bytes)
    if [[ -f "$logfile" ]]; then
        local filesize
        filesize=$(wc -c < "$logfile" 2>/dev/null || echo 0)
        if [[ "$filesize" -gt 1048576 ]]; then
            # Rotate: shift .log.9 -> .log.10 ... .log.1 -> .log.2, .log -> .log.1
            local i=9
            while [[ $i -ge 1 ]]; do
                local next=$((i + 1))
                [[ -f "${logfile}.${i}" ]] && mv -f "${logfile}.${i}" "${logfile}.${next}" 2>/dev/null
                i=$((i - 1))
            done
            mv -f "$logfile" "${logfile}.1" 2>/dev/null
            # Remove excess rotated files (keep max 10)
            [[ -f "${logfile}.11" ]] && rm -f "${logfile}.11" 2>/dev/null
        fi
    fi

    # Write log entry
    printf '[%s] %s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$msg" >> "$logfile" 2>/dev/null
}

################################################################################
## Trace
##
## _trace emits detailed diagnostic output when ENVOY_TRACE=1 is set.
## Output goes to stderr with timestamps so it never contaminates piped data.
## Use this at key points: command dispatch, tool resolution, config loading.
################################################################################

_trace() {
    [[ "${ENVOY_TRACE:-0}" == "1" ]] || return 0
    printf '[TRACE %s] %s\n' "$(date +%H:%M:%S.%3N)" "$*" >&2
}

################################################################################
## Color
##
## _envoy_init_color sets the C_* variables used for terminal coloring.
## Respects:
##   - NO_COLOR        (https://no-color.org/)
##   - ENVOY_NO_COLOR  (project-specific override)
##   - Non-TTY stdout  (piped or redirected output)
##
## Call once near the top of your script after sourcing this file.
################################################################################

_envoy_init_color() {
    # Disable color when requested or when stdout is not a terminal
    if [[ -n "${NO_COLOR:-}" ]] || [[ -n "${ENVOY_NO_COLOR:-}" ]] || [[ ! -t 1 ]]; then
        C_RED=''
        C_GREEN=''
        C_YELLOW=''
        C_BLUE=''
        C_DIM=''
        C_BOLD=''
        C_RESET=''
    else
        C_RED='\033[0;31m'
        C_GREEN='\033[0;32m'
        C_YELLOW='\033[0;33m'
        C_BLUE='\033[0;34m'
        C_DIM='\033[0;90m'
        C_BOLD='\033[1m'
        C_RESET='\033[0m'
    fi
}

################################################################################
## Version
##
## envoy_version reads the "## Version:" header comment from a script and
## prints the version string.
##
## @param  $1  string  Path to the script file
## @return void (prints version string to stdout, or "unknown")
################################################################################

envoy_version() {
    local script_path="$1"
    _trace "envoy_version: checking ${script_path:-<empty>}"
    if [[ -z "$script_path" ]] || [[ ! -f "$script_path" ]]; then
        printf '%s\n' "unknown"
        return 1
    fi
    local ver
    ver=$(grep '^## Version:' "$script_path" 2>/dev/null | head -n 1 \
          | sed 's/^## Version:[[:space:]]*//')
    if [[ -n "$ver" ]]; then
        _trace "envoy_version: found version ${ver} in ${script_path}"
        printf '%s\n' "$ver"
    else
        printf '%s\n' "unknown"
        return 1
    fi
}

################################################################################
## Temp Files
##
## envoy_mktemp creates a temporary file (or directory with -d) under
## ${TMPDIR:-/tmp} and registers it for automatic cleanup.
##
## _envoy_cleanup_temps is the EXIT trap handler that removes everything
## that was registered.
##
## Usage:
##   local tmp
##   tmp=$(envoy_mktemp)         # temp file
##   tmp=$(envoy_mktemp -d)      # temp directory
################################################################################

# Registry of temp paths to clean up (newline-separated)
_ENVOY_TEMP_REGISTRY=""

_envoy_cleanup_temps() {
    if [[ -z "$_ENVOY_TEMP_REGISTRY" ]]; then
        return 0
    fi
    local path
    while IFS= read -r path; do
        [[ -z "$path" ]] && continue
        if [[ -d "$path" ]]; then
            rm -rf "$path" 2>/dev/null
        elif [[ -f "$path" ]]; then
            rm -f "$path" 2>/dev/null
        fi
    done <<< "$_ENVOY_TEMP_REGISTRY"
    _ENVOY_TEMP_REGISTRY=""
}

envoy_mktemp() {
    local tmppath
    if [[ "${1:-}" == "-d" ]]; then
        tmppath=$(mktemp -d "${TMPDIR:-/tmp}/envoy.XXXXXXXXXX")
    else
        tmppath=$(mktemp "${TMPDIR:-/tmp}/envoy.XXXXXXXXXX")
    fi

    if [[ -z "$_ENVOY_TEMP_REGISTRY" ]]; then
        _ENVOY_TEMP_REGISTRY="$tmppath"
        # Install the cleanup trap only once (on the first temp created)
        trap '_envoy_cleanup_temps' EXIT
    else
        _ENVOY_TEMP_REGISTRY="${_ENVOY_TEMP_REGISTRY}
${tmppath}"
    fi

    printf '%s\n' "$tmppath"
}

################################################################################
## Atomic Writes
##
## envoy_atomic_write writes data to a target file atomically: a same-
## directory mktemp is populated then `mv`'d over the target. Because
## the temp lives next to the target, the rename is on a single
## filesystem and is therefore atomic per POSIX (rename(2)). A crash
## or signal mid-write leaves either the old file untouched OR the
## new file in place — never a truncated half-written state.
##
## Usage:
##   envoy_atomic_write <target>            # data on stdin
##   echo "hello" | envoy_atomic_write /etc/foo.conf
##
## ENV-178: standard helper for shared state files. Replaces ad-hoc
## `printf > file` and `{ … } > file` patterns that crash mid-write.
##
## @param  $1  string  Target file path
## @return 0 on success, non-zero on failure (target file untouched)
################################################################################

envoy_atomic_write() {
    local target="$1"
    if [[ -z "$target" ]]; then
        printf '%s\n' "ERROR: envoy_atomic_write requires a target path" >&2
        return 1
    fi
    local target_dir
    target_dir=$(dirname -- "$target") || return 1
    if [[ ! -d "$target_dir" ]]; then
        printf '%s\n' "ERROR: envoy_atomic_write: directory not found: $target_dir" >&2
        return 1
    fi
    # Same-dir mktemp + umask 077: the temp file is invisible to other
    # users while we populate it. State files often contain user-only
    # data; the temp inheriting world-readable perms before mv would
    # be a leak.
    local prev_umask tmp
    prev_umask=$(umask)
    umask 077
    tmp=$(mktemp "${target_dir}/.envoy_atomic.XXXXXX") || {
        umask "$prev_umask"
        printf '%s\n' "ERROR: envoy_atomic_write: mktemp failed under $target_dir" >&2
        return 1
    }
    umask "$prev_umask"
    # Catch any failure on stdin → temp; remove the temp before
    # propagating the error so we never leave an abandoned dotfile.
    if ! cat > "$tmp"; then
        rm -f "$tmp" 2>/dev/null
        return 1
    fi
    if ! mv -f "$tmp" "$target"; then
        rm -f "$tmp" 2>/dev/null
        return 1
    fi
    return 0
}

################################################################################
## Config Loading
##
## envoy_load_config delegates to the suite-wide loader in
## lib/envoy_envoyrc.sh (ENV-154) when available.  That loader provides
## a safe parser (no eval / no $(…) expansion), an upward walk for
## per-project `.envoyrc`, and the documented precedence ladder
## (CLI flag > shell env > most-specific .envoyrc > ... > XDG global).
##
## When envoy_envoyrc.sh isn't on disk (partial dev checkout), we fall
## back to the legacy `source`-based path that loads
## ${ENVOY_HOME}/envoy.conf and ~/.envoyrc only.  Tools shouldn't
## depend on the legacy fallback for new keys.
##
## @return void
################################################################################

envoy_load_config() {
    local envoy_home="${ENVOY_HOME:-$HOME/.envoy}"
    _trace "envoy_load_config: envoy_home=${envoy_home}"

    # ENV-154: prefer the safe suite-wide loader.  Sit alongside
    # envoy_common.sh in lib/.  Source on demand so we don't pay the
    # cost when the config layer isn't asked for.
    local _ec_dir
    _ec_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [[ -r "${_ec_dir}/envoy_envoyrc.sh" ]] && ! declare -F envoy_envoyrc_load >/dev/null; then
        # shellcheck disable=SC1091
        source "${_ec_dir}/envoy_envoyrc.sh"
    fi
    if declare -F envoy_envoyrc_load >/dev/null; then
        envoy_envoyrc_load
        _trace "envoy_load_config: envoy_envoyrc_load count=${_ENVOY_ENVOYRC_COUNT:-0}"
        return 0
    fi

    # --- Legacy fallback (pre-ENV-154) -------------------------------------
    # System-level / install-level config
    if [[ -f "${envoy_home}/envoy.conf" ]]; then
        # shellcheck disable=SC1090
        source "${envoy_home}/envoy.conf"
        _log_debug "Loaded config: ${envoy_home}/envoy.conf"
        _trace "envoy_load_config: loaded ${envoy_home}/envoy.conf"
    else
        _trace "envoy_load_config: no system config at ${envoy_home}/envoy.conf"
    fi

    # User-level config (higher precedence)
    if [[ -f "$HOME/.envoyrc" ]]; then
        # shellcheck disable=SC1090
        source "$HOME/.envoyrc"
        _log_debug "Loaded config: $HOME/.envoyrc"
        _trace "envoy_load_config: loaded $HOME/.envoyrc"
    else
        _trace "envoy_load_config: no user config at $HOME/.envoyrc"
    fi
}
