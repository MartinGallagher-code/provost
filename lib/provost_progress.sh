#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## provost_progress.sh — shared progress-indicator helper (ENV-135).
##
## Two long-running workflows feel hung to a new user because they run
## silent while doing non-trivial work:
##   * provost-extract on stdin against the full strategy library
##   * provost-analyze on a wide CSV (column-stats stage)
##
## This module exports a tiny API both tools call so the format and
## suppression rules stay uniform suite-wide.
##
## Public API:
##   provost_progress_init [TOTAL]     enable progress for this run; pre-arms
##                                   the gating predicates. TOTAL is
##                                   optional and used by tick callers
##                                   that pass `n` rather than `n/N` text.
##   provost_progress_active           returns 0 (true) iff progress should
##                                   render right now. Cheap predicate to
##                                   guard hot loops.
##   provost_progress_tick N TOTAL TEXT  emits one progress line. TTY callers
##                                   get `\r`-rewritten in-place updates;
##                                   non-TTY callers get one full line per
##                                   tick (line-oriented for log readers).
##   provost_progress_done              clears the in-place TTY line so the
##                                   next stderr write starts fresh.
##
## Suppression rules (any one of these disables progress):
##   * `[ -t 2 ]` is false AND --progress was NOT passed (no TTY → silent
##     by default; opt-in available so log readers can still see ticks).
##   * --no-progress / `PROVOST_NO_PROGRESS=1` / `PROVOST_QUIET=1` / `NO_COLOR=*`.
##   * Caller passed --quiet (caller decides what that means; we read
##     `PROVOST_QUIET` which the suite quiet flag sets — ENV-151).
##
## Inputs (caller-controlled before provost_progress_init):
##   PROVOST_PROGRESS_OPT_IN=1     same as --progress (force-enable on non-TTY).
##   PROVOST_PROGRESS_DISABLE=1    same as --no-progress (force-disable).
##   PROVOST_NO_PROGRESS=1         alias accepted for tool-style consistency.
##   PROVOST_PROGRESS_FORCE_TTY=1  test hook: pretend stderr is a TTY.
##
## Output: stderr only. Stdout is reserved for the tool's primary payload
## so pipelines that consume it remain byte-identical. Lines are ASCII-only
## (no unicode spinners) per the project convention.
################################################################################

# Internal state.
_PROVOST_PROGRESS_ARMED=0
_PROVOST_PROGRESS_LAST_LEN=0
_PROVOST_PROGRESS_IS_TTY=0

# Compute and cache the gating decision. Idempotent: call once per run
# (typically right after argument parsing).
provost_progress_init () {
    _PROVOST_PROGRESS_ARMED=0
    _PROVOST_PROGRESS_LAST_LEN=0

    # Hard-disable knobs. Any non-empty value beats the opt-in.
    if [[ "${PROVOST_PROGRESS_DISABLE:-0}" != "0" \
       || "${PROVOST_NO_PROGRESS:-0}"      != "0" \
       || "${PROVOST_QUIET:-0}"            != "0" \
       || -n "${NO_COLOR:-}" ]]; then
        return 0
    fi

    # TTY detection — overridable for tests (PROVOST_PROGRESS_FORCE_TTY=1).
    if [[ "${PROVOST_PROGRESS_FORCE_TTY:-0}" == "1" ]]; then
        _PROVOST_PROGRESS_IS_TTY=1
    elif [[ -t 2 ]]; then
        _PROVOST_PROGRESS_IS_TTY=1
    else
        _PROVOST_PROGRESS_IS_TTY=0
    fi

    # On a non-TTY we still arm if the user passed --progress
    # (`PROVOST_PROGRESS_OPT_IN=1`). On a TTY we arm by default.
    if [[ "$_PROVOST_PROGRESS_IS_TTY" == "1" \
       || "${PROVOST_PROGRESS_OPT_IN:-0}" == "1" ]]; then
        _PROVOST_PROGRESS_ARMED=1
    fi
}

provost_progress_active () {
    [[ "$_PROVOST_PROGRESS_ARMED" == "1" ]]
}

# Emit one progress line. `n / total` are integers; `text` is a short
# label (strategy / column / stage). Width drift between consecutive
# lines is tracked so a longer label doesn't leave trailing characters
# from a previous tick visible after carriage return.
provost_progress_tick () {
    [[ "$_PROVOST_PROGRESS_ARMED" == "1" ]] || return 0
    local n="${1:-0}" total="${2:-0}" text="${3:-}"
    local line
    if [[ "$total" -gt 0 ]]; then
        printf -v line '[%d/%d] %s' "$n" "$total" "$text"
    else
        printf -v line '[%s] %s' "$n" "$text"
    fi

    if [[ "$_PROVOST_PROGRESS_IS_TTY" == "1" ]]; then
        # In-place update: pad to last length so trailing chars from a
        # longer previous label are erased.
        local cur_len=${#line}
        local pad=""
        if [[ "$_PROVOST_PROGRESS_LAST_LEN" -gt "$cur_len" ]]; then
            printf -v pad '%*s' $((_PROVOST_PROGRESS_LAST_LEN - cur_len)) ""
        fi
        printf '\r%s%s' "$line" "$pad" >&2
        _PROVOST_PROGRESS_LAST_LEN=$cur_len
    else
        # Non-TTY: line-per-tick so log readers can grep the timeline.
        printf '%s\n' "$line" >&2
    fi
}

# Clear the current in-place line so the next stderr write isn't
# stacked onto the progress line. No-op on non-TTY (each tick was its
# own newline-terminated line already).
provost_progress_done () {
    [[ "$_PROVOST_PROGRESS_ARMED" == "1" ]] || return 0
    if [[ "$_PROVOST_PROGRESS_IS_TTY" == "1" ]]; then
        if [[ "$_PROVOST_PROGRESS_LAST_LEN" -gt 0 ]]; then
            local clear=""
            printf -v clear '%*s' "$_PROVOST_PROGRESS_LAST_LEN" ""
            printf '\r%s\r' "$clear" >&2
        fi
    fi
    _PROVOST_PROGRESS_LAST_LEN=0
}
