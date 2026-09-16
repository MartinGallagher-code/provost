#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Batch Summary Tests
##
## Tests for --batch-summary flag: after batch processing, emit a summary JSON
## object with totals, strategy usage, common fields, and file lists.
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

MFE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo ""
echo "========================================"
echo "Batch Summary Tests"
echo "========================================"

# ---------------------------------------------------------------------------
# Basic: --batch-summary emits summary object after file records
# ---------------------------------------------------------------------------

test_batch_summary_basic () {
    local tmp1 tmp2 output last_line
    tmp1=$(mktemp --suffix=.json)
    tmp2=$(mktemp --suffix=.json)
    printf '{"host": "server1", "port": "80"}\n' > "$tmp1"
    printf '{"host": "server2", "version": "2.0"}\n' > "$tmp2"
    output=$(printf '%s\n%s\n' "$tmp1" "$tmp2" | run_mfe batch --batch-summary 2>/dev/null)
    rm -f "$tmp1" "$tmp2"
    # Should have 3 lines: 2 file records + 1 summary
    assert_line_count "$output" 3 "batch-summary: should produce 3 output lines (2 files + summary)"
    last_line=$(echo "$output" | tail -1)
    assert_contains "$last_line" '"_summary": true' "batch-summary: last line should have _summary marker"
    assert_contains "$last_line" '"total_files": 2' "batch-summary: total_files should be 2"
}

# ---------------------------------------------------------------------------
# Verify total_files count with three files
# ---------------------------------------------------------------------------

test_batch_summary_total_files () {
    local tmp1 tmp2 tmp3 output summary
    tmp1=$(mktemp --suffix=.json)
    tmp2=$(mktemp --suffix=.json)
    tmp3=$(mktemp --suffix=.json)
    printf '{"a": "1"}\n' > "$tmp1"
    printf '{"b": "2"}\n' > "$tmp2"
    printf '{"c": "3"}\n' > "$tmp3"
    output=$(printf '%s\n%s\n%s\n' "$tmp1" "$tmp2" "$tmp3" | run_mfe batch --batch-summary 2>/dev/null)
    rm -f "$tmp1" "$tmp2" "$tmp3"
    summary=$(echo "$output" | tail -1)
    assert_contains "$summary" '"total_files": 3' "batch-summary: total_files should be 3"
    assert_contains "$summary" '"total_fields": 3' "batch-summary: total_fields should be 3"
}

# ---------------------------------------------------------------------------
# Verify common_fields detection: fields present in all files
# ---------------------------------------------------------------------------

test_batch_summary_common_fields () {
    local tmp1 tmp2 output summary
    tmp1=$(mktemp --suffix=.json)
    tmp2=$(mktemp --suffix=.json)
    printf '{"name": "alpha", "version": "1.0", "author": "test"}\n' > "$tmp1"
    printf '{"name": "beta", "version": "2.0", "license": "MIT"}\n' > "$tmp2"
    output=$(printf '%s\n%s\n' "$tmp1" "$tmp2" | run_mfe batch --batch-summary 2>/dev/null)
    rm -f "$tmp1" "$tmp2"
    summary=$(echo "$output" | tail -1)
    # "name" and "version" are common to both files
    assert_contains "$summary" '"name"' "batch-summary: common_fields should include name"
    assert_contains "$summary" '"version"' "batch-summary: common_fields should include version"
}

# ---------------------------------------------------------------------------
# Error when --batch-summary used without --batch
# ---------------------------------------------------------------------------

test_batch_summary_requires_batch () {
    local tmp1 stderr_out exit_code
    tmp1=$(mktemp --suffix=.json)
    printf '{"key": "val"}\n' > "$tmp1"
    stderr_out=$(run_mfe --batch-summary "$tmp1" 2>&1 >/dev/null || true)
    rm -f "$tmp1"
    assert_contains "$stderr_out" "requires --batch" "batch-summary: should error without --batch"
}

# ---------------------------------------------------------------------------
# Empty input: summary with zero totals
# ---------------------------------------------------------------------------

