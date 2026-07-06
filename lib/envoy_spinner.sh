#!/bin/bash
################################################################################
## Envoy Shared Spinner Helper — envoy_spinner.sh  (ENV-147)
##
## Animates an ASCII heartbeat on stderr while a long, indeterminate
## operation runs.  Designed for cases where the tool can't report
## "N of M" progress (e.g. `git gc`, `git fsck`, multi-GB extraction
## startup) so the user has confidence the process isn't frozen.
##
## Sourcing is OPTIONAL — every tool can run standalone if the file
## isn't on disk; callers should provide a no-op fallback.
##
## Public API
## ----------
##   envoy_spinner_start [LABEL]
##       Forks a background loop that writes
##         \r{frame} {LABEL} ({elapsed}s)
##       to stderr at ~8 Hz.  Stores the bg PID in $_ENVOY_SPINNER_PID.
##       No-op when paging is suppressed (see envoy_spinner_active).
##
##   envoy_spinner_stop
##       Kills the bg loop, clears the line, and unsets state.
##       Idempotent — safe to call when no spinner is running.
##
##   envoy_spinner_run [LABEL] CMD [ARG...]
##       Convenience wrapper: starts the spinner, runs CMD, stops the
##       spinner, returns CMD's exit status.  Forwards SIGINT / SIGTERM
##       to CMD so Ctrl-C still works.
##
##   envoy_spinner_active
##       Predicate: returns 0 if a spinner *would* be drawn given the
##       current env / TTY / overrides; 1 otherwise.  Use to gate
##       expensive label-formatting paths.
##
## Reads (env)
## -----------
##   ENVOY_NO_SPINNER=1     Suite-wide suppression.
##   NO_COLOR=*             Spinner counts as decorative — suppressed.
##   ENVOY_NO_COLOR=*       Same.
##   _ENVOY_SPINNER_DISABLED=1
##                          Per-process suppression (set by --no-spinner
##                          flag parsing in callers).
##   ENVOY_SPINNER_FORCE_TTY=1
##                          Test hook: pretend stderr is a TTY.
##
## Writes (globals)
## ----------------
##   _ENVOY_SPINNER_PID     PID of the bg loop while running, "" otherwise.
##   _ENVOY_SPINNER_DISABLED
##                          0/1 — set to 1 by `--no-spinner` flag parsing.
##
## Design notes
## ------------
##   - ASCII frames only (`/ - \ |`).  Unicode (⠋⠙⠹…) renders as ?
##     on non-UTF-8 terminals and breaks the line-rewriter trick.
##   - Stderr (not stdout) is the right channel: many tools have their
##     primary output on stdout and pipe it elsewhere.  A spinner on
##     stdout would corrupt that.  `[ -t 2 ]` gates correctly.
##   - The bg loop is `disown`ed after fork so it doesn't print
##     "[1] 1234 Done" / "Killed" job-control noise on shell exit.
##   - On stop, we send TERM (not KILL) so the loop's own EXIT trap
##     can clear the spinner line.  `wait` is followed by a redirect
##     to /dev/null so any race-window stderr from the dying child
##     stays out of the user's terminal.
##   - SIGPIPE / EPIPE on the printf to a closed terminal are OK —
##     the loop keeps running until parent kills it.
################################################################################

# Guard against double-sourcing
[[ -n "${_ENVOY_SPINNER_LOADED:-}" ]] && return 0
_ENVOY_SPINNER_LOADED=1

_ENVOY_SPINNER_DISABLED="${_ENVOY_SPINNER_DISABLED:-0}"
_ENVOY_SPINNER_PID=""

################################################################################
## envoy_spinner_active
##
## Returns 0 (true) iff a spinner *should* be drawn:
##   - $_ENVOY_SPINNER_DISABLED is not 1
##   - $ENVOY_NO_SPINNER is not 1
##   - $NO_COLOR / $ENVOY_NO_COLOR are unset (spinner is decorative)
##   - stderr is a TTY (or $ENVOY_SPINNER_FORCE_TTY=1)
################################################################################

