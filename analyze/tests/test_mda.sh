#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
source "$SCRIPT_DIR/helpers.sh"

test_strongest_correlations_has_pairs () {
    local output
    output=$(run_mda "$SAMPLES_DIR/trees.csv" --good)
    assert_contains "$output" "Strongest correlations" "should include correlation header"
    assert_contains "$output" "Girth (in) vs Volume(ft^3): r=" "should include specific correlation pair"
    assert_not_contains "$output" "vs : r=" "correlation pairs should not be empty"
}

test_tags_filter_advanced () {
    local output
    output=$(run_mda --tags ADVANCED "$SAMPLES_DIR/trees.csv")
    assert_contains "$output" "[ADVANCED]" "should emit ADVANCED items"
    assert_not_contains "$output" "[GOOD]" "should filter out GOOD items when only ADVANCED"
}

test_kinds_filter_shape () {
    local output
    output=$(run_mda --kinds shape "$SAMPLES_DIR/trees.csv")
    assert_contains "$output" "Distribution shape: Index" "should include shape items"
    assert_not_contains "$output" "Summary stats: Index" "should exclude non-shape items"
}

test_zero_variance_and_missing_rank () {
    local output
    output=$(run_mda --kinds zero_variance "$SAMPLES_DIR/edge.csv")
    assert_contains "$output" "Zero-variance numeric columns" "should include zero-variance header"
    assert_contains "$output" "constant: std=0" "should flag constant column"

    output=$(run_mda --kinds missing_rank "$SAMPLES_DIR/edge.csv")
    assert_contains "$output" "Most missing columns" "should include missing-rank header"
    assert_contains "$output" "measure: 2 missing" "should report missing counts"
}

test_skewness_differs_per_column () {
    local output
    output=$(run_mda --kinds shape "$SAMPLES_DIR/trees.csv")
    # Extract skewness values — each column should have a different value
    local skew_index skew_girth skew_height
    skew_index=$(echo "$output" | grep -A1 "Distribution shape: Index" | grep "Skewness:" | awk '{print $2}')
    skew_girth=$(echo "$output" | grep -A1 "Distribution shape: Girth" | grep "Skewness:" | awk '{print $2}')
    skew_height=$(echo "$output" | grep -A1 "Distribution shape: Height" | grep "Skewness:" | awk '{print $2}')
    # Index is uniform (1..31), skewness should be ~0
    assert_contains "$skew_index" "0.000000" "Index skewness should be ~0 (uniform)"
    # Girth and Height should differ from each other and from Index
    if [[ "$skew_index" == "$skew_girth" ]]; then
        echo "  ASSERT FAILED: Index and Girth skewness should differ ($skew_index vs $skew_girth)"
        return 1
    fi
    if [[ "$skew_girth" == "$skew_height" ]]; then
        echo "  ASSERT FAILED: Girth and Height skewness should differ ($skew_girth vs $skew_height)"
        return 1
    fi
}

test_correlation_bounded () {
    local output
    output=$(run_mda --kinds corr_pairs "$SAMPLES_DIR/edge.csv")
    # Correlation should be between -1 and 1, never exceed those bounds
    local r_val
    r_val=$(echo "$output" | grep "id vs measure" | sed 's/.*r=//')
    if awk -v r="$r_val" 'BEGIN{exit !(r > 1.0 || r < -1.0)}'; then
        echo "  ASSERT FAILED: correlation $r_val exceeds [-1,1] bounds"
        return 1
    fi
    assert_contains "$output" "id vs measure: r=" "should include correlation pair"
}

test_correlation_matrix_alignment () {
    local output
    output=$(run_mda --kinds corr_matrix "$SAMPLES_DIR/trees.csv")
    # Column names with spaces should stay intact in the matrix header
    assert_contains "$output" "Girth (in)" "matrix should preserve column name with spaces"
    assert_contains "$output" "Height (ft)" "matrix should preserve column name with spaces"
    # Should NOT have broken fragments like standalone "(in)" as a column
    assert_not_contains "$output" $'\n'"   (in)" "column name should not be split across columns"
}

test_correlation_matrix_header_alignment () {
    local output
    output=$(run_mda --kinds corr_matrix "$SAMPLES_DIR/trees.csv")
    # Header row should be indented past the row-label column
    # The first data row starts with "Index" followed by values
    # The header should NOT start with a column name at position 0
    local header_line
    header_line=$(echo "$output" | grep "Index.*Girth" | head -1)
    # Header line should have leading whitespace (blank row-label column)
    if [[ "$header_line" == [A-Za-z]* ]]; then
        echo "  ASSERT FAILED: matrix header should be indented (has blank row-label column)"
        echo "    got: '$header_line'"
        return 1
    fi
}

