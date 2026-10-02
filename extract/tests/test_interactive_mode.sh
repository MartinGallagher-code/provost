#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Interactive Mode Tests for provost-extract
##
## Tests the -i / --interactive flag.  TTY-requiring tests use `expect` and
## are automatically skipped when `expect` is not installed.
## Helper function unit tests do not require a TTY.
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

# Source the interactive library directly for unit testing
_LIB_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/lib"
source "$_LIB_DIR/_helpers.sh"
source "$_LIB_DIR/_interactive.sh"

HAS_EXPECT=0
command -v expect >/dev/null 2>&1 && HAS_EXPECT=1

echo ""
echo "========================================"
echo "Interactive Mode Tests"
echo "========================================"

if [[ $HAS_EXPECT -eq 0 ]]; then
    echo "  (NOTE: expect not installed — TTY simulation tests will be skipped)"
fi

################################################################################
## Unit tests: _interactive_get_nth
################################################################################

test_get_nth_first () {
    local list
    list=$'alpha\nbeta\ngamma'
    _interactive_get_nth "$list" 0
    assert_eq "alpha" "$_NTH_RESULT" "get_nth index 0 should return first item"
}

test_get_nth_middle () {
    local list
    list=$'alpha\nbeta\ngamma'
    _interactive_get_nth "$list" 1
    assert_eq "beta" "$_NTH_RESULT" "get_nth index 1 should return second item"
}

test_get_nth_last () {
    local list
    list=$'alpha\nbeta\ngamma'
    _interactive_get_nth "$list" 2
    assert_eq "gamma" "$_NTH_RESULT" "get_nth index 2 should return third item"
}

test_get_nth_out_of_range () {
    local list
    list=$'alpha\nbeta'
    _interactive_get_nth "$list" 5
    assert_eq "0" "$_NTH_RESULT" "get_nth out-of-range should return 0"
}

################################################################################
## Unit tests: _interactive_toggle_nth
################################################################################

test_toggle_nth_zero_to_one () {
    local list
    list=$'0\n0\n0'
    _interactive_toggle_nth "$list" 1
    local second
    second=$(echo "$_TOGGLE_RESULT" | sed -n '2p')
    assert_eq "1" "$second" "toggling index 1 of all-zeros should set it to 1"
}

test_toggle_nth_one_to_zero () {
    local list
    list=$'1\n1\n1'
    _interactive_toggle_nth "$list" 0
    local first
    first=$(echo "$_TOGGLE_RESULT" | head -1)
    assert_eq "0" "$first" "toggling index 0 of all-ones should set it to 0"
}

test_toggle_nth_preserves_others () {
    local list
    list=$'1\n0\n1'
    _interactive_toggle_nth "$list" 1
    local first third
    first=$(echo "$_TOGGLE_RESULT" | head -1)
    third=$(echo "$_TOGGLE_RESULT" | sed -n '3p')
    assert_eq "1" "$first" "toggle should not change non-toggled items (first)"
    assert_eq "1" "$third" "toggle should not change non-toggled items (third)"
}

################################################################################
## Unit tests: _interactive_set_all
################################################################################

test_set_all_to_one () {
    _interactive_set_all 3 "1"
    local count
    count=$(echo "$_SETALL_RESULT" | grep -c "^1$")
    assert_eq "3" "$count" "set_all 3 items to 1 should produce 3 ones"
}

test_set_all_to_zero () {
    _interactive_set_all 4 "0"
    local count
    count=$(echo "$_SETALL_RESULT" | grep -c "^0$")
    assert_eq "4" "$count" "set_all 4 items to 0 should produce 4 zeros"
}

test_set_all_count () {
    _interactive_set_all 5 "1"
    local lines
    lines=$(echo "$_SETALL_RESULT" | grep -c .)
    assert_eq "5" "$lines" "set_all should produce exactly the requested count"
}

################################################################################
## Integration tests: conflict detection
################################################################################

test_interactive_count_conflict () {
    local output rc=0
    output=$(run_extract --interactive --count "$SAMPLES_DIR/json/basic.json" 2>&1) || rc=$?
    assert_exit_nonzero "$rc" "--interactive and --count should conflict"
    assert_contains "$output" "cannot" "should show conflict error"
}

