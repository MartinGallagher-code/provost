#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## provost shared Config Loader — provost_rc.sh  (ENV-154)
##
## Generalises EnvoyCapture's `.capturerc` layer (ENV-083) to the whole
## suite.  Every tool that sources this file picks up suite-wide
## defaults from a single hierarchy:
##
##   1.  $XDG_CONFIG_HOME/provost/config (or ~/.config/provost/config)
##           Global user defaults.
##   2.  ~/.provostrc
##           Legacy / convenience location, same format.
##   3.  .provostrc walked upward from $PWD, never past $HOME
##           Per-project overrides, mirroring the .capturerc walk. When $PWD
##           is outside $HOME only $PWD/.provostrc itself is considered.
##
## SECURITY. A .provostrc can sit in any checkout the user cds into, so the
## loader treats every file as untrusted input:
##   - PROVOST_NO_RC=1 disables the whole layer (provost sets it).
##   - Only keys with a tool prefix — PROVOST_ — are exported;
##     anything else is skipped with a warning. On top of that a hard deny
##     list (LD_*, BASH_ENV, ENV, PATH, IFS, PS4, SHELLOPTS, BASHOPTS, …) can
##     never be set, even if the allow list is ever widened. (LD_PRELOAD from
##     a .provostrc in an untrusted checkout used to reach child processes.)
##   - A file not owned by the current user, or writable by group or others,
##     is skipped.
##
## Already-set environment variables ALWAYS win — the loader uses
## ${VAR:-default} semantics by skipping any KEY whose env var is
## already non-empty when the loader runs.  This pins the documented
## precedence ladder:
##
##     CLI flag  >  shell env  >  (this file's three sources)  >  default
##
## Sourcing is OPTIONAL — every tool keeps working without it.  Tools
## that want the layer source it explicitly and call `provost_rc_load`
## once at startup, before parsing CLI flags.
##
## Public API
## ----------
##   provost_rc_load              Discover + load every config file
##                                    in the documented order, exporting
##                                    keys to the environment.  Skips a
##                                    key when its env var is already set.
##                                    Returns the count of unique keys
##                                    loaded via $_PROVOST_RC_COUNT.
##
##   provost_rc_files             Echo the list of config files that
##                                    *would* be considered, in load order
##                                    (one per line).  Useful for
##                                    `provost-extract`.
##
##   provost_rc_parse FILE        Parse a single config file safely
##                                    (no eval, no $(…) substitution).
##                                    Sets keys via `export` only when
##                                    they are not already set.
##                                    Returns non-zero on bad syntax.
##
## Format
## ------
##   - One `KEY=VALUE` per line.
##   - Keys must match `^[A-Z_][A-Z0-9_]*$` (POSIX env-var convention) AND
##     carry an allowed prefix (PROVOST_) AND not be on the
##     deny list. Anything else is rejected (see SECURITY above).
##   - VALUE may optionally be wrapped in single or double quotes;
##     the wrapping characters are stripped.  No backtick / `$(…)`
##     expansion happens — the file is parsed, not sourced.
##   - Lines starting with `#` and blank lines are ignored.
##   - Inline `# comment` after a value is NOT supported (would break
##     values containing `#`).  Document.
##
## Reads (env / globals)
## ---------------------
##   XDG_CONFIG_HOME, HOME, PWD     Standard.
##   PROVOST_NO_RC=1                  Skip loading entirely.
##   PROVOST_RC_DEBUG=1          When set, emit a one-line trace per
##                                  loaded file to stderr.
##
## Writes (globals)
## ----------------
##   _PROVOST_RC_COUNT           Count of unique keys exported by the
##                                  most recent load.
##   _PROVOST_RC_SOURCES         Space-delimited paths of files that
##                                  contributed at least one key.
################################################################################

# Guard against double-sourcing
[[ -n "${_PROVOST_RC_LOADED:-}" ]] && return 0
_PROVOST_RC_LOADED=1

_PROVOST_RC_COUNT=0
_PROVOST_RC_SOURCES=""

################################################################################
## provost_rc_files
##
## Echo (one per line) the list of config files that exist, in
## load order — least-specific first, most-specific last.  Used by
## `provost_rc_load`, `provost-extract`, and the test harness.
##
## Order:
##   $XDG_CONFIG_HOME/provost/config  (or ~/.config/provost/config)
##   ~/.provostrc
##   ancestors of $PWD with a .provostrc, walked from / down to $PWD
##   $PWD/.provostrc                  (only listed once even if it
##                                    coincides with $HOME/.provostrc)
################################################################################

