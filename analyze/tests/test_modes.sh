#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo "=== Analysis Mode Tests ==="

test_mode_benchmark_promotes_cv () {
    local output
    output=$(run_mda --mode benchmark --tags GOOD "$SAMPLES_DIR/trees.csv" 2>/dev/null)
    assert_contains "$output" "Coefficient of variation" "benchmark mode should promote CV to GOOD"
}

test_mode_benchmark_promotes_anomaly () {
    local output
    output=$(run_mda --mode benchmark --tags GOOD "$SAMPLES_DIR/trees.csv" 2>/dev/null)
    assert_contains "$output" "Anomaly detection" "benchmark mode should promote anomaly to GOOD"
}

test_mode_monitor_promotes_trend () {
    local output
    output=$(run_mda --mode monitor --tags GOOD "$SAMPLES_DIR/trees.csv" 2>/dev/null)
    assert_contains "$output" "Trend:" "monitor mode should promote trend to GOOD"
}

test_mode_monitor_demotes_histogram () {
    local output
    output=$(run_mda --mode monitor --tags GOOD "$SAMPLES_DIR/trees.csv" 2>/dev/null)
    assert_not_contains "$output" "Histogram:" "monitor mode should demote histogram from GOOD"
}

test_mode_monitor_demotes_sparkline () {
    local output
    output=$(run_mda --mode monitor --tags GOOD "$SAMPLES_DIR/trees.csv" 2>/dev/null)
    assert_not_contains "$output" "Sparkline:" "monitor mode should demote sparkline from GOOD"
}

test_mode_explore_unchanged () {
    local output_default output_explore
    output_default=$(run_mda --tags GOOD "$SAMPLES_DIR/trees.csv" 2>/dev/null)
    output_explore=$(run_mda --mode explore --tags GOOD "$SAMPLES_DIR/trees.csv" 2>/dev/null)
    if [[ "$output_default" != "$output_explore" ]]; then
        echo "  ASSERT FAILED: --mode explore should produce identical output to no mode"
        return 1
    fi
}

test_mode_invalid () {
    local code=0
    run_mda --mode bogus "$SAMPLES_DIR/trees.csv" 2>/dev/null || code=$?
    if [[ $code -eq 0 ]]; then
        echo "  ASSERT FAILED: invalid mode should error"
        return 1
    fi
}

test_mode_benchmark_with_compare () {
    local output
    output=$(run_mda --mode benchmark --compare "$SAMPLES_DIR/trees.csv" "$SAMPLES_DIR/trees.csv" --tags GOOD 2>/dev/null)
    assert_contains "$output" "Cross-dataset comparison" "benchmark + compare should show comparison as GOOD"
}

run_test "benchmark promotes CV" test_mode_benchmark_promotes_cv
run_test "benchmark promotes anomaly" test_mode_benchmark_promotes_anomaly
run_test "monitor promotes trend" test_mode_monitor_promotes_trend
run_test "monitor demotes histogram" test_mode_monitor_demotes_histogram
run_test "monitor demotes sparkline" test_mode_monitor_demotes_sparkline
run_test "explore is unchanged" test_mode_explore_unchanged
run_test "invalid mode errors" test_mode_invalid
run_test "benchmark with compare" test_mode_benchmark_with_compare

print_summary