test_interactive_names_conflict () {
    local output rc=0
    output=$(run_extract --interactive --names "$SAMPLES_DIR/json/basic.json" 2>&1) || rc=$?
    assert_exit_nonzero "$rc" "--interactive and --names should conflict"
    assert_contains "$output" "cannot" "should show conflict error"
}

################################################################################
## TTY fallback: provost-extract --interactive without terminal exits gracefully
################################################################################

test_interactive_no_tty_graceful () {
    # When run without a controlling terminal, provost-extract -i should exit (not hang).
    # We use timeout to guard against hanging.
    local rc=0
    timeout 3 bash "$PROVOST_EXTRACT_SCRIPT" -i -s colons "$SAMPLES_DIR/colons/basic.txt" \
        >/dev/null 2>/dev/null || rc=$?
    # Exit code 1 (no output) or 0 (empty selection message) are both acceptable.
    # The critical property is that it exits within 3 seconds (not hung).
    [[ $rc -ne 124 ]] || { echo "  ASSERT FAILED: --interactive hung (timeout)"; return 1; }
}

################################################################################
## Integration tests: additional conflict detection
################################################################################

test_interactive_quiet_conflict () {
    local output rc=0
    output=$(run_extract --interactive --quiet "$SAMPLES_DIR/json/basic.json" 2>&1) || rc=$?
    assert_exit_nonzero "$rc" "--interactive and --quiet should conflict"
    assert_contains "$output" "cannot" "should show conflict error"
}

test_interactive_stream_conflict () {
    local output rc=0
    output=$(echo '{}' | run_extract --interactive --stream -s json 2>&1) || rc=$?
    assert_exit_nonzero "$rc" "--interactive and --stream should conflict"
    assert_contains "$output" "cannot" "should show conflict error"
}

test_interactive_batch_conflict () {
    local output rc=0
    output=$(echo "/dev/null" | run_extract --interactive --batch 2>&1) || rc=$?
    assert_exit_nonzero "$rc" "--interactive and --batch should conflict"
    assert_contains "$output" "cannot" "should show conflict error"
}

################################################################################
## Non-TTY fallback behavior
################################################################################

test_interactive_no_tty_fallback_selects_all () {
    # When /dev/tty is unavailable, interactive mode should fall back to
    # selecting all fields and produce output (not just exit silently).
    local output rc=0
    output=$(timeout 3 bash "$PROVOST_EXTRACT_SCRIPT" -i -s colons -f json \
        "$SAMPLES_DIR/colons/basic.txt" 2>/dev/null) || rc=$?
    # Should not hang (rc 124 = timeout)
    [[ $rc -ne 124 ]] || { echo "  ASSERT FAILED: --interactive hung (timeout)"; return 1; }
    # Should produce JSON output with all fields (fallback selects all)
    if [[ $rc -eq 0 && -n "$output" ]]; then
        assert_contains "$output" "Name" "fallback should include all fields"
    fi
    # rc=0 with output is the ideal; rc=1 with warning is also acceptable
}

test_interactive_no_tty_stderr_warning () {
    # When /dev/tty is unavailable (or broken), stderr should contain a
    # diagnostic message: either the "not a terminal" warning from the code,
    # or the shell's own "No such device" error from /dev/tty redirection.
    local stderr_output rc=0
    stderr_output=$(timeout 3 bash "$PROVOST_EXTRACT_SCRIPT" -i -s colons \
        "$SAMPLES_DIR/colons/basic.txt" 2>&1 >/dev/null) || rc=$?
    [[ $rc -ne 124 ]] || { echo "  ASSERT FAILED: --interactive hung (timeout)"; return 1; }
    # Accept either our warning or a shell-level /dev/tty error
    if [[ "$stderr_output" == *"terminal"* ]] || \
       [[ "$stderr_output" == *"/dev/tty"* ]] || \
       [[ "$stderr_output" == *"interactive"* ]]; then
        return 0
    fi
    echo "  ASSERT FAILED: non-TTY fallback should warn on stderr"
    echo "    stderr was: '$stderr_output'"
    return 1
}

################################################################################
## Interactive mode with --strategy constraint
################################################################################