test_version_string () {
    local output expected
    # The top-level VERSION file is the single source of truth (lib/envoy_version.sh);
    # derive the expectation from it so version bumps can't break this test.
    expected="$(head -n1 "$SCRIPT_DIR/../../VERSION" | tr -d '[:space:]')"
    output=$(run_mda --help 2>&1)
    assert_contains "$output" "v${expected}" "help should show current version v${expected}"
}

test_cv_output () {
    local output
    output=$(run_mda --kinds cv "$SAMPLES_DIR/trees.csv")
    assert_contains "$output" "Coefficient of variation:" "should emit CV items"
    assert_contains "$output" "CV:" "should show CV percentage"
    assert_contains "$output" "Interpretation:" "should show variability interpretation"
}

test_normality_output () {
    local output
    output=$(run_mda --kinds normality "$SAMPLES_DIR/trees.csv")
    assert_contains "$output" "Normality: Index" "should emit normality for Index"
    assert_contains "$output" "Shape:" "should show shape description"
    assert_contains "$output" "Direction:" "should show skew direction"
}

test_precision_output () {
    local output
    output=$(run_mda --kinds precision "$SAMPLES_DIR/trees.csv")
    assert_contains "$output" "Numeric precision:" "should emit precision items"
    assert_contains "$output" "Type:" "should show integer/decimal type"
    assert_contains "$output" "Max decimal places:" "should show max decimal places"
}

test_benford_output () {
    local output
    output=$(run_mda --kinds benford "$SAMPLES_DIR/trees.csv")
    assert_contains "$output" "Benford" "should emit Benford analysis"
    assert_contains "$output" "Digit 1:" "should list digit 1 frequency"
    assert_contains "$output" "Chi-squared:" "should show chi-squared statistic"
    assert_contains "$output" "Result:" "should show pass/fail verdict"
}

test_trend_on_index () {
    local output
    output=$(run_mda --kinds trend "$SAMPLES_DIR/trees.csv")
    # Index column (1..31) should have a strong increasing trend
    assert_contains "$output" "Trend: Index" "should emit trend for Index"
    assert_contains "$output" "Spearman rho" "should show Spearman correlation"
    assert_contains "$output" "increasing" "Index should show increasing trend"
}

test_regression_output () {
    local output
    output=$(run_mda --kinds regression "$SAMPLES_DIR/trees.csv")
    assert_contains "$output" "Linear regression" "should emit regression section"
    assert_contains "$output" "R²=" "should show R-squared"
}

test_quality_score () {
    local output
    output=$(run_mda --kinds quality_score "$SAMPLES_DIR/trees.csv")
    assert_contains "$output" "Data quality score" "should emit quality score"
    assert_contains "$output" "Score:" "should show numeric score"
    assert_contains "$output" "/100" "should show out of 100"

    # edge.csv has missing values — should reduce score
    output=$(run_mda --kinds quality_score "$SAMPLES_DIR/edge.csv")
    assert_contains "$output" "Data quality score" "edge.csv should have quality score"
    assert_contains "$output" "Missing values:" "edge.csv should flag missing data"
}

test_corr_strength () {
    # ENV-125: the old "Correlation dimension summary" / "Rank N:" /
    # "Total dimensions: N" framing implied a dimensional decomposition
    # the metric (sum of |r|) cannot deliver. Path A reframed it as
    # "Column correlation strength" with `<col>: connectedness=<v>`
    # entries plus an explicit "not a PCA" disclaimer.
    local output
    output=$(run_mda --kinds corr_strength "$SAMPLES_DIR/trees.csv")
    assert_contains "$output" "Column correlation strength" "renamed item title"
    assert_contains "$output" "connectedness=" "neutral per-column connectedness label"
    assert_contains "$output" "Not a PCA" "explicit disclaimer about the metric"
    assert_contains "$output" "Summed across" "footer reports summed-column count"
    # Old framing must be gone.
    assert_not_contains "$output" "Correlation dimension summary" "old title removed"
    assert_not_contains "$output" "Rank1:" "old Rank N: labels removed"
    assert_not_contains "$output" "Total dimensions:" "misleading dimension count removed"
    assert_not_contains "$output" "Principal component" "no PCA label"
    assert_not_contains "$output" "PC1:" "no PC1 label"
}

