#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Tests for: empty / header-only stdin handling (ENV-129)
##
## Regression cover: before ENV-129, running `provost-analyze < /dev/null`
## or any upstream pipeline that produced zero bytes crashed with
##   line 701: COL_NAMES[$((col_idx-1))]: unbound variable
## because the empty-stdin guard only fired when stdin was a TTY.
##
## The fix adds a post-header-read check: if COL_COUNT is 0 the input
## had no header, if ROW_COUNT is 0 the input had only a header. Both
## cases exit non-zero with a user-readable message that does NOT leak
## the internal "unbound variable" text.
################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo "=== Empty-Input Handling (ENV-129) ==="

_check_empty_input () {
    local desc="$1" input="$2" expected_needle="$3"
    local output rc=0
    output=$(printf '%s' "$input" | bash "$MDA_SCRIPT" 2>&1) || rc=$?
    if [[ $rc -eq 0 ]]; then
        echo -e "  ${RED}ASSERT FAILED${NC}: $desc — expected non-zero exit, got 0"
        echo "    output: $output"
        return 1
    fi
    assert_contains "$output" "$expected_needle" "$desc — user-friendly message" || return 1
    assert_not_contains "$output" "unbound variable" "$desc — no 'unbound variable' leak" || return 1
    assert_not_contains "$output" "COL_NAMES" "$desc — no 'COL_NAMES' leak" || return 1
    return 0
}

test_empty_stdin_dev_null () {
    # provost-analyze < /dev/null  — the original ticket repro.
    local output rc=0
    output=$(bash "$MDA_SCRIPT" < /dev/null 2>&1) || rc=$?
    if [[ $rc -eq 0 ]]; then
        echo -e "  ${RED}ASSERT FAILED${NC}: /dev/null stdin — expected non-zero exit, got 0"
        return 1
    fi
    assert_contains "$output" "Input contained no data" "user-friendly message" || return 1
    assert_not_contains "$output" "unbound variable" "no unbound-variable leak" || return 1
    assert_not_contains "$output" "COL_NAMES" "no COL_NAMES leak" || return 1
}

test_empty_stdin_zero_bytes () {
    # Zero bytes on a pipe (`printf '' | provost-analyze`).
    _check_empty_input "zero-byte pipe" "" "Input contained no data"
}

test_header_only_no_rows () {
    # Header line present, zero data rows. Previously rendered a bogus
    # "Rows: 0" dashboard; now exits non-zero with a clear message.
    _check_empty_input "header-only pipe" "col1,col2"$'\n' "no data rows"
}

test_header_only_tsv () {
    # Same path for a TSV header to make sure the delimiter-detection
    # branch takes the same guard.
    _check_empty_input "header-only TSV" $'a\tb\tc\n' "no data rows"
}

test_empty_file_arg () {
    # Empty file passed as a path argument also hits the same code path.
    local f
    f=$(mktemp)
    local output rc=0
    output=$(bash "$MDA_SCRIPT" "$f" 2>&1) || rc=$?
    rm -f "$f"
    if [[ $rc -eq 0 ]]; then
        echo -e "  ${RED}ASSERT FAILED${NC}: empty file arg — expected non-zero exit, got 0"
        return 1
    fi
    assert_contains "$output" "Input contained no data" "user-friendly message" || return 1
    assert_not_contains "$output" "unbound variable" "no unbound-variable leak" || return 1
}

test_valid_data_still_works () {
    # Regression guard: a real dataset still parses and exits 0.
    local output rc=0
    output=$(bash "$MDA_SCRIPT" "$SAMPLES_DIR/anscombe.csv" 2>&1) || rc=$?
    assert_exit_zero "$rc" "valid dataset should succeed"
    assert_contains "$output" "Rows:" "valid dataset should render stats"
}

run_test "empty stdin via < /dev/null" test_empty_stdin_dev_null
run_test "empty stdin via zero-byte pipe" test_empty_stdin_zero_bytes
run_test "header-only CSV pipe" test_header_only_no_rows
run_test "header-only TSV pipe" test_header_only_tsv
run_test "empty file passed as argument" test_empty_file_arg
run_test "valid dataset still works" test_valid_data_still_works

print_summary