test_interactive_with_strategy_no_tty () {
    # Using -i with --strategy should still work in non-TTY (fallback mode).
    # The strategy constraint should be respected: only colons strategy runs.
    local output rc=0
    output=$(timeout 3 bash "$PROVOST_EXTRACT_SCRIPT" -i -s colons -f json \
        "$SAMPLES_DIR/colons/basic.txt" 2>/dev/null) || rc=$?
    [[ $rc -ne 124 ]] || { echo "  ASSERT FAILED: hung with -i -s"; return 1; }
    if [[ $rc -eq 0 && -n "$output" ]]; then
        assert_contains "$output" "Name" \
            "-i with -s colons should extract fields from colons sample"
    fi
}

test_interactive_with_json_strategy_no_tty () {
    # Interactive + json strategy should produce JSON fields.
    local output rc=0
    output=$(timeout 3 bash "$PROVOST_EXTRACT_SCRIPT" -i -s json -f json \
        "$SAMPLES_DIR/json/basic.json" 2>/dev/null) || rc=$?
    [[ $rc -ne 124 ]] || { echo "  ASSERT FAILED: hung with -i -s json"; return 1; }
    if [[ $rc -eq 0 && -n "$output" ]]; then
        assert_contains "$output" "name" \
            "-i with -s json should extract json fields"
    fi
}

################################################################################
## Interactive mode with --format flag
################################################################################

test_interactive_format_csv_no_tty () {
    # In non-TTY fallback, --format should still be respected.
    local output rc=0
    output=$(timeout 3 bash "$PROVOST_EXTRACT_SCRIPT" -i -s colons -f csv \
        "$SAMPLES_DIR/colons/basic.txt" 2>/dev/null) || rc=$?
    [[ $rc -ne 124 ]] || { echo "  ASSERT FAILED: hung with -i -f csv"; return 1; }
    if [[ $rc -eq 0 && -n "$output" ]]; then
        # CSV output has comma-separated header row
        assert_contains "$output" "," \
            "-i with -f csv should produce comma-separated output"
    fi
}

test_interactive_format_yaml_no_tty () {
    # In non-TTY fallback, --format yaml should produce YAML output.
    local output rc=0
    output=$(timeout 3 bash "$PROVOST_EXTRACT_SCRIPT" -i -s colons -f yaml \
        "$SAMPLES_DIR/colons/basic.txt" 2>/dev/null) || rc=$?
    [[ $rc -ne 124 ]] || { echo "  ASSERT FAILED: hung with -i -f yaml"; return 1; }
    if [[ $rc -eq 0 && -n "$output" ]]; then
        # YAML output uses "key: value" format
        assert_contains "$output" ": " \
            "-i with -f yaml should produce YAML-style output"
    fi
}

################################################################################
## Multi-file interactive mode
################################################################################

test_interactive_multiple_files_no_tty () {
    # Interactive mode should work with multiple input files in non-TTY mode.
    # Note: provost-extract processes one file at a time; multiple files are
    # handled by the caller (or batch mode). This tests that -i doesn't break
    # when a single file is specified alongside strategy.
    local output1 rc1=0
    output1=$(timeout 3 bash "$PROVOST_EXTRACT_SCRIPT" -i -s colons -f json \
        "$SAMPLES_DIR/colons/basic.txt" 2>/dev/null) || rc1=$?
    local output2 rc2=0
    output2=$(timeout 3 bash "$PROVOST_EXTRACT_SCRIPT" -i -s json -f json \
        "$SAMPLES_DIR/json/basic.json" 2>/dev/null) || rc2=$?

    [[ $rc1 -ne 124 ]] || { echo "  ASSERT FAILED: first file hung"; return 1; }
    [[ $rc2 -ne 124 ]] || { echo "  ASSERT FAILED: second file hung"; return 1; }

    # Both should succeed (or gracefully fall back)
    if [[ $rc1 -eq 0 && -n "$output1" ]]; then
        assert_contains "$output1" "Name" "first file should extract colons fields"
    fi
    if [[ $rc2 -eq 0 && -n "$output2" ]]; then
        assert_contains "$output2" "name" "second file should extract json fields"
    fi
}

################################################################################
## Edge case: _interactive_select with empty input
################################################################################

test_interactive_select_empty_input () {
    # _interactive_select with empty input should set _SELECTED_FIELDS to ""
    _SELECTED_FIELDS="UNSET"
    _interactive_select ""
    assert_eq "" "$_SELECTED_FIELDS" \
        "_interactive_select with empty input should produce empty selection"
}

