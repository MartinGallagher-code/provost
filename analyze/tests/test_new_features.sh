#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo "========================================"
echo "EnvoyAnalyze v3.1 New Features Tests"
echo "========================================"

########################################
## CROSS-DATASET COMPARISON TESTS
########################################

test_compare_same_file () {
    local output
    output=$(run_mda --compare "$SAMPLES_DIR/trees.csv" "$SAMPLES_DIR/trees.csv" --all 2>/dev/null)
    assert_contains "$output" "Cross-dataset comparison" "should produce comparison items"
    assert_contains "$output" "Dataset ranking" "should produce ranking items"
    assert_contains "$output" "Comparison summary" "should produce summary item"
}

test_compare_ranking () {
    local output
    output=$(run_mda --compare "$SAMPLES_DIR/trees.csv" "$SAMPLES_DIR/trees.csv" --all 2>/dev/null)
    assert_contains "$output" "#1" "should rank datasets"
    assert_contains "$output" "trees" "should use filename as label"
}

test_compare_shared_columns () {
    local output
    output=$(run_mda --compare "$SAMPLES_DIR/trees.csv" "$SAMPLES_DIR/biostats.csv" --all 2>/dev/null)
    # These have no shared numeric columns
    assert_contains "$output" "No shared numeric columns" "should report no shared columns"
}

test_compare_json_format () {
    local output
    output=$(run_mda --compare "$SAMPLES_DIR/trees.csv" "$SAMPLES_DIR/trees.csv" --all --format json 2>/dev/null)
    assert_contains "$output" '"tag":"GOOD"' "should produce valid JSON with GOOD tags"
    assert_contains "$output" "Cross-dataset comparison" "JSON should contain comparison title"
}

test_compare_requires_two_files () {
    local rc=0
    run_mda --compare "$SAMPLES_DIR/trees.csv" 2>/dev/null || rc=$?
    if [[ $rc -eq 0 ]]; then
        echo "  ASSERT FAILED: --compare with one file should error"
        return 1
    fi
}

test_compare_good_filter () {
    local output
    output=$(run_mda --compare "$SAMPLES_DIR/trees.csv" "$SAMPLES_DIR/trees.csv" 2>/dev/null)
    assert_contains "$output" "Cross-dataset comparison" "comparison should appear in --good default output"
}

test_compare_no_early_exit_in_pipe () {
    # Regression guard: under `set -euo pipefail`, an awk that exits before
    # consuming all of a piped `echo` can leave `echo` with SIGPIPE (141),
    # which pipefail+set -e turn into a comparison-aborting failure. That flaked
    # the "compare same file" test on Alpine. Keep the match-row awk free of an
    # early `exit` so the upstream pipe always drains.
    local lib="$SCRIPT_DIR/../lib/_compare.sh"
    if grep -nE 'echo .*\| *awk[^|]*exit' "$lib"; then
        echo "  ASSERT FAILED: _compare.sh pipes echo into an early-exit awk (SIGPIPE/pipefail hazard)"
        return 1
    fi
}

########################################
## THRESHOLD TESTS
########################################

test_threshold_pass () {
    local output rc=0
    output=$(run_mda --threshold "Index>0" "$SAMPLES_DIR/trees.csv" --all 2>/dev/null) || rc=$?
    assert_contains "$output" "Threshold check" "should produce threshold check item"
    assert_contains "$output" "PASS" "should pass: Index min=1 > 0"
    assert_exit_zero "$rc" "exit code should be 0 for passing threshold"
}

test_threshold_fail () {
    local output rc=0
    output=$(run_mda --threshold "Index<0" "$SAMPLES_DIR/trees.csv" --all 2>/dev/null) || rc=$?
    assert_contains "$output" "FAIL" "should fail: Index max=31 is not < 0"
    if [[ $rc -eq 0 ]]; then
        echo "  ASSERT FAILED: exit code should be 1 for failing threshold"
        return 1
    fi
}

test_threshold_multiple () {
    local output rc=0
    output=$(run_mda --threshold "Index>0" --threshold "Index<100" "$SAMPLES_DIR/trees.csv" --all 2>/dev/null) || rc=$?
    assert_contains "$output" "2/2 checks passed" "both thresholds should pass"
    assert_exit_zero "$rc" "exit code should be 0 when all thresholds pass"
}

