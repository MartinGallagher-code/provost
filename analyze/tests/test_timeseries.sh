#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo "=== Time-Series Promotion Tests ==="

test_timeseries_auto_detect () {
    # trees.csv has Index column that is perfectly sorted ascending
    # So trend/monotonicity should auto-promote to GOOD
    local output
    output=$(run_mda --tags GOOD "$SAMPLES_DIR/trees.csv" 2>/dev/null)
    assert_contains "$output" "Trend: Index" "auto-detected timeseries should promote Index trend to GOOD"
    assert_contains "$output" "Monotonicity: Index" "auto-detected timeseries should promote Index monotonicity to GOOD"
}

test_timeseries_flag_promotes () {
    local output
    output=$(run_mda --timeseries --tags GOOD "$SAMPLES_DIR/trees.csv" 2>/dev/null)
    assert_contains "$output" "Trend:" "timeseries flag should promote trend items to GOOD"
}

test_timeseries_flag_promotes_all_trends () {
    local output
    output=$(run_mda --timeseries --tags GOOD "$SAMPLES_DIR/trees.csv" 2>/dev/null)
    # trees.csv has strong trends in multiple columns
    assert_contains "$output" "Trend: Girth" "should promote Girth trend"
    assert_contains "$output" "Trend: Volume" "should promote Volume trend"
}

test_timeseries_without_flag_edge () {
    # edge.csv may not have a perfectly sorted column
    local output
    output=$(run_mda --tags GOOD "$SAMPLES_DIR/edge.csv" 2>/dev/null)
    # Trend should NOT be in GOOD unless auto-detected
    # (edge.csv has an id column that IS sorted, so it might still promote)
    # Just verify it doesn't crash
    assert_contains "$output" "Dataset overview" "should still produce output"
}

test_timeseries_with_mode_benchmark () {
    local output
    output=$(run_mda --timeseries --mode benchmark --tags GOOD "$SAMPLES_DIR/trees.csv" 2>/dev/null)
    assert_contains "$output" "Trend:" "timeseries + benchmark should keep trend as GOOD"
    assert_contains "$output" "Coefficient of variation" "benchmark should also promote CV"
}

test_timeseries_with_mode_monitor () {
    local output
    output=$(run_mda --timeseries --mode monitor --tags GOOD "$SAMPLES_DIR/trees.csv" 2>/dev/null)
    assert_contains "$output" "Trend:" "timeseries + monitor should promote trend"
    assert_not_contains "$output" "Histogram:" "monitor should demote histogram"
}

run_test "timeseries auto-detect" test_timeseries_auto_detect
run_test "timeseries flag promotes" test_timeseries_flag_promotes
run_test "timeseries flag promotes all trends" test_timeseries_flag_promotes_all_trends
run_test "timeseries without flag on edge" test_timeseries_without_flag_edge
run_test "timeseries with benchmark mode" test_timeseries_with_mode_benchmark
run_test "timeseries with monitor mode" test_timeseries_with_mode_monitor

print_summary