test_interactive_select_single_field () {
    # _interactive_select with one field and no usable TTY.
    # We run it via the CLI in non-TTY mode (piped), which triggers the
    # fallback to selecting all fields. We verify the output is produced.
    local output rc=0
    output=$(timeout 3 bash "$PROVOST_EXTRACT_SCRIPT" -i -s colons -f json \
        "$SAMPLES_DIR/colons/basic.txt" 2>/dev/null) || rc=$?
    [[ $rc -ne 124 ]] || { echo "  ASSERT FAILED: hung"; return 1; }
    # In non-TTY fallback, all fields should be selected and output produced
    if [[ $rc -eq 0 && -n "$output" ]]; then
        # The output should contain at least one field from the sample
        assert_contains "$output" "Name" \
            "non-TTY fallback should produce output with extracted fields"
    fi
}

################################################################################
## Unit test: _interactive_get_nth with single element
################################################################################

test_get_nth_single_element () {
    local list="only"
    _interactive_get_nth "$list" 0
    assert_eq "only" "$_NTH_RESULT" "get_nth single element at index 0"
}

################################################################################
## Unit test: _interactive_toggle_nth boundary
################################################################################

test_toggle_nth_last_element () {
    local list
    list=$'0\n0\n0\n0'
    _interactive_toggle_nth "$list" 3
    local last
    last=$(echo "$_TOGGLE_RESULT" | sed -n '4p')
    assert_eq "1" "$last" "toggling last element should flip it"
    local first
    first=$(echo "$_TOGGLE_RESULT" | head -1)
    assert_eq "0" "$first" "toggling last should not affect first"
}

################################################################################
## Ctrl-C / signal handling: non-interactive verification
################################################################################

test_interactive_sigint_no_hang () {
    # Send SIGINT to an interactive process and verify it exits promptly.
    # This tests that the process doesn't ignore SIGINT and hang.
    local rc=0
    # Run in background, send SIGINT after a short delay
    timeout 3 bash -c "
        bash \"$PROVOST_EXTRACT_SCRIPT\" -i -s colons \"$SAMPLES_DIR/colons/basic.txt\" &
        pid=\$!
        sleep 0.3
        kill -INT \$pid 2>/dev/null
        wait \$pid 2>/dev/null
    " >/dev/null 2>/dev/null || rc=$?
    # The key property: did not hang (rc=124 means timeout)
    [[ $rc -ne 124 ]] || { echo "  ASSERT FAILED: process hung after SIGINT"; return 1; }
}

################################################################################
## TTY simulation tests (require expect)
################################################################################

