#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo "=== Cross-Dataset Comparison Tests ==="

test_compare_two_identical_files () {
    local output
    output=$(run_mda --compare "$SAMPLES_DIR/trees.csv" "$SAMPLES_DIR/trees.csv" --all 2>/dev/null)
    assert_contains "$output" "Cross-dataset comparison" "should produce comparison item"
    assert_contains "$output" "Dataset ranking" "should produce ranking item"
    assert_contains "$output" "Comparison summary" "should produce comparison summary"
}

test_compare_ranking_output () {
    local output
    output=$(run_mda --compare "$SAMPLES_DIR/trees.csv" "$SAMPLES_DIR/trees.csv" --all 2>/dev/null)
    assert_contains "$output" "Ranked by mean" "should show ranking"
    assert_contains "$output" "#1" "should have rank #1"
}

test_compare_shared_columns () {
    local output
    output=$(run_mda --compare "$SAMPLES_DIR/trees.csv" "$SAMPLES_DIR/edge.csv" --all 2>/dev/null)
    # These files have no shared numeric columns, so should report that
    assert_contains "$output" "Cross-dataset comparison" "should produce comparison even with different columns"
}

test_compare_summary_counts () {
    local output
    output=$(run_mda --compare "$SAMPLES_DIR/trees.csv" "$SAMPLES_DIR/trees.csv" --all 2>/dev/null)
    assert_contains "$output" "Compared 2 datasets" "should report dataset count"
}

test_compare_json_format () {
    local output
    output=$(run_mda --compare "$SAMPLES_DIR/trees.csv" "$SAMPLES_DIR/trees.csv" --all --format json 2>/dev/null)
    assert_contains "$output" '"tag":"GOOD"' "JSON should contain GOOD tag"
    assert_contains "$output" "Cross-dataset comparison" "JSON should contain comparison title"
}

test_compare_requires_two_files () {
    local code=0
    run_mda --compare "$SAMPLES_DIR/trees.csv" 2>/dev/null || code=$?
    if [[ $code -eq 0 ]]; then
        echo "  ASSERT FAILED: --compare with 1 file should error"
        return 1
    fi
}

test_compare_with_good_filter () {
    local output
    output=$(run_mda --compare "$SAMPLES_DIR/trees.csv" "$SAMPLES_DIR/trees.csv" --good 2>/dev/null)
    assert_contains "$output" "Cross-dataset comparison" "comparison items should be tagged GOOD"
    assert_contains "$output" "Comparison summary" "summary should be tagged GOOD"
}

run_test "compare two identical files" test_compare_two_identical_files
run_test "compare ranking output" test_compare_ranking_output
run_test "compare shared columns" test_compare_shared_columns
run_test "compare summary counts" test_compare_summary_counts
run_test "compare JSON format" test_compare_json_format
run_test "compare requires two files" test_compare_requires_two_files
run_test "compare with --good filter" test_compare_with_good_filter

print_summary