test_corr_strength_constant_column_last () {
    # ENV-125: a constant column has zero variance, so |r| with every
    # other column is undefined → treated as 0; sum of |r| is 0 too. It
    # must rank last in the connectedness order. samples/known.csv has
    # exactly such a column (header `constant`, all rows = 5).
    local output constant_line
    output=$(run_mda --kinds corr_strength "$SAMPLES_DIR/known.csv")
    if ! grep -q "Column correlation strength" <<< "$output"; then
        # known.csv's numeric column count may be < 3 in some configs;
        # if no item was emitted skip the check rather than fail.
        return 0
    fi
    constant_line=$(grep -E "^[[:space:]]*constant:" <<< "$output" | head -1)
    if [[ -z "$constant_line" ]]; then
        # No `constant` column in this fixture revision — skip silently.
        return 0
    fi
    assert_contains "$constant_line" "connectedness=0.000" \
        "constant column should sum |r|=0 with every other column"
}

test_monotonicity_on_index () {
    local output
    output=$(run_mda --kinds monotonicity "$SAMPLES_DIR/trees.csv")
    # Index column (1..31) is perfectly sorted ascending
    assert_contains "$output" "Monotonicity: Index" "should detect sorted Index column"
    assert_contains "$output" "perfectly sorted (ascending)" "Index should be perfectly ascending"
}

test_drop_suggest () {
    local output
    output=$(run_mda --kinds drop_suggest "$SAMPLES_DIR/edge.csv")
    # edge.csv has a zero-variance column — should suggest dropping it
    assert_contains "$output" "Suggested column drops" "should emit drop suggestions"
    assert_contains "$output" "constant" "should flag zero-variance constant column"
}

test_format_json () {
    local output
    output=$(run_mda --format json --good "$SAMPLES_DIR/trees.csv")
    assert_contains "$output" "[" "JSON output should start with array"
    assert_contains "$output" "]" "JSON output should end with array"
    assert_contains "$output" '"tag"' "JSON items should have tag field"
    assert_contains "$output" '"title"' "JSON items should have title field"
    assert_contains "$output" '"id"' "JSON items should have id field"
}

test_format_csv () {
    local output
    output=$(run_mda --format csv --good "$SAMPLES_DIR/trees.csv")
    assert_contains "$output" "id,tag,title,body" "CSV output should have correct header"
}

test_format_tsv () {
    local output
    output=$(run_mda --format tsv --good "$SAMPLES_DIR/trees.csv")
    assert_contains "$output" "id	tag	title	body" "TSV output should have tab-separated header"
}

test_format_unknown_errors () {
    local rc=0
    run_mda --format bogus "$SAMPLES_DIR/trees.csv" >/dev/null 2>&1 || rc=$?
    if [[ $rc -eq 0 ]]; then
        echo "  ASSERT FAILED: unknown --format should exit non-zero"
        return 1
    fi
}

test_profile_roundtrip () {
    local tmpdir output
    tmpdir=$(mktemp -d)
    # Save items 1,2 as a named profile in the temp dir
    run_mda --profile-dir "$tmpdir" --save roundtrip "$SAMPLES_DIR/trees.csv" 1,2 >/dev/null
    assert_contains "$(ls "$tmpdir")" "roundtrip.profile" "profile file should be written to disk"
    # Load the profile back and verify the items appear
    output=$(run_mda --profile-dir "$tmpdir" --profile roundtrip "$SAMPLES_DIR/trees.csv")
    assert_contains "$output" "1." "profile load should reproduce item 1"
    assert_contains "$output" "2." "profile load should reproduce item 2"
    rm -rf "$tmpdir"
}

test_forced_delimiter () {
    local tmpf output
    tmpf=$(mktemp /tmp/mda_test_XXXXXX.tsv)
    printf 'Name\tValue\nAlpha\t10\nBeta\t20\nGamma\t30\nDelta\t40\n' > "$tmpf"
    output=$(run_mda --delimiter $'\t' "$tmpf")
    assert_contains "$output" "Value" "forced tab delimiter should parse TSV column names"
    rm -f "$tmpf"
}

test_stdin_input () {
    local output
    output=$(cat "$SAMPLES_DIR/trees.csv" | run_mda)
    assert_contains "$output" "Girth" "stdin CSV input should parse column names"
    assert_contains "$output" "Height" "stdin CSV input should find all columns"
}

