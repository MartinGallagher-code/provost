#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo "=== Summary/Verdict Tests ==="

test_summary_contains_findings () {
    local output
    output=$(run_mda --summary --all "$SAMPLES_DIR/trees.csv" 2>/dev/null)
    assert_contains "$output" "Analysis summary" "should produce analysis summary item"
    assert_contains "$output" "Key findings" "should contain key findings header"
}

test_summary_mentions_dataset_size () {
    local output
    output=$(run_mda --summary --all "$SAMPLES_DIR/trees.csv" 2>/dev/null)
    assert_contains "$output" "31 rows" "should mention row count"
    assert_contains "$output" "4 columns" "should mention column count"
}

test_summary_mentions_correlation () {
    local output
    output=$(run_mda --summary --all "$SAMPLES_DIR/trees.csv" 2>/dev/null)
    assert_contains "$output" "Strongest correlation" "should mention strongest correlation"
}

test_summary_mentions_quality () {
    local output
    output=$(run_mda --summary --all "$SAMPLES_DIR/trees.csv" 2>/dev/null)
    assert_contains "$output" "Quality:" "should mention quality score"
}

test_summary_mentions_trends () {
    local output
    output=$(run_mda --summary --all "$SAMPLES_DIR/trees.csv" 2>/dev/null)
    assert_contains "$output" "Strong trend" "should mention strong trends"
}

test_summary_json_format () {
    local output
    output=$(run_mda --summary --all --format json "$SAMPLES_DIR/trees.csv" 2>/dev/null)
    assert_contains "$output" "Analysis summary" "JSON should contain verdict item"
    assert_contains "$output" "Key findings" "JSON should contain findings"
}

test_summary_with_threshold () {
    local output
    output=$(run_mda --summary --threshold "Index>0" --all "$SAMPLES_DIR/trees.csv" 2>/dev/null)
    assert_contains "$output" "Thresholds:" "summary should mention threshold results"
    assert_contains "$output" "passed" "summary should mention pass/fail"
}

test_summary_tagged_good () {
    local output
    output=$(run_mda --summary --good "$SAMPLES_DIR/trees.csv" 2>/dev/null)
    assert_contains "$output" "[GOOD] Analysis summary" "summary should be tagged GOOD"
}

run_test "summary contains findings" test_summary_contains_findings
run_test "summary mentions dataset size" test_summary_mentions_dataset_size
run_test "summary mentions correlation" test_summary_mentions_correlation
run_test "summary mentions quality" test_summary_mentions_quality
run_test "summary mentions trends" test_summary_mentions_trends
run_test "summary JSON format" test_summary_json_format
run_test "summary with threshold" test_summary_with_threshold
run_test "summary tagged GOOD" test_summary_tagged_good

print_summary