provost_rc_files() {
    local xdg="${XDG_CONFIG_HOME:-$HOME/.config}"
    local out=()

    # 1. Global XDG config.
    [[ -f "${xdg}/provost/config" ]] && out+=("${xdg}/provost/config")

    # 2. Legacy / convenience location.
    [[ -f "$HOME/.provostrc" ]] && out+=("$HOME/.provostrc")

    # 3. Walk upward from $PWD looking for .provostrc — never past $HOME.
    #    Outside $HOME (a checkout under /tmp, /srv, …) there is no trusted
    #    boundary to stop at, so only $PWD/.provostrc itself is considered;
    #    walking on to / would pick up files in shared, world-writable
    #    parents like /tmp.
    local d="$PWD"
    local -a walk=()
    local home="${HOME%/}"
    local under_home=0
    if [[ -n "$home" && ( "$d" == "$home" || "$d" == "$home"/* ) ]]; then
        under_home=1
    fi
    while [[ -n "$d" && "$d" != "/" ]]; do
        if [[ -f "$d/.provostrc" ]]; then
            walk+=("$d/.provostrc")
        fi
        # Outside $HOME: $PWD only.
        [[ $under_home -eq 1 ]] || break
        # Stop at $HOME — its .provostrc is already covered by step 2 above.
        [[ "$d" == "$home" ]] && break
        local parent
        parent="$(dirname -- "$d")"
        [[ "$parent" == "$d" ]] && break
        d="$parent"
    done
    # walk[] is collected $PWD→ancestors; reverse so the most-distant
    # ancestor loads first and $PWD/.provostrc loads last (most-specific
    # wins, matching the documented precedence ladder).
    local i
    for ((i=${#walk[@]}-1; i>=0; i--)); do
        out+=("${walk[$i]}")
    done

    # Dedupe — $HOME/.provostrc may also appear via the upward walk when
    # $PWD is $HOME or a child.  Print each path once, preserving the
    # first-seen position so load order stays deterministic.
    local p
    declare -A seen=()
    for p in "${out[@]}"; do
        [[ -n "${seen[$p]:-}" ]] && continue
        seen[$p]=1
        printf '%s\n' "$p"
    done
}

################################################################################
## provost_rc_parse FILE [SHELL_PROTECT]
##
## Safely parse a single config file.  Exports each KEY=VALUE pair.
##
## When SHELL_PROTECT=1 (the default when called via `provost_rc_load`),
## a key is skipped if it was set in the original shell environment
## *before* `provost_rc_load` was invoked — that's the "shell env wins
## over file" rule.  Subsequent files in the chain CAN override each
## other, so the most-specific `.provostrc` legitimately overrides a
## less-specific one.
##
## SHELL_PROTECT=0 makes every assignment unconditional (useful when the
## caller has already filtered keys themselves).
##
## Returns 0 on success.  Returns 1 if the file isn't readable.  Bad
## lines are skipped with a warning to stderr; they don't fail the load.
################################################################################

# provost_rc_key_allowed KEY — 0 when a config file may set KEY.
# Allow list: the suite's own prefixes. Deny list: variables that change how
# the dynamic linker, the shell or child processes behave — refused even if a
# future allow-list entry would match them.
provost_rc_key_allowed() {
    local key="$1"
    case "$key" in
        LD_*|BASH_ENV|ENV|PATH|IFS|PS4|SHELLOPTS|BASHOPTS|CDPATH|GLOBIGNORE \
        |BASH_FUNC_*|PROMPT_COMMAND|HOME|SHELL|TMPDIR|PYTHONPATH|PYTHONSTARTUP \
        |PERL5LIB|PERL5OPT|RUBYOPT|NODE_OPTIONS|GIT_*|DYLD_*|LOCPATH|GCONV_PATH \
        |MALLOC_*|HOSTALIASES|RESOLV_HOST_CONF|NLSPATH)
            return 1 ;;
    esac
    case "$key" in
        PROVOST_*) return 0 ;;
    esac
    return 1
}

# provost_rc_file_trusted FILE — 0 when FILE is owned by the current user
# and not writable by group or others. Anything else could have been planted
# (a shared checkout, a world-writable parent) and is skipped.
provost_rc_file_trusted() {
    local file="$1" perms
    [[ -O "$file" ]] || return 1
    # %a = octal permission bits (GNU stat); BSD/macOS stat uses -f %Lp.
    perms="$(stat -c '%a' -- "$file" 2>/dev/null || stat -f '%Lp' -- "$file" 2>/dev/null)" || return 1
    [[ "$perms" =~ ^[0-7]+$ ]] || return 1
    # group-write (020) or other-write (002) -> untrusted
    (( (8#$perms & 8#022) == 0 )) || return 1
    return 0
}

provost_rc_parse() {
    local file="$1"
    local shell_protect="${2:-0}"
    [[ -r "$file" ]] || return 1
    if ! provost_rc_file_trusted "$file"; then
        printf 'provost: warning: %s: not owned by you or writable by others (skipped)\n' \
            "$file" >&2
        return 1
    fi

    local lineno=0 line key value
    while IFS= read -r line || [[ -n "$line" ]]; do
        lineno=$((lineno + 1))

        # Strip leading whitespace; comments and blanks are no-ops.
        line="${line#"${line%%[![:space:]]*}"}"
        [[ -z "$line" || "$line" == \#* ]] && continue

        # Reject anything not matching KEY=...
        if [[ "$line" != *=* ]]; then
            printf 'provost: warning: %s:%d: not a KEY=VALUE line (skipped)\n' \
                "$file" "$lineno" >&2
            continue
        fi
        key="${line%%=*}"
        value="${line#*=}"

        # Strip trailing whitespace from key (be lenient about user typos
        # like `KEY = value` — but only on the key side; values stay
        # verbatim because they may legitimately contain spaces).
        key="${key%"${key##*[![:space:]]}"}"

        # Validate key shape.  Refuse `eval`-able shenanigans like
        # `KEY=$(rm -rf /)` by ensuring the key is a plain POSIX name.
        if ! [[ "$key" =~ ^[A-Z_][A-Z0-9_]*$ ]]; then
            printf 'provost: warning: %s:%d: invalid key %q (must match [A-Z_][A-Z0-9_]*)\n' \
                "$file" "$lineno" "$key" >&2
            continue
        fi

        # Allow / deny list (see SECURITY in the header).
        if ! provost_rc_key_allowed "$key"; then
            printf 'provost: warning: %s:%d: key %s not allowed in a config file (only PROVOST_*; skipped)\n' \
                "$file" "$lineno" "$key" >&2
            continue
        fi

        # Strip a single matching pair of surrounding quotes from the
        # value.  We don't process backticks / $(…) — the file is
        # parsed, not sourced.
        if [[ ${#value} -ge 2 ]]; then
            local first="${value:0:1}" last="${value: -1}"
            if [[ "$first" == '"' && "$last" == '"' ]] \
            || [[ "$first" == "'" && "$last" == "'" ]]; then
                value="${value:1:${#value}-2}"
            fi
        fi

        # Shell-env-wins-over-file: skip when the key is in the
        # snapshot we took before `provost_rc_load` started.  When
        # called standalone (`shell_protect=0`), no such snapshot
        # exists and every assignment goes through.
        if [[ "$shell_protect" == "1" ]] \
            && [[ -n "${_PROVOST_RC_SNAPSHOT[$key]+x}" ]]; then
            continue
        fi

        export "$key=$value"
        _PROVOST_RC_COUNT=$((_PROVOST_RC_COUNT + 1))
        if [[ "${PROVOST_RC_DEBUG:-0}" == "1" ]]; then
            printf 'provost_rc: set %s=%s from %s:%d\n' \
                "$key" "$value" "$file" "$lineno" >&2
        fi
    done < "$file"
    return 0
}

################################################################################
## provost_rc_load
##
## Load every config file in the documented order.  Idempotent — keys
## already in the environment are preserved.  Updates the count and
## sources globals.
##
## Call once at the top of each tool, before flag parsing, so flags
## still win.
################################################################################

provost_rc_load() {
    _PROVOST_RC_COUNT=0
    _PROVOST_RC_SOURCES=""

    # Opt-out: provost sets this so no .provostrc is ever consulted.
    [[ "${PROVOST_NO_RC:-0}" == "1" ]] && return 0

    # Snapshot the shell env at load time.  Anything already set here
    # is "from the shell" and outranks every config file in the chain.
    # Files can still override each other; only the snapshot is sticky.
    declare -gA _PROVOST_RC_SNAPSHOT=()
    local _ek
    while IFS= read -r _ek; do
        [[ -z "$_ek" ]] && continue
        _PROVOST_RC_SNAPSHOT[$_ek]=1
    done < <(compgen -e 2>/dev/null || env | sed -n 's/^\([^=]*\)=.*/\1/p')

    local file
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        local before="$_PROVOST_RC_COUNT"
        provost_rc_parse "$file" 1
        if (( _PROVOST_RC_COUNT > before )); then
            if [[ -n "$_PROVOST_RC_SOURCES" ]]; then
                _PROVOST_RC_SOURCES+=" "
            fi
            _PROVOST_RC_SOURCES+="$file"
        fi
    done < <(provost_rc_files)
}
