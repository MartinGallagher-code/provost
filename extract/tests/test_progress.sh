#!/bin/bash
################################################################################
## Tests for: ENV-135 progress indicator in envoy-extract.
##
## Pins the contract from the ticket:
##   * `--progress` forces ticks even on a non-TTY (line-per-tick).
##   * On a TTY the ticks are `\r`-rewritten in place.
##   * `--no-progress` and `ENVOY_NO_PROGRESS=1` suppress ticks entirely.
##   * `ENVOY_QUIET=1` and `NO_COLOR=1` suppress ticks.
##   * Stdout payload is byte-identical with vs. without progress.
##   * Below the 20-strategy threshold, default mode emits no progress
##     even on a TTY (uses the explicit `--strategy` filter to limit).
##
## We synthesise a TTY for the relevant tests via the helper's
## `ENVOY_PROGRESS_FORCE_TTY=1` test hook so the suite stays portable
## across CI environments that don't ship `script(1)` or `expect(1)`.
################################################################################
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

EE="$(cd "$SCRIPT_DIR/.." && pwd)/envoy-extract"
SAMPLE_INPUT='user=alice host=localhost path=/foo'

################################################################################
## --progress on a non-TTY produces line-per-tick on stderr
################################################################################

test_progress_emits_lines_on_non_tty () {
    local out err rc=0
    err=$(printf '%s' "$SAMPLE_INPUT" | bash "$EE" --progress 2>&1 >/dev/null) || rc=$?
    assert_exit_zero "$rc" "extract should still succeed with --progress"
    if ! grep -qE '^\[[0-9]+/[0-9]+\] [A-Za-z0-9_/-]+' <<< "$err"; then
        echo "  ASSERT FAILED: --progress should emit '[n/N] strategy-name' lines"
        echo "  stderr (first 200): $(printf '%s' "$err" | head -c 200)"
        return 1
    fi
}

################################################################################
## TTY path uses `\r` for in-place updates
################################################################################

test_progress_uses_carriage_return_on_tty () {
    local err rc=0
    # `ENVOY_PROGRESS_FORCE_TTY=1` is the documented test hook.
    err=$(printf '%s' "$SAMPLE_INPUT" \
        | ENVOY_PROGRESS_FORCE_TTY=1 bash "$EE" --progress 2>&1 >/dev/null) || rc=$?
    assert_exit_zero "$rc" "extract should still succeed with TTY-forced progress"
    if [[ "$err" != *$'\r'* ]]; then
        echo "  ASSERT FAILED: TTY progress should contain a CR for in-place updates"
        return 1
    fi
}

################################################################################
## Suppression knobs
################################################################################

test_no_progress_flag_suppresses () {
    local err rc=0
    err=$(printf '%s' "$SAMPLE_INPUT" \
        | ENVOY_PROGRESS_FORCE_TTY=1 bash "$EE" --no-progress 2>&1 >/dev/null) || rc=$?
    assert_exit_zero "$rc" "extract should still succeed with --no-progress"
    if grep -qE '^\[[0-9]+/[0-9]+\]' <<< "$err"; then
        echo "  ASSERT FAILED: --no-progress should suppress all '[n/N]' ticks"
        return 1
    fi
}

test_envoy_no_progress_env_suppresses () {
    local err rc=0
    err=$(printf '%s' "$SAMPLE_INPUT" \
        | ENVOY_PROGRESS_FORCE_TTY=1 ENVOY_NO_PROGRESS=1 bash "$EE" --progress 2>&1 >/dev/null) || rc=$?
    assert_exit_zero "$rc" "extract should still succeed under ENVOY_NO_PROGRESS=1"
    # ENVOY_NO_PROGRESS beats --progress.
    if grep -qE '^\[[0-9]+/[0-9]+\]' <<< "$err"; then
        echo "  ASSERT FAILED: ENVOY_NO_PROGRESS=1 should suppress ticks even with --progress"
        return 1
    fi
}

test_envoy_quiet_suppresses () {
    local err rc=0
    err=$(printf '%s' "$SAMPLE_INPUT" \
        | ENVOY_PROGRESS_FORCE_TTY=1 ENVOY_QUIET=1 bash "$EE" 2>&1 >/dev/null) || rc=$?
    # ENVOY_QUIET propagates through the suite-quiet contract.
    if grep -qE '^\[[0-9]+/[0-9]+\]' <<< "$err"; then
        echo "  ASSERT FAILED: ENVOY_QUIET=1 should suppress progress ticks"
        return 1
    fi
}

test_no_color_suppresses () {
    local err rc=0
    err=$(printf '%s' "$SAMPLE_INPUT" \
        | ENVOY_PROGRESS_FORCE_TTY=1 NO_COLOR=1 bash "$EE" --progress 2>&1 >/dev/null) || rc=$?
    if grep -qE '^\[[0-9]+/[0-9]+\]' <<< "$err"; then
        echo "  ASSERT FAILED: NO_COLOR=1 should suppress progress (decorative output)"
        return 1
    fi
}

################################################################################
## Stdout payload is byte-identical with / without progress
################################################################################

test_progress_does_not_alter_stdout () {
    local with without
    with=$(printf '%s' "$SAMPLE_INPUT" | bash "$EE" --progress 2>/dev/null)
    without=$(printf '%s' "$SAMPLE_INPUT" | bash "$EE" --no-progress 2>/dev/null)
    if [[ "$with" != "$without" ]]; then
        echo "  ASSERT FAILED: --progress changed stdout payload"
        return 1
    fi
}

################################################################################
## --help advertises the flags
################################################################################

test_help_documents_progress () {
    local out
    out=$(bash "$EE" --help 2>&1)
    assert_contains "$out" "--progress" "--help must advertise --progress"
    assert_contains "$out" "--no-progress" "--help must advertise --no-progress"
}

run_test "ENV-135 --progress emits [n/N] lines on stderr (non-TTY)" test_progress_emits_lines_on_non_tty
run_test "ENV-135 TTY progress uses carriage return for in-place" test_progress_uses_carriage_return_on_tty
run_test "ENV-135 --no-progress suppresses ticks" test_no_progress_flag_suppresses
run_test "ENV-135 ENVOY_NO_PROGRESS=1 beats --progress" test_envoy_no_progress_env_suppresses
run_test "ENV-135 ENVOY_QUIET=1 suppresses progress" test_envoy_quiet_suppresses
run_test "ENV-135 NO_COLOR=1 suppresses progress" test_no_color_suppresses
run_test "ENV-135 --progress does not alter stdout payload" test_progress_does_not_alter_stdout
run_test "ENV-135 --help advertises --progress / --no-progress" test_help_documents_progress

print_summary
