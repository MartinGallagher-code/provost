#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Envoy Shared Config Loader — envoy_envoyrc.sh  (ENV-154)
##
## Generalises EnvoyCapture's `.capturerc` layer (ENV-083) to the whole
## suite.  Every tool that sources this file picks up suite-wide
## defaults from a single hierarchy:
##
##   1.  $XDG_CONFIG_HOME/envoy/config (or ~/.config/envoy/config)
##           Global user defaults.
##   2.  ~/.envoyrc
##           Legacy / convenience location, same format.
##   3.  .envoyrc walked upward from $PWD to / (or $HOME)
##           Per-project overrides, mirroring the .capturerc walk.
##
## Already-set environment variables ALWAYS win — the loader uses
## ${VAR:-default} semantics by skipping any KEY whose env var is
## already non-empty when the loader runs.  This pins the documented
## precedence ladder:
##
##     CLI flag  >  shell env  >  (this file's three sources)  >  default
##
## Sourcing is OPTIONAL — every tool keeps working without it.  Tools
## that want the layer source it explicitly and call `envoy_envoyrc_load`
## once at startup, before parsing CLI flags.
##
## Public API
## ----------
##   envoy_envoyrc_load              Discover + load every config file
##                                    in the documented order, exporting
##                                    keys to the environment.  Skips a
##                                    key when its env var is already set.
##                                    Returns the count of unique keys
##                                    loaded via $_ENVOY_ENVOYRC_COUNT.
##
##   envoy_envoyrc_files             Echo the list of config files that
##                                    *would* be considered, in load order
##                                    (one per line).  Useful for
##                                    `envoy config show`.
##
##   envoy_envoyrc_parse FILE        Parse a single config file safely
##                                    (no eval, no $(…) substitution).
##                                    Sets keys via `export` only when
##                                    they are not already set.
##                                    Returns non-zero on bad syntax.
##
## Format
## ------
##   - One `KEY=VALUE` per line.
##   - Keys must match `^[A-Z_][A-Z0-9_]*$` (POSIX env-var convention).
##     Anything else is rejected to avoid shell-injection vectors.
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
##   ENVOY_ENVOYRC_DEBUG=1          When set, emit a one-line trace per
##                                  loaded file to stderr.
##
## Writes (globals)
## ----------------
##   _ENVOY_ENVOYRC_COUNT           Count of unique keys exported by the
##                                  most recent load.
##   _ENVOY_ENVOYRC_SOURCES         Space-delimited paths of files that
##                                  contributed at least one key.
################################################################################

# Guard against double-sourcing
[[ -n "${_ENVOY_ENVOYRC_LOADED:-}" ]] && return 0
_ENVOY_ENVOYRC_LOADED=1

_ENVOY_ENVOYRC_COUNT=0
_ENVOY_ENVOYRC_SOURCES=""

################################################################################
## envoy_envoyrc_files
##
## Echo (one per line) the list of config files that exist, in
## load order — least-specific first, most-specific last.  Used by
## `envoy_envoyrc_load`, `envoy config show`, and the test harness.
##
## Order:
##   $XDG_CONFIG_HOME/envoy/config  (or ~/.config/envoy/config)
##   ~/.envoyrc
##   ancestors of $PWD with a .envoyrc, walked from / down to $PWD
##   $PWD/.envoyrc                  (only listed once even if it
##                                    coincides with $HOME/.envoyrc)
################################################################################