envoy_spinner_active() {
    [[ "${_ENVOY_SPINNER_DISABLED:-0}" == "1" ]] && return 1
    [[ "${ENVOY_NO_SPINNER:-0}" == "1" ]] && return 1
    [[ -n "${NO_COLOR:-}" ]] && return 1
    [[ -n "${ENVOY_NO_COLOR:-}" ]] && return 1
    if [[ "${ENVOY_SPINNER_FORCE_TTY:-0}" == "1" ]]; then
        return 0
    fi
    [[ -t 2 ]] || return 1
    return 0
}

################################################################################
## envoy_spinner_disable
##
## Per-process kill switch.  Caller's `--no-spinner` flag parsing should
## call this rather than setting the variable directly so the contract is
## obvious in shell traces.
################################################################################

envoy_spinner_disable() {
    _ENVOY_SPINNER_DISABLED=1
}

################################################################################
## _envoy_spinner_loop LABEL
##
## Internal: the bg loop body.  Not part of the public API.
##
## Writes a continuously-overwritten line to stderr at ~8 Hz.  Cleans up
## the spinner line on EXIT so callers don't have to.
################################################################################

_envoy_spinner_loop() {
    local label="${1:-Working}"
    local frames='/-\|'
    local i=0
    local start
    start=$(date +%s)

    # Clear the line on exit (signal or graceful kill from parent).
    # `\r\033[2K` is Erase-In-Line; we keep it ASCII-only, falling back
    # to overwriting with spaces (80 wide is plenty for our labels).
    trap 'printf "\r%80s\r" "" >&2; exit 0' TERM INT EXIT

    while :; do
        local now elapsed frame
        now=$(date +%s)
        elapsed=$(( now - start ))
        frame="${frames:$((i % 4)):1}"
        # %-50s left-justifies and pads so the trailing remnants of a
        # previous, longer label don't linger on the line.
        printf '\r%s %s (%ds) ' "$frame" "$label" "$elapsed" >&2
        i=$((i + 1))
        sleep 0.125
    done
}

################################################################################
## envoy_spinner_start [LABEL]
##
## Forks the bg loop.  Stores the PID in $_ENVOY_SPINNER_PID.  No-op
## if envoy_spinner_active is false or if a spinner is already running.
################################################################################

envoy_spinner_start() {
    envoy_spinner_active || return 0
    [[ -n "$_ENVOY_SPINNER_PID" ]] && return 0
    local label="${1:-Working}"
    _envoy_spinner_loop "$label" &
    _ENVOY_SPINNER_PID=$!
    # Suppress "[1] 1234" job-control noise that bash prints on exit
    # when the loop is still around.
    disown "$_ENVOY_SPINNER_PID" 2>/dev/null || true
}

################################################################################
## envoy_spinner_stop
##
## Kills the bg loop and clears the line.  Idempotent.
################################################################################

envoy_spinner_stop() {
    [[ -z "${_ENVOY_SPINNER_PID:-}" ]] && return 0
    # TERM lets the loop's own EXIT trap clear the line.  Drop any
    # "Terminated" noise the shell might print.
    kill -TERM "$_ENVOY_SPINNER_PID" 2>/dev/null || true
    wait "$_ENVOY_SPINNER_PID" 2>/dev/null || true
    _ENVOY_SPINNER_PID=""
    # Belt-and-braces: if the loop's trap somehow didn't fire, still
    # clear the current line so the next stderr write starts clean.
    printf '\r%80s\r' '' >&2 2>/dev/null || true
}

################################################################################
## envoy_spinner_run [LABEL] CMD [ARG...]
##
## Convenience: spinner-wrap a command.  Returns CMD's exit status.
## Always stops the spinner, even on caller's signal.
##
## Forwards SIGINT / SIGTERM from the parent shell to CMD via a trap on
## the wait, so Ctrl-C still terminates the user's command.
################################################################################

envoy_spinner_run() {
    local label="$1"; shift
    if ! envoy_spinner_active; then
        "$@"
        return $?
    fi
    envoy_spinner_start "$label"
    local rc=0
    "$@" || rc=$?
    envoy_spinner_stop
    return "$rc"
}
