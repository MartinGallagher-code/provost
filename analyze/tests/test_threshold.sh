#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo "=== Threshold Alerting Tests ==="

test_threshold_pass () {
    local output code=0
    output=$(run_mda --threshold "Index>0" "$SAMPLES_DIR/trees.csv" --all 2>/dev/null) || code=$?
    assert_contains "$output" "Threshold check" "should produce threshold check item"
    assert_contains "$output" "PASS" "should show PASS verdict"
    assert_exit_zero "$code" "threshold should pass (all Index > 0)"
}

test_threshold_fail () {
    local output code=0
    # Index min=1, so Index>50 will fail
    output=$(run_mda --threshold "Index>50" "$SAMPLES_DIR/trees.csv" --all 2>/dev/null) || code=$?
    assert_contains "$output" "FAIL" "should show FAIL verdict"
    if [[ $code -eq 0 ]]; then
        echo "  ASSERT FAILED: threshold should fail with exit code 1"
        return 1
    fi
}

test_threshold_exit_code_pass () {
    local code=0
    run_mda --threshold "Index>0" "$SAMPLES_DIR/trees.csv" --all 2>/dev/null || code=$?
    assert_exit_zero "$code" "exit code should be 0 on pass"
}

test_threshold_exit_code_fail () {
    local code=0
    run_mda --threshold "Index>50" "$SAMPLES_DIR/trees.csv" --all 2>/dev/null || code=$?
    if [[ $code -ne 1 ]]; then
        echo "  ASSERT FAILED: exit code should be 1 on fail, got $code"
        return 1
    fi
}

test_threshold_multiple () {
    local output code=0
    output=$(run_mda --threshold "Index>0" --threshold "Index<100" "$SAMPLES_DIR/trees.csv" --all 2>/dev/null) || code=$?
    assert_contains "$output" "Threshold summary" "should produce threshold summary"
    assert_contains "$output" "2/2 checks passed" "both checks should pass"
    assert_exit_zero "$code" "all thresholds pass"
}

test_threshold_multiple_one_fails () {
    local output code=0
    output=$(run_mda --threshold "Index>0" --threshold "Index>50" "$SAMPLES_DIR/trees.csv" --all 2>/dev/null) || code=$?
    assert_contains "$output" "1/2 checks passed" "one of two should pass"
    if [[ $code -eq 0 ]]; then
        echo "  ASSERT FAILED: should fail when any threshold fails"
        return 1
    fi
}

test_threshold_nonexistent_column () {
    local output code=0
    output=$(run_mda --threshold "nonexistent>5" "$SAMPLES_DIR/trees.csv" --all 2>/dev/null) || code=$?
    assert_contains "$output" "not found" "should report column not found"
    if [[ $code -eq 0 ]]; then
        echo "  ASSERT FAILED: nonexistent column should cause failure"
        return 1
    fi
}

test_threshold_operators () {
    local output code=0
    # Index min=1, max=31, mean=16
    output=$(run_mda --threshold "Index>=1" "$SAMPLES_DIR/trees.csv" --all 2>/dev/null) || code=$?
    assert_contains "$output" "PASS" ">= operator should pass"
    assert_exit_zero "$code" ">= should pass"

    code=0
    output=$(run_mda --threshold "Index<=31" "$SAMPLES_DIR/trees.csv" --all 2>/dev/null) || code=$?
    assert_contains "$output" "PASS" "<= operator should pass"
    assert_exit_zero "$code" "<= should pass"
}

test_threshold_json_format () {
    local output code=0
    output=$(run_mda --threshold "Index>0" "$SAMPLES_DIR/trees.csv" --all --format json 2>/dev/null) || code=$?
    assert_contains "$output" "Threshold check" "JSON should contain threshold item"
    assert_contains "$output" "Threshold summary" "JSON should contain summary item"
}

run_test "threshold pass" test_threshold_pass
run_test "threshold fail" test_threshold_fail
run_test "threshold exit code pass" test_threshold_exit_code_pass
run_test "threshold exit code fail" test_threshold_exit_code_fail
run_test "threshold multiple pass" test_threshold_multiple
run_test "threshold multiple one fails" test_threshold_multiple_one_fails
run_test "threshold nonexistent column" test_threshold_nonexistent_column
run_test "threshold operators" test_threshold_operators
run_test "threshold JSON format" test_threshold_json_format

print_summary