test_threshold_nonexistent_column () {
    local output rc=0
    output=$(run_mda --threshold "Bogus>0" "$SAMPLES_DIR/trees.csv" --all 2>/dev/null) || rc=$?
    assert_contains "$output" "not found" "should report column not found"
    if [[ $rc -eq 0 ]]; then
        echo "  ASSERT FAILED: exit code should be 1 for missing column"
        return 1
    fi
}

test_threshold_operators () {
    local output rc=0
    output=$(run_mda --threshold "Index>=1" "$SAMPLES_DIR/trees.csv" --all 2>/dev/null) || rc=$?
    assert_contains "$output" "PASS" "should pass >= check"
    assert_exit_zero "$rc" "exit code should be 0 for >= pass"
}

test_threshold_summary () {
    local output
    output=$(run_mda --threshold "Index>0" "$SAMPLES_DIR/trees.csv" --all 2>/dev/null)
    assert_contains "$output" "Threshold summary" "should include threshold summary item"
    assert_contains "$output" "1/1 checks passed" "summary should show pass count"
}

########################################
## ANALYSIS MODE TESTS
########################################

test_mode_benchmark_promotes_cv () {
    local output
    output=$(run_mda --mode benchmark --tags GOOD "$SAMPLES_DIR/trees.csv" 2>/dev/null)
    assert_contains "$output" "Coefficient of variation" "benchmark mode should promote CV to GOOD"
}

test_mode_benchmark_demotes_top_values () {
    local output
    output=$(run_mda --mode benchmark --tags GOOD "$SAMPLES_DIR/biostats.csv" 2>/dev/null)
    assert_not_contains "$output" "Top values" "benchmark mode should demote top_values from GOOD"
}

test_mode_monitor_promotes_trend () {
    local output
    output=$(run_mda --mode monitor --tags GOOD "$SAMPLES_DIR/trees.csv" 2>/dev/null)
    assert_contains "$output" "Trend" "monitor mode should promote trend items to GOOD"
}

test_mode_monitor_promotes_anomaly () {
    local output
    output=$(run_mda --mode monitor --tags GOOD "$SAMPLES_DIR/trees.csv" 2>/dev/null)
    assert_contains "$output" "Anomaly detection" "monitor mode should promote anomaly items to GOOD"
}

test_mode_monitor_demotes_histogram () {
    local output
    output=$(run_mda --mode monitor --tags GOOD "$SAMPLES_DIR/trees.csv" 2>/dev/null)
    assert_not_contains "$output" "Histogram" "monitor mode should demote histogram from GOOD"
}

test_mode_explore_unchanged () {
    local output_default output_explore
    output_default=$(run_mda --tags GOOD "$SAMPLES_DIR/trees.csv" 2>/dev/null)
    output_explore=$(run_mda --mode explore --tags GOOD "$SAMPLES_DIR/trees.csv" 2>/dev/null)
    if [[ "$output_default" != "$output_explore" ]]; then
        echo "  ASSERT FAILED: explore mode should produce same output as default"
        return 1
    fi
}

test_mode_invalid () {
    local rc=0
    run_mda --mode bogus "$SAMPLES_DIR/trees.csv" 2>/dev/null || rc=$?
    if [[ $rc -eq 0 ]]; then
        echo "  ASSERT FAILED: --mode bogus should error"
        return 1
    fi
}

########################################
## SUMMARY / VERDICT TESTS
########################################

test_summary_contains_findings () {
    local output
    output=$(run_mda --summary "$SAMPLES_DIR/trees.csv" 2>/dev/null)
    assert_contains "$output" "Analysis summary" "should produce summary item"
    assert_contains "$output" "Key findings" "should contain 'Key findings' heading"
}

test_summary_mentions_correlation () {
    local output
    output=$(run_mda --summary "$SAMPLES_DIR/trees.csv" 2>/dev/null)
    assert_contains "$output" "Strongest correlation" "should mention strongest correlation"
}

test_summary_mentions_quality () {
    local output
    output=$(run_mda --summary "$SAMPLES_DIR/trees.csv" 2>/dev/null)
    assert_contains "$output" "Quality" "should mention quality score"
}