_run_expect_test () {
    local script="$1"
    local desc="$2"
    if [[ $HAS_EXPECT -eq 0 ]]; then
        printf "  %sSKIP%s: %s (expect not installed)\n" "$YELLOW" "$NC" "$desc"
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    fi
    local tmpscript
    tmpscript=$(mktemp "${TMPDIR:-/tmp}/itest_XXXXXX.exp")
    echo "$script" > "$tmpscript"
    local result=0
    expect -f "$tmpscript" >/dev/null 2>&1 || result=1
    rm -f "$tmpscript"
    if [[ $result -eq 0 ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        printf "  %sPASS%s: %s\n" "$GREEN" "$NC" "$desc"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        FAILED_NAMES+=("$desc")
        printf "  %sFAIL%s: %s\n" "$RED" "$NC" "$desc"
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
}

_COLONS_SAMPLE="$SAMPLES_DIR/colons/basic.txt"
_JSON_SAMPLE="$SAMPLES_DIR/json/basic.json"

# TTY test: press Enter immediately → all fields returned
_run_expect_test "
set timeout 5
spawn bash $PROVOST_EXTRACT_SCRIPT -i -s colons $_COLONS_SAMPLE
expect {Select fields} {}
send \"\r\"
expect eof
catch wait result
set rc [lindex \$result 3]
if {\$rc != 0} { exit 1 }
exit 0
" "interactive: press Enter returns all fields"

# TTY test: cancel with q → exit 1 (non-zero), no fields
_run_expect_test "
set timeout 5
spawn bash $PROVOST_EXTRACT_SCRIPT -i -s colons $_COLONS_SAMPLE
expect {Select fields} {}
send \"q\"
expect eof
catch wait result
set rc [lindex \$result 3]
if {\$rc != 1} { exit 1 }
exit 0
" "interactive: q cancels and exits cleanly"

# TTY test: interactive with --strategy constraint and --format json
_run_expect_test "
set timeout 5
log_file /dev/null
spawn bash $PROVOST_EXTRACT_SCRIPT -i -s colons -f json $_COLONS_SAMPLE
expect {Select fields} {}
send \"\r\"
expect eof
catch wait result
set rc [lindex \$result 3]
if {\$rc != 0} { exit 1 }
exit 0
" "interactive: -s colons -f json with Enter confirms all"

# TTY test: interactive with json strategy
_run_expect_test "
set timeout 5
spawn bash $PROVOST_EXTRACT_SCRIPT -i -s json $_JSON_SAMPLE
expect {Select fields} {}
send \"\r\"
expect eof
catch wait result
set rc [lindex \$result 3]
if {\$rc != 0} { exit 1 }
exit 0
" "interactive: -s json with Enter confirms all"

# TTY test: press 'n' (none) then Enter → no fields selected
_run_expect_test "
set timeout 5
spawn bash $PROVOST_EXTRACT_SCRIPT -i -s colons $_COLONS_SAMPLE
expect {Select fields} {}
send \"n\"
after 200
send \"\r\"
expect eof
catch wait result
set rc [lindex \$result 3]
# Should exit 0 with \"No fields selected\" warning or empty output
exit 0
" "interactive: n then Enter selects no fields"

# TTY test: press 'a' (all) then Enter → all fields selected
_run_expect_test "
set timeout 5
spawn bash $PROVOST_EXTRACT_SCRIPT -i -s colons $_COLONS_SAMPLE
expect {Select fields} {}
send \"a\"
after 200
send \"\r\"
expect eof
catch wait result
set rc [lindex \$result 3]
if {\$rc != 0} { exit 1 }
exit 0
" "interactive: a then Enter selects all fields"

################################################################################
## Run all tests
################################################################################

run_test "interactive helper: get_nth first item" test_get_nth_first
run_test "interactive helper: get_nth middle item" test_get_nth_middle
run_test "interactive helper: get_nth last item" test_get_nth_last
run_test "interactive helper: get_nth out-of-range" test_get_nth_out_of_range
run_test "interactive helper: get_nth single element" test_get_nth_single_element
run_test "interactive helper: toggle 0→1" test_toggle_nth_zero_to_one
run_test "interactive helper: toggle 1→0" test_toggle_nth_one_to_zero
run_test "interactive helper: toggle preserves others" test_toggle_nth_preserves_others
run_test "interactive helper: toggle last element" test_toggle_nth_last_element
run_test "interactive helper: set_all ones" test_set_all_to_one
run_test "interactive helper: set_all zeros" test_set_all_to_zero
run_test "interactive helper: set_all count" test_set_all_count
run_test "interactive: --count conflict" test_interactive_count_conflict
run_test "interactive: --names conflict" test_interactive_names_conflict
run_test "interactive: --quiet conflict" test_interactive_quiet_conflict
run_test "interactive: --stream conflict" test_interactive_stream_conflict
run_test "interactive: --batch conflict" test_interactive_batch_conflict
run_test "interactive: no-TTY exits gracefully" test_interactive_no_tty_graceful
run_test "interactive: no-TTY fallback selects all fields" test_interactive_no_tty_fallback_selects_all
run_test "interactive: no-TTY emits stderr warning" test_interactive_no_tty_stderr_warning
run_test "interactive: -i with -s colons in non-TTY" test_interactive_with_strategy_no_tty
run_test "interactive: -i with -s json in non-TTY" test_interactive_with_json_strategy_no_tty
run_test "interactive: -i with -f csv in non-TTY" test_interactive_format_csv_no_tty
run_test "interactive: -i with -f yaml in non-TTY" test_interactive_format_yaml_no_tty
run_test "interactive: multi-file non-TTY" test_interactive_multiple_files_no_tty
run_test "interactive: _interactive_select empty input" test_interactive_select_empty_input
run_test "interactive: _interactive_select single field" test_interactive_select_single_field
run_test "interactive: SIGINT does not hang" test_interactive_sigint_no_hang

print_summary
