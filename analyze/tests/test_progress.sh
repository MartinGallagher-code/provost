#!/bin/bash
################################################################################
## Tests for: ENV-135 progress indicator in envoy-analyze.
##
## Mirrors EnvoyExtract/tests/test_progress.sh but for the per-column
## stats stage. The shared helper at lib/envoy_progress.sh is the same
## code path; we re-test here to pin the analyze-side wiring.
################################################################################
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

EA="$(cd "$SCRIPT_DIR/.." && pwd)/envoy-analyze"
SAMPLE="$SAMPLES_DIR/biostats.csv"

# Wrapper that suppresses the unrelated awk/gawk warnings so progress
# parsing works even with mawk in CI.
_run_ea () {
    ENVOY_ANALYZE_SUPPRESS_AWK_WARNING=1 "$@"
}

################################################################################
## --progress emits per-column lines on stderr (non-TTY path)
################################################################################

test_progress_per_column_lines () {
    local err rc=0
    err=$(_run_ea bash "$EA" --progress "$SAMPLE" 2>&1 >/dev/null) || rc=$?
    assert_exit_zero "$rc" "analyze should still succeed with --progress"
    # `[n/N] stats: <colname>` is the per-column tick format.
    if ! grep -qE '^\[[0-9]+/[0-9]+\] stats: ' <<< "$err"; then
        echo "  ASSERT FAILED: --progress should emit '[n/N] stats: <col>' lines"
        echo "  stderr (first 200): $(printf '%s' "$err" | head -c 200)"
        return 1
    fi
}

################################################################################
## TTY mode uses CR for in-place updates
################################################################################

test_progress_uses_cr_on_tty () {
    local err rc=0
    err=$(ENVOY_PROGRESS_FORCE_TTY=1 _run_ea bash "$EA" --progress "$SAMPLE" 2>&1 >/dev/null) || rc=$?
    assert_exit_zero "$rc" "analyze should still succeed with TTY-forced progress"
    if [[ "$err" != *$'\r'* ]]; then
        echo "  ASSERT FAILED: TTY progress should contain a CR for in-place updates"
        return 1
    fi
}

################################################################################
## Suppression knobs
################################################################################

test_no_progress_suppresses () {
    local err rc=0
    err=$(ENVOY_PROGRESS_FORCE_TTY=1 _run_ea bash "$EA" --no-progress "$SAMPLE" 2>&1 >/dev/null) || rc=$?
    if grep -qE '^\[[0-9]+/[0-9]+\] stats:' <<< "$err"; then
        echo "  ASSERT FAILED: --no-progress should suppress ticks"
        return 1
    fi
}

test_envoy_no_progress_beats_progress () {
    local err rc=0
    err=$(ENVOY_PROGRESS_FORCE_TTY=1 ENVOY_NO_PROGRESS=1 _run_ea bash "$EA" --progress "$SAMPLE" 2>&1 >/dev/null) || rc=$?
    if grep -qE '^\[[0-9]+/[0-9]+\] stats:' <<< "$err"; then
        echo "  ASSERT FAILED: ENVOY_NO_PROGRESS=1 should beat --progress"
        return 1
    fi
}

test_envoy_quiet_suppresses () {
    local err rc=0
    err=$(ENVOY_PROGRESS_FORCE_TTY=1 _run_ea bash "$EA" --quiet --progress "$SAMPLE" 2>&1 >/dev/null) || rc=$?
    if grep -qE '^\[[0-9]+/[0-9]+\] stats:' <<< "$err"; then
        echo "  ASSERT FAILED: --quiet should suppress progress"
        return 1
    fi
}

################################################################################
## Default (non-TTY, no flag, small file) emits nothing
################################################################################

test_default_non_tty_silent () {
    # No flag and no forced TTY → biostats.csv (5 columns) should be silent.
    local err rc=0
    err=$(_run_ea bash "$EA" "$SAMPLE" 2>&1 >/dev/null) || rc=$?
    if grep -qE '^\[[0-9]+/[0-9]+\] stats:' <<< "$err"; then
        echo "  ASSERT FAILED: default (no flag, non-TTY) should not emit progress"
        return 1
    fi
}

################################################################################
## Below the 20-column threshold, default-on-TTY also stays silent
################################################################################

test_below_threshold_silent_on_tty () {
    # biostats.csv has 5 columns — below the 20-column auto threshold.
    # On a forced TTY without --progress, no ticks should appear.
    local err rc=0
    err=$(ENVOY_PROGRESS_FORCE_TTY=1 _run_ea bash "$EA" "$SAMPLE" 2>&1 >/dev/null) || rc=$?
    if grep -qE '^\[[0-9]+/[0-9]+\] stats:' <<< "$err"; then
        echo "  ASSERT FAILED: small input (5 cols < 20) should not emit progress on TTY without --progress"
        return 1
    fi
}

################################################################################
## Stdout payload is byte-identical with / without progress
################################################################################

test_progress_does_not_alter_stdout () {
    local with without
    with=$(_run_ea bash "$EA" --progress "$SAMPLE" 2>/dev/null)
    without=$(_run_ea bash "$EA" --no-progress "$SAMPLE" 2>/dev/null)
    if [[ "$with" != "$without" ]]; then
        echo "  ASSERT FAILED: --progress altered stdout payload"
        return 1
    fi
}

################################################################################
## --help advertises both flags
################################################################################

test_help_documents_progress () {
    local out
    out=$(bash "$EA" --help 2>&1)
    assert_contains "$out" "--progress" "--help must advertise --progress"
    assert_contains "$out" "--no-progress" "--help must advertise --no-progress"
}

run_test "ENV-135 --progress emits per-column [n/N] lines" test_progress_per_column_lines
run_test "ENV-135 TTY progress uses carriage return" test_progress_uses_cr_on_tty
run_test "ENV-135 --no-progress suppresses ticks" test_no_progress_suppresses
run_test "ENV-135 ENVOY_NO_PROGRESS=1 beats --progress" test_envoy_no_progress_beats_progress
run_test "ENV-135 --quiet suppresses progress" test_envoy_quiet_suppresses
run_test "ENV-135 default (non-TTY, no flag) silent" test_default_non_tty_silent
run_test "ENV-135 below 20-col threshold silent on TTY without --progress" test_below_threshold_silent_on_tty
run_test "ENV-135 --progress does not alter stdout payload" test_progress_does_not_alter_stdout
run_test "ENV-135 --help advertises --progress / --no-progress" test_help_documents_progress

print_summary