test_batch_summary_empty_input () {
    local output summary
    output=$(echo "" | run_mfe batch --batch-summary 2>/dev/null)
    summary=$(echo "$output" | tail -1)
    assert_contains "$summary" '"_summary": true' "batch-summary: empty input should still emit summary"
    assert_contains "$summary" '"total_files": 0' "batch-summary: empty input total_files should be 0"
    assert_contains "$summary" '"total_fields": 0' "batch-summary: empty input total_fields should be 0"
    assert_contains "$summary" '"common_fields": []' "batch-summary: empty input common_fields should be empty"
    assert_contains "$summary" '"files_processed": []' "batch-summary: empty input files_processed should be empty"
    assert_contains "$summary" '"files_failed": []' "batch-summary: empty input files_failed should be empty"
}

# ---------------------------------------------------------------------------
# Files with different strategies: strategies_used tracks counts
# ---------------------------------------------------------------------------

test_batch_summary_strategies_used () {
    local tmp_json tmp_ini output summary
    tmp_json=$(mktemp --suffix=.json)
    tmp_ini=$(mktemp --suffix=.ini)
    printf '{"host": "server1"}\n' > "$tmp_json"
    printf '[section]\nkey = value\n' > "$tmp_ini"
    output=$(printf '%s\n%s\n' "$tmp_json" "$tmp_ini" | run_mfe batch --batch-summary 2>/dev/null)
    rm -f "$tmp_json" "$tmp_ini"
    summary=$(echo "$output" | tail -1)
    assert_contains "$summary" '"strategies_used":' "batch-summary: should contain strategies_used"
    # json strategy should appear (the .json file definitely triggers json strategy)
    assert_contains "$summary" '"json":' "batch-summary: json strategy should appear in strategies_used"
}

# ---------------------------------------------------------------------------
# files_failed tracks missing files
# ---------------------------------------------------------------------------

test_batch_summary_files_failed () {
    local tmp1 output summary
    tmp1=$(mktemp --suffix=.json)
    printf '{"key": "val"}\n' > "$tmp1"
    output=$(printf '%s\n/nonexistent/missing.json\n' "$tmp1" | run_mfe batch --batch-summary 2>/dev/null)
    rm -f "$tmp1"
    summary=$(echo "$output" | tail -1)
    assert_contains "$summary" '"total_files": 1' "batch-summary: total_files should be 1 (only successful)"
    assert_contains "$summary" '/nonexistent/missing.json' "batch-summary: files_failed should contain missing file"
}

# ---------------------------------------------------------------------------
# files_processed lists all successfully processed files
# ---------------------------------------------------------------------------

test_batch_summary_files_processed () {
    local tmp1 tmp2 output summary
    tmp1=$(mktemp --suffix=.json)
    tmp2=$(mktemp --suffix=.json)
    printf '{"a": "1"}\n' > "$tmp1"
    printf '{"b": "2"}\n' > "$tmp2"
    output=$(printf '%s\n%s\n' "$tmp1" "$tmp2" | run_mfe batch --batch-summary 2>/dev/null)
    summary=$(echo "$output" | tail -1)
    assert_contains "$summary" "$tmp1" "batch-summary: files_processed should include first file"
    assert_contains "$summary" "$tmp2" "batch-summary: files_processed should include second file"
    rm -f "$tmp1" "$tmp2"
}

# ---------------------------------------------------------------------------
# Run all tests
# ---------------------------------------------------------------------------

run_test "batch-summary: basic output with two files"                  test_batch_summary_basic
run_test "batch-summary: total_files count with three files"           test_batch_summary_total_files
run_test "batch-summary: common_fields detects shared fields"          test_batch_summary_common_fields
run_test "batch-summary: errors without --batch"                       test_batch_summary_requires_batch
run_test "batch-summary: empty input produces zero-count summary"      test_batch_summary_empty_input
run_test "batch-summary: strategies_used tracks different strategies"   test_batch_summary_strategies_used
run_test "batch-summary: files_failed tracks missing files"            test_batch_summary_files_failed
run_test "batch-summary: files_processed lists successful files"       test_batch_summary_files_processed

print_summary