test_summary_with_threshold () {
    local output
    output=$(run_mda --summary --threshold "Index>0" "$SAMPLES_DIR/trees.csv" 2>/dev/null)
    assert_contains "$output" "Thresholds" "summary should mention threshold results"
    assert_contains "$output" "passed" "summary should indicate threshold pass"
}

test_summary_json () {
    local output
    output=$(run_mda --summary --format json "$SAMPLES_DIR/trees.csv" 2>/dev/null)
    assert_contains "$output" '"title":"Analysis summary"' "JSON should contain summary item"
}

########################################
## TIME-SERIES TESTS
########################################

test_timeseries_auto_detect () {
    # trees.csv has Index column that is perfectly sorted ascending
    local output
    output=$(run_mda --tags GOOD "$SAMPLES_DIR/trees.csv" 2>/dev/null)
    assert_contains "$output" "Trend: Index" "auto-detect should promote monotonic column's trend to GOOD"
    assert_contains "$output" "Monotonicity: Index" "auto-detect should promote monotonic column's monotonicity to GOOD"
}

test_timeseries_flag () {
    local output
    output=$(run_mda --timeseries --tags GOOD "$SAMPLES_DIR/trees.csv" 2>/dev/null)
    assert_contains "$output" "Trend" "timeseries flag should promote trend items to GOOD"
}

test_timeseries_no_promote_without () {
    # bimodal.csv has no monotonic columns (random-ish data)
    local output
    output=$(run_mda --tags GOOD "$SAMPLES_DIR/bimodal.csv" 2>/dev/null)
    assert_not_contains "$output" "Monotonicity:" "non-timeseries data should not promote monotonicity to GOOD"
}

test_timeseries_with_mode () {
    local output
    output=$(run_mda --timeseries --mode benchmark --tags GOOD "$SAMPLES_DIR/trees.csv" 2>/dev/null)
    # Both timeseries and benchmark should promote trend
    assert_contains "$output" "Trend" "timeseries + benchmark should keep trend as GOOD"
}

########################################
## RUN ALL TESTS
########################################

echo ""
echo "--- Cross-dataset comparison ---"
run_test "compare same file" test_compare_same_file
run_test "compare ranking" test_compare_ranking
run_test "compare no shared columns" test_compare_shared_columns
run_test "compare JSON format" test_compare_json_format
run_test "compare requires two files" test_compare_requires_two_files
run_test "compare shows in GOOD default" test_compare_good_filter
run_test "compare match-row pipe has no SIGPIPE/pipefail hazard" test_compare_no_early_exit_in_pipe

echo ""
echo "--- Threshold alerting ---"
run_test "threshold pass" test_threshold_pass
run_test "threshold fail" test_threshold_fail
run_test "threshold multiple" test_threshold_multiple
run_test "threshold nonexistent column" test_threshold_nonexistent_column
run_test "threshold operators" test_threshold_operators
run_test "threshold summary" test_threshold_summary

echo ""
echo "--- Analysis modes ---"
run_test "mode benchmark promotes CV" test_mode_benchmark_promotes_cv
run_test "mode benchmark demotes top_values" test_mode_benchmark_demotes_top_values
run_test "mode monitor promotes trend" test_mode_monitor_promotes_trend
run_test "mode monitor promotes anomaly" test_mode_monitor_promotes_anomaly
run_test "mode monitor demotes histogram" test_mode_monitor_demotes_histogram
run_test "mode explore unchanged" test_mode_explore_unchanged
run_test "mode invalid" test_mode_invalid

echo ""
echo "--- Summary / verdict ---"
run_test "summary contains findings" test_summary_contains_findings
run_test "summary mentions correlation" test_summary_mentions_correlation
run_test "summary mentions quality" test_summary_mentions_quality
run_test "summary with threshold" test_summary_with_threshold
run_test "summary JSON output" test_summary_json

echo ""
echo "--- Time-series ---"
run_test "timeseries auto-detect" test_timeseries_auto_detect
run_test "timeseries flag" test_timeseries_flag
run_test "timeseries no promote without" test_timeseries_no_promote_without
run_test "timeseries with mode" test_timeseries_with_mode

print_summary