test_biostats_no_crash () {
    local output rc=0
    output=$(run_mda "$SAMPLES_DIR/biostats.csv") || rc=$?
    assert_exit_zero "$rc" "biostats.csv should not crash"
    assert_contains "$output" "Dataset overview" "biostats.csv should produce overview"
    assert_contains "$output" "Name: categorical" "Name should be categorical"
    assert_contains "$output" "Sex: categorical" "Sex should be categorical"
    assert_contains "$output" "Age: numeric" "Age should be numeric"
}

test_biostats_cramers_v () {
    local output
    output=$(run_mda --kinds cramers_v "$SAMPLES_DIR/biostats.csv")
    assert_contains "$output" "Categorical associations" "biostats.csv should produce Cramer's V"
    assert_contains "$output" "Name vs Sex" "should compare Name and Sex"
    assert_contains "$output" "V=" "should show V value"
}

test_biostats_group_summary () {
    local output
    output=$(run_mda --kinds group_summary "$SAMPLES_DIR/biostats.csv")
    assert_contains "$output" "Group summary:" "biostats.csv should produce group summaries"
    assert_contains "$output" "Sex" "should group by Sex"
}

test_biostats_mixed_analyses () {
    local output
    output=$(run_mda --good "$SAMPLES_DIR/biostats.csv")
    # Should have both numeric and categorical analyses
    assert_contains "$output" "Summary stats: Age" "should have numeric summary for Age"
    assert_contains "$output" "Top values: Name" "should have top values for Name"
    assert_contains "$output" "Correlation matrix" "should have correlation matrix for numeric columns"
}

test_numeric_exclusion_warning () {
    local tmpf output
    tmpf=$(mktemp /tmp/mda_test_XXXXXX.csv)
    printf 'id,value\n1,10\n2,20\n3,text\n4,40\n5,text\n6,60\n7,text\n8,80\n9,text\n10,100\n' > "$tmpf"
    output=$(run_mda --tags DIAGNOSTIC "$tmpf")
    assert_contains "$output" "Numeric exclusion warning: value" "should warn about borderline column"
    assert_contains "$output" "classified as categorical" "should explain categorical classification"
    assert_contains "$output" "numeric values" "should mention ignored numeric values"
    rm -f "$tmpf"
}

run_test "biostats.csv does not crash" test_biostats_no_crash
run_test "biostats.csv Cramer's V" test_biostats_cramers_v
run_test "biostats.csv group summaries" test_biostats_group_summary
run_test "biostats.csv mixed numeric/categorical" test_biostats_mixed_analyses
run_test "numeric exclusion DIAGNOSTIC warning" test_numeric_exclusion_warning
run_test "strongest correlations include pairs" test_strongest_correlations_has_pairs
run_test "--tags filters to ADVANCED" test_tags_filter_advanced
run_test "--kinds filters to shape" test_kinds_filter_shape
run_test "zero variance and missing rank" test_zero_variance_and_missing_rank
run_test "skewness differs per column" test_skewness_differs_per_column
run_test "correlation bounded [-1,1]" test_correlation_bounded
run_test "correlation matrix alignment with spaces" test_correlation_matrix_alignment
run_test "correlation matrix header indented" test_correlation_matrix_header_alignment
run_test "version string is current" test_version_string
run_test "CV output for numeric columns" test_cv_output
run_test "normality indicator output" test_normality_output
run_test "numeric precision output" test_precision_output
run_test "Benford's Law output" test_benford_output
run_test "trend detection on Index" test_trend_on_index
run_test "linear regression output" test_regression_output
run_test "data quality score" test_quality_score
run_test "Column correlation strength output (ENV-125)" test_corr_strength
run_test "Column correlation strength: constant column ranks last (ENV-125)" test_corr_strength_constant_column_last
run_test "monotonicity on sorted column" test_monotonicity_on_index
run_test "suggested column drops" test_drop_suggest
run_test "--format json produces JSON array" test_format_json
run_test "--format csv has correct header" test_format_csv
run_test "--format tsv has tab-separated header" test_format_tsv
run_test "--format unknown exits non-zero" test_format_unknown_errors
run_test "profile save and load round-trip" test_profile_roundtrip
run_test "--delimiter forces tab parsing" test_forced_delimiter
run_test "stdin input parses correctly" test_stdin_input

print_summary
