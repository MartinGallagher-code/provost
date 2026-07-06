#!/bin/bash
################################################################################
## envoy_status.sh — shared status-marker formatter (ENV-155).
##
## Colourises the `[OK]` / `[WARN]` / `[FAIL]` / `[GOOD]` / `[INFO]` /
## `[ERROR]` / `[SKIP]` / `[PASS]` / `[MISSING]` markers that several tools
## emit in their human output. Centralises the colour table so a `[OK]`
## that comes out of `envoy doctor` and the `PASS:` row that comes out of
## `envoy-capture verify` share the same green wrapper bytes.
##
## Public API:
##   fmt_status MARKER         echos the marker, ANSI-coloured when the
##                             stream is a TTY and NO_COLOR is unset.
##   envoy_status_active       predicate — true iff fmt_status would
##                             actually emit colour bytes (cheap guard
##                             for callers that build composite strings).
##
## Suppression cascade (any one disables colour, plain text still prints):
##   * `NO_COLOR=*` (any non-empty value) — de-facto standard
##   * `ENVOY_NO_COLOR=*`                  — suite-specific knob
##   * stdout (`fd 1`) is not a TTY        — pipelines and scripts
##   * `ENVOY_STATUS_FORCE_PLAIN=1`        — explicit kill switch / tests
##
## Test hook:
##   `ENVOY_STATUS_FORCE_COLOR=1` forces colour on regardless of TTY
##   detection so tests can pin the coloured output without `script(1)`.
##
## ASCII only — never switches to ✓ / ✗ / unicode marks. Project
## convention; broad terminal compat across the linux/wsl install base.
################################################################################

# Pure-bash table lookup; no external fork.
_ENVOY_STATUS_RESET=$'\033[0m'

_envoy_status_color () {
    case "$1" in
        '[OK]'|'[GOOD]'|'[PASS]')          echo $'\033[32m' ;;   # green
        '[INFO]')                          echo $'\033[36m' ;;   # cyan
        '[WARN]')                          echo $'\033[33m' ;;   # yellow
        '[FAIL]'|'[ERROR]'|'[MISSING]')    echo $'\033[31m' ;;   # red
        '[SKIP]')                          echo $'\033[2m' ;;    # dim
        *)                                 echo "" ;;
    esac
}

envoy_status_active () {
    # NO_COLOR (the de-facto standard) and ENVOY_STATUS_FORCE_PLAIN are
    # absolute "no": they win even when ENVOY_STATUS_FORCE_COLOR is set.
    [[ -n "${NO_COLOR:-}" ]]                          && return 1
    [[ -n "${ENVOY_NO_COLOR:-}" ]]                    && return 1
    [[ "${ENVOY_STATUS_FORCE_PLAIN:-0}" == "1" ]]     && return 1
    # Force-on (test hook) overrides only the TTY check.
    [[ "${ENVOY_STATUS_FORCE_COLOR:-0}" == "1" ]]     && return 0
    [[ -t 1 ]]
}

fmt_status () {
    local marker="${1:-}"
    if envoy_status_active; then
        local c
        c=$(_envoy_status_color "$marker")
        if [[ -n "$c" ]]; then
            printf '%s%s%s' "$c" "$marker" "$_ENVOY_STATUS_RESET"
            return
        fi
    fi
    printf '%s' "$marker"
}