envoy_envoyrc_files() {
    local xdg="${XDG_CONFIG_HOME:-$HOME/.config}"
    local out=()

    # 1. Global XDG config.
    [[ -f "${xdg}/envoy/config" ]] && out+=("${xdg}/envoy/config")

    # 2. Legacy / convenience location.
    [[ -f "$HOME/.envoyrc" ]] && out+=("$HOME/.envoyrc")

    # 3. Walk upward from $PWD looking for .envoyrc.  Stop at $HOME or /.
    local d="$PWD"
    local -a walk=()
    while [[ -n "$d" && "$d" != "/" ]]; do
        if [[ -f "$d/.envoyrc" ]]; then
            walk+=("$d/.envoyrc")
        fi
        # Stop at $HOME — its .envoyrc is already covered by step 2 above.
        [[ "$d" == "$HOME" ]] && break
        local parent
        parent="$(dirname -- "$d")"
        [[ "$parent" == "$d" ]] && break
        d="$parent"
    done
    # walk[] is collected $PWD→ancestors; reverse so the most-distant
    # ancestor loads first and $PWD/.envoyrc loads last (most-specific
    # wins, matching the documented precedence ladder).
    local i
    for ((i=${#walk[@]}-1; i>=0; i--)); do
        out+=("${walk[$i]}")
    done

    # Dedupe — $HOME/.envoyrc may also appear via the upward walk when
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
## envoy_envoyrc_parse FILE [SHELL_PROTECT]
##
## Safely parse a single config file.  Exports each KEY=VALUE pair.
##
## When SHELL_PROTECT=1 (the default when called via `envoy_envoyrc_load`),
## a key is skipped if it was set in the original shell environment
## *before* `envoy_envoyrc_load` was invoked — that's the "shell env wins
## over file" rule.  Subsequent files in the chain CAN override each
## other, so the most-specific `.envoyrc` legitimately overrides a
## less-specific one.
##
## SHELL_PROTECT=0 makes every assignment unconditional (useful when the
## caller has already filtered keys themselves).
##
## Returns 0 on success.  Returns 1 if the file isn't readable.  Bad
## lines are skipped with a warning to stderr; they don't fail the load.
################################################################################

envoy_envoyrc_parse() {
    local file="$1"
    local shell_protect="${2:-0}"
    [[ -r "$file" ]] || return 1

    local lineno=0 line key value
    while IFS= read -r line || [[ -n "$line" ]]; do
        lineno=$((lineno + 1))

        # Strip leading whitespace; comments and blanks are no-ops.
        line="${line#"${line%%[![:space:]]*}"}"
        [[ -z "$line" || "$line" == \#* ]] && continue

        # Reject anything not matching KEY=...
        if [[ "$line" != *=* ]]; then
            printf 'envoy: warning: %s:%d: not a KEY=VALUE line (skipped)\n' \
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
            printf 'envoy: warning: %s:%d: invalid key %q (must match [A-Z_][A-Z0-9_]*)\n' \
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
        # snapshot we took before `envoy_envoyrc_load` started.  When
        # called standalone (`shell_protect=0`), no such snapshot
        # exists and every assignment goes through.
        if [[ "$shell_protect" == "1" ]] \
            && [[ -n "${_ENVOY_ENVOYRC_SNAPSHOT[$key]+x}" ]]; then
            continue
        fi

        export "$key=$value"
        _ENVOY_ENVOYRC_COUNT=$((_ENVOY_ENVOYRC_COUNT + 1))
        if [[ "${ENVOY_ENVOYRC_DEBUG:-0}" == "1" ]]; then
            printf 'envoy_envoyrc: set %s=%s from %s:%d\n' \
                "$key" "$value" "$file" "$lineno" >&2
        fi
    done < "$file"
    return 0
}

################################################################################
## envoy_envoyrc_load
##
## Load every config file in the documented order.  Idempotent — keys
## already in the environment are preserved.  Updates the count and
## sources globals.
##
## Call once at the top of each tool, before flag parsing, so flags
## still win.
################################################################################

envoy_envoyrc_load() {
    [[ "${ENVOY_NO_RC:-0}" == 1 ]] && return 0
    _ENVOY_ENVOYRC_COUNT=0
    _ENVOY_ENVOYRC_SOURCES=""

    # Snapshot the shell env at load time.  Anything already set here
    # is "from the shell" and outranks every config file in the chain.
    # Files can still override each other; only the snapshot is sticky.
    declare -gA _ENVOY_ENVOYRC_SNAPSHOT=()
    local _ek
    while IFS= read -r _ek; do
        [[ -z "$_ek" ]] && continue
        _ENVOY_ENVOYRC_SNAPSHOT[$_ek]=1
    done < <(compgen -e 2>/dev/null || env | sed -n 's/^\([^=]*\)=.*/\1/p')

    local file
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        local before="$_ENVOY_ENVOYRC_COUNT"
        envoy_envoyrc_parse "$file" 1
        if (( _ENVOY_ENVOYRC_COUNT > before )); then
            if [[ -n "$_ENVOY_ENVOYRC_SOURCES" ]]; then
                _ENVOY_ENVOYRC_SOURCES+=" "
            fi
            _ENVOY_ENVOYRC_SOURCES+="$file"
        fi
    done < <(envoy_envoyrc_files)
}
