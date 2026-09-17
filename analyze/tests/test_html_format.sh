#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
source "$SCRIPT_DIR/helpers.sh"

########################################
## HTML format tests
########################################

test_html_contains_expected_tags () {
    local output
    output=$(run_mda --format html "$SAMPLES_DIR/trees.csv")
    assert_contains "$output" "<!DOCTYPE html>" "should start with DOCTYPE"
    assert_contains "$output" "<html" "should contain html tag"
    assert_contains "$output" "<head>" "should contain head tag"
    assert_contains "$output" "<body>" "should contain body tag"
    assert_contains "$output" "</html>" "should close html tag"
    assert_contains "$output" "<style>" "should contain inline CSS"
    assert_contains "$output" "EnvoyAnalyze Report" "should contain report title"
}

test_html_contains_summary_stats () {
    local output
    output=$(run_mda --format html "$SAMPLES_DIR/trees.csv")
    assert_contains "$output" "summary-stats" "should contain summary stats section"
    assert_contains "$output" "GOOD" "should contain GOOD tag"
    assert_contains "$output" "items" "should mention item count"
}

test_html_contains_column_data () {
    local output
    output=$(run_mda --format html --all "$SAMPLES_DIR/trees.csv")
    assert_contains "$output" "Girth" "should contain column name Girth"
    assert_contains "$output" "Height" "should contain column name Height"
    assert_contains "$output" "Dataset overview" "should contain dataset overview"
    assert_contains "$output" "Column types" "should contain column types section"
}

test_html_sparkline_svgs_present () {
    local output
    output=$(run_mda --format html --all --kinds histogram "$SAMPLES_DIR/trees.csv")
    # Histogram items should have SVG sparklines
    assert_contains "$output" "<svg" "should contain SVG sparkline elements"
    assert_contains "$output" "<rect" "should contain SVG rect bars"
    assert_contains "$output" "sparkline" "should contain sparkline class"
}

test_html_error_on_invalid_input () {
    local rc=0
    run_mda --format html /tmp/nonexistent_file_$$.csv 2>/dev/null || rc=$?
    if [[ "$rc" -eq 0 ]]; then
        echo "  ASSERT FAILED: should exit non-zero on invalid input"
        return 1
    fi
}

test_html_format_validation () {
    local rc=0
    run_mda --format bogus "$SAMPLES_DIR/trees.csv" 2>/dev/null || rc=$?
    if [[ "$rc" -eq 0 ]]; then
        echo "  ASSERT FAILED: should reject unknown format"
        return 1
    fi
}

test_html_correlation_coloring () {
    local output
    output=$(run_mda --format html --all --kinds corr_pairs "$SAMPLES_DIR/trees.csv")
    assert_contains "$output" "correlation-strong" "should color-code strong correlations"
}

########################################
## Run all HTML format tests
########################################

run_test "HTML output contains expected HTML tags" test_html_contains_expected_tags
run_test "HTML output contains summary statistics" test_html_contains_summary_stats
run_test "HTML output contains column data" test_html_contains_column_data
run_test "HTML output has SVG sparklines for histograms" test_html_sparkline_svgs_present
run_test "HTML format rejects invalid input file" test_html_error_on_invalid_input
run_test "Format validation rejects unknown format" test_html_format_validation
run_test "HTML output color-codes strong correlations" test_html_correlation_coloring

print_summary
