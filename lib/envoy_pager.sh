#!/bin/bash
################################################################################
## Envoy Shared Pager Helper — envoy_pager.sh  (ENV-143)
##
## Single source of truth for "auto-pipe long output through $PAGER" across
## the active Envoy suite (envoy-capture, envoy-extract, envoy-analyze,
## envoy-browse).  Mirrors the behaviour users expect from git, systemctl, less, etc.:
## a TTY caller gets a pager; a piped/redirected caller gets a clean pipe.
##
## Sourcing this file is OPTIONAL — every tool still runs standalone if it
## isn't available.  No external deps beyond bash 4.0+ and POSIX `less`.
##
## Public API:
##   envoy_pager_parse_args [args...]    Strip --no-pager from argv into
##                                        $_ENVOY_PAGER_REMAINING (array).
##   envoy_pager_disable                  Force-disable the pager (e.g. once a
##                                        --json caller is detected).
##   envoy_pager_active                   Returns 0 if a pager run is wanted.
##   envoy_maybe_page                     Filter on stdin: pipes through
##                                        $PAGER when active, else just cats.
##
## Reads (env / globals):
##   PAGER                  Override; default is `less -FRX`.
##   ENVOY_NO_PAGER         When 1, disables paging suite-wide.
##   _ENVOY_PAGER_DISABLED  Per-process disable (set by --no-pager).
##   ENVOY_PAGER_FORCE_TTY  Test hook: pretend stdout is a TTY.
##
## Writes (globals):
##   _ENVOY_PAGER_DISABLED       0/1
##   _ENVOY_PAGER_REMAINING[@]   argv with --no-pager stripped
##
## ENV-143 design notes:
##   - Default pager is `less -FRX`:
##       -F  quit if output fits on one screen (matches git log/diff)
##       -R  pass ANSI colour codes through unchanged
##       -X  do NOT use the alt-screen, so short output stays visible after
##           less exits.  Combined with -F this gives the "feels native"
##           behaviour.
##   - We do NOT try to measure terminal height ourselves — `less -F` already
##     does the right thing.  Keeping the gate to "stdout is a TTY" matches
##     git's behaviour and is robust across SSH, tmux, non-256-colour terms.
##   - JSON output bypass is the *caller's* responsibility (they call
##     envoy_pager_disable when --json / --format=json|csv|tsv is selected).
##     We can't introspect output bytes here without breaking streaming.
################################################################################

# Guard against double-sourcing
[[ -n "${_ENVOY_PAGER_LOADED:-}" ]] && return 0
_ENVOY_PAGER_LOADED=1

_ENVOY_PAGER_DISABLED="${_ENVOY_PAGER_DISABLED:-0}"
_ENVOY_PAGER_REMAINING=()

################################################################################
## envoy_pager_parse_args [args...]
##
## Walks argv and strips `--no-pager` from it.  Remaining args land in the
## $_ENVOY_PAGER_REMAINING array so callers can `set -- "${_ENVOY_PAGER_REMAINING[@]}"`.
## When `--no-pager` is seen, sets $_ENVOY_PAGER_DISABLED=1.
##
## Idempotent — safe to call multiple times.
################################################################################

envoy_pager_parse_args() {
    _ENVOY_PAGER_REMAINING=()
    local arg
    for arg in "$@"; do
        if [[ "$arg" == "--no-pager" ]]; then
            _ENVOY_PAGER_DISABLED=1
            continue
        fi
        _ENVOY_PAGER_REMAINING+=("$arg")
    done
}

################################################################################
## envoy_pager_disable
##
## Force-disable paging for the rest of the process.  Use when a caller
## detects --json / --format=json|csv|tsv: structured output must reach the
## consumer untouched.
################################################################################

envoy_pager_disable() {
    _ENVOY_PAGER_DISABLED=1
}

################################################################################
## envoy_pager_active
##
## Returns 0 (true) when output should be piped through the pager:
##   - $_ENVOY_PAGER_DISABLED is not 1
##   - $ENVOY_NO_PAGER is not 1
##   - $PAGER is not empty and not "cat"
##   - stdout is a TTY (or $ENVOY_PAGER_FORCE_TTY=1 for tests)
##
## Returns non-zero otherwise.  Does not invoke the pager.
################################################################################

envoy_pager_active() {
    [[ "${_ENVOY_PAGER_DISABLED:-0}" == "1" ]] && return 1
    [[ "${ENVOY_NO_PAGER:-0}" == "1" ]] && return 1

    # Allow PAGER="" or PAGER=cat to disable, matching git's convention.
    local pager="${PAGER-less -FRX}"
    [[ -z "$pager" ]] && return 1
    [[ "$pager" == "cat" ]] && return 1

    if [[ "${ENVOY_PAGER_FORCE_TTY:-0}" == "1" ]]; then
        return 0
    fi

    [[ -t 1 ]] || return 1
    return 0
}

################################################################################
## envoy_maybe_page
##
## Stdin filter.  When envoy_pager_active is true, pipes stdin through
## ${PAGER:-less -FRX}; otherwise it's a transparent `cat`.  Always returns
## 0 even if the user quits the pager — `q` is normal, not an error.
##
## Usage:
##   { command_that_emits_lots ; } | envoy_maybe_page
##
## Why eval-free word splitting: $PAGER may legitimately contain flags
## (e.g. "less -RS", "more").  We use `read -a` so the user can override
## without us inviting an injection vector via eval.
################################################################################

envoy_maybe_page() {
    if envoy_pager_active; then
        local pager_str="${PAGER:-less -FRX}"
        local -a pager_argv=()
        # shellcheck disable=SC2206
        read -r -a pager_argv <<< "$pager_str"
        # SIGPIPE on early `q` is not an error.  Suppress it so the caller's
        # exit status still reflects whether the producer succeeded.
        "${pager_argv[@]}" || true
    else
        cat
    fi
}
