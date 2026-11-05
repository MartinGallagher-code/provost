#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## provost-extract Test Runner
##
## Runs all test suites and reports combined results.
##
## Usage: bash run_tests.sh [OPTIONS]
##
## Options:
##   --filter PATTERN   Only run test files matching PATTERN
##   --timing           Show elapsed time per test file
##   --fail-fast        Stop on first test file failure
##
## Test files run in parallel under a job pool sized to the CPU count
## (PROVOST_TEST_JOBS overrides it; PROVOST_TEST_JOBS=1 runs them one at a
## time, streaming, as before). Each file's output is held in its own log and
## printed whole, in file order, so the report reads the same either way.
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OVERALL_EXIT=0
FILES_RUN=0
FILES_FAILED=0
FAILED_FILES=()
opt_filter=""
opt_timing=0
opt_fail_fast=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --filter)   opt_filter="$2"; shift 2 ;;
        --timing)   opt_timing=1; shift ;;
        --fail-fast) opt_fail_fast=1; shift ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

echo "========================================"
echo "provost-extract Test Suite"
echo "========================================"

JOBS="${PROVOST_TEST_JOBS:-$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}"
if ! [[ "$JOBS" =~ ^[1-9][0-9]*$ ]]; then
    echo "PROVOST_TEST_JOBS must be a positive integer (got '$JOBS')" >&2; exit 1
fi
# wait -n (bash 4.3+) wakes as soon as any job ends; older bash (macOS's 3.2) polls.
_has_wait_n=0
(( BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 3) )) && _has_wait_n=1
_wait_any () { if [[ $_has_wait_n -eq 1 ]]; then wait -n 2>/dev/null; else sleep 0.1; fi; }

# Auto-discover all test files, then the golden output verification (if no
# filter is set, or the filter matches) as the last entry.
NAMES=(); CMDS=()
for test_file in "$SCRIPT_DIR"/test_*.sh; do
    [[ -f "$test_file" ]] || continue

    # Apply filter if set
    if [[ -n "$opt_filter" ]]; then
        case "$test_file" in
            *"$opt_filter"*) ;;
            *) continue ;;
        esac
    fi
    NAMES+=("$(basename "$test_file")"); CMDS+=("$test_file")
done
if [[ -z "$opt_filter" || "verify_strategy_outputs" == *"$opt_filter"* ]]; then
    NAMES+=("verify_strategy_outputs.sh"); CMDS+=("$SCRIPT_DIR/verify_strategy_outputs.sh")
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/provost-extract-tests.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

_is_verify () { [[ "${NAMES[$1]}" == verify_strategy_outputs.sh ]]; }

# _run I: run entry I. With one job its output streams straight through;
# otherwise it goes to WORK/I.log (and the job's own stderr, which would only
# say "Terminated" after a --fail-fast stop, is dropped). WORK/I.rc is written last, by rename, so
# its presence means the entry has finished.
_run () {
    local _start=$SECONDS _rc=0 _args=()
    [[ -e "$WORK/stop" ]] && ! _is_verify "$1" && return 0
    _is_verify "$1" && _args=(--check)
    if [[ $JOBS -eq 1 ]]; then
        bash "${CMDS[$1]}" "${_args[@]}" || _rc=$?
    else
        bash "${CMDS[$1]}" "${_args[@]}" > "$WORK/$1.log" 2>&1 || _rc=$?
    fi
    echo $((SECONDS - _start)) > "$WORK/$1.t"
    echo "$_rc" > "$WORK/$1.rc.tmp" && mv "$WORK/$1.rc.tmp" "$WORK/$1.rc"
}

# _report I: print entry I's log and timing, and count it. Returns 1 when
# --fail-fast should stop the run.
_report () {
    local _rc
    [[ $JOBS -eq 1 ]] || cat "$WORK/$1.log"
    _rc="$(cat "$WORK/$1.rc")"
    FILES_RUN=$((FILES_RUN + 1))
    if [[ $opt_timing -eq 1 ]] && ! _is_verify "$1"; then
        echo "  [timing] ${NAMES[$1]}: $(cat "$WORK/$1.t")s"
    fi
    if [[ "$_rc" -ne 0 ]]; then
        OVERALL_EXIT=1
        FILES_FAILED=$((FILES_FAILED + 1))
        FAILED_FILES+=("${NAMES[$1]}")
        if [[ $opt_fail_fast -eq 1 ]] && ! _is_verify "$1"; then
            echo ""
            echo "FAIL-FAST: Stopping after ${NAMES[$1]}"
            return 1
        fi
    fi
    return 0
}

# Launch into the pool and print finished entries in order as they come in.
# The golden verification is reported last but, being independent, starts
# first; like the serial run, it is still reported after a --fail-fast stop.
_n=${#NAMES[@]}; _last=$((_n - 1)); _vpid=""
_next=0; _stopped=0
_flush () {
    while [[ $_next -lt $_n && -f "$WORK/$_next.rc" ]]; do
        _report "$_next" || { _stopped=1; return; }
        _next=$((_next + 1))
    done
}
if [[ $JOBS -gt 1 && $_n -gt 0 ]] && _is_verify "$_last"; then
    _run "$_last" 2>/dev/null & _vpid=$!
fi
for (( _i = 0; _i < _n; _i++ )); do
    [[ -n "$_vpid" && $_i -eq $_last ]] && break
    _flush; [[ $_stopped -eq 1 ]] && break
    if [[ $JOBS -eq 1 ]]; then
        _run "$_i"
    else
        _run "$_i" 2>/dev/null &
        while [[ "$(jobs -rp | wc -l)" -ge "$JOBS" ]]; do _wait_any; done
    fi
done
if [[ $_stopped -eq 1 ]]; then
    # --fail-fast: stop the test files still running (a job not yet started
    # sees the stop file and skips its test), but let the golden
    # verification finish and report it. The jobs themselves are left to
    # exit as their test does, so the final wait sees nothing left behind.
    : > "$WORK/stop"
    _kill_tree () { local _c; for _c in $(pgrep -P "$1"); do _kill_tree "$_c"; done; kill -TERM "$1" 2>/dev/null; }
    for _p in $(jobs -p); do
        [[ "$_p" == "$_vpid" ]] && continue
        for _c in $(pgrep -P "$_p"); do _kill_tree "$_c"; done
    done
    if _is_verify "$_last" && [[ $_next -lt $_last ]]; then
        [[ -z "$_vpid" ]] && _run "$_last"
        wait "$_vpid" 2>/dev/null
        _report "$_last" || true
    fi
else
    while [[ $_next -lt $_n ]]; do
        _flush
        [[ $_next -lt $_n ]] && _wait_any
    done
fi
wait 2>/dev/null

echo ""
echo "========================================"
echo "Overall: $((FILES_RUN - FILES_FAILED))/$FILES_RUN test files passed"
if [[ $FILES_FAILED -gt 0 ]]; then
    echo "Failed files:"
    for f in "${FAILED_FILES[@]}"; do
        echo "  - $f"
    done
    echo "========================================"
    echo "Some test suites had failures."
else
    echo "========================================"
    echo "All test suites passed."
fi

exit $OVERALL_EXIT
