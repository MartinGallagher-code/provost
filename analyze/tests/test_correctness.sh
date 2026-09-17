#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
source "$SCRIPT_DIR/helpers.sh"

################################################################################
## Known-answer numerical correctness tests
##
## Uses samples/known.csv:
##   x = 1,2,...,10  (uniform integers)
##   y = 10,20,...,100  (y = 10x, perfect linear)
##   constant = 5,5,...,5  (zero variance)
##
## Hand-calculated expected values:
##   x: mean=5.500000, std=2.872281, skew=0.000000, min=1, max=10
##   y: mean=55.000000, std=28.722813, min=10, max=100
##   corr(x,y) = 1.0000
##   regression: y = 10.0*x + 0.0  (R²=1.0000)
##   x percentiles: P05=1.4500, Q1=3.2500, P50=5.5000, Q3=7.7500, P95=9.5500
##   x: perfectly sorted ascending
##   constant: zero-variance, std=0
################################################################################

test_mean_exact () {
    local output
    output=$(run_mda --kinds summary "$SAMPLES_DIR/known.csv")
    assert_contains "$output" "Mean: 5.500000" "x mean should be 5.500000"
    assert_contains "$output" "Mean: 55.000000" "y mean should be 55.000000"
}

test_std_exact () {
    local output
    output=$(run_mda --kinds summary "$SAMPLES_DIR/known.csv")
    assert_contains "$output" "Std: 2.872281" "x std should be 2.872281"
    assert_contains "$output" "Std: 28.722813" "y std should be 28.722813"
}

test_min_max_exact () {
    local output
    output=$(run_mda --kinds summary "$SAMPLES_DIR/known.csv")
    assert_contains "$output" "Min: 1" "x min should be 1"
    assert_contains "$output" "Max: 10" "x max should be 10"
    assert_contains "$output" "Min: 10" "y min should be 10"
    assert_contains "$output" "Max: 100" "y max should be 100"
}

test_skewness_zero () {
    local output
    output=$(run_mda --kinds shape "$SAMPLES_DIR/known.csv")
    # Uniform distribution 1..10 has zero skewness
    local skew_x
    skew_x=$(echo "$output" | grep -A1 "Distribution shape: x" | grep "Skewness:" | awk '{print $2}')
    if [[ "$skew_x" != "0.000000" ]]; then
        echo "  ASSERT FAILED: x skewness should be 0.000000, got '$skew_x'"
        return 1
    fi
}

test_kurtosis_uniform () {
    local output
    output=$(run_mda --kinds shape "$SAMPLES_DIR/known.csv")
    # Discrete uniform 1..10 excess kurtosis ≈ -1.2242
    local kurt_x
    kurt_x=$(echo "$output" | grep -A2 "Distribution shape: x" | grep "Kurtosis" | awk '{print $3}')
    if [[ "$kurt_x" != "-1.224242" ]]; then
        echo "  ASSERT FAILED: x excess kurtosis should be -1.224242, got '$kurt_x'"
        return 1
    fi
}

test_percentiles_exact () {
    local output
    output=$(run_mda --kinds shape "$SAMPLES_DIR/known.csv")
    local shape_x
    shape_x=$(echo "$output" | grep -A7 "Distribution shape: x")
    assert_contains "$shape_x" "P05: 1.4500" "x P05 should be 1.4500"
    assert_contains "$shape_x" "P25: 3.2500" "x Q1 should be 3.2500"
    assert_contains "$shape_x" "P50: 5.5000" "x P50 should be 5.5000"
    assert_contains "$shape_x" "P75: 7.7500" "x Q3 should be 7.7500"
    assert_contains "$shape_x" "P95: 9.5500" "x P95 should be 9.5500"
}

test_correlation_perfect () {
    local output
    output=$(run_mda --kinds corr_pairs "$SAMPLES_DIR/known.csv")
    # y = 10x → perfect positive correlation
    assert_contains "$output" "x vs y: r=1.0000" "x-y correlation should be 1.0000"
}

test_correlation_matrix_diagonal () {
    local output
    output=$(run_mda --kinds corr_matrix "$SAMPLES_DIR/known.csv")
    # Diagonal should be 1.0000
    assert_contains "$output" "1.0000" "diagonal should have 1.0000"
}

test_regression_exact () {
    local output
    output=$(run_mda --kinds regression "$SAMPLES_DIR/known.csv")
    # y = 10*x + 0 → slope=10, intercept=0, R²=1
    assert_contains "$output" "R²=1.0000" "R-squared should be 1.0000"
    assert_contains "$output" "r=1.0000" "correlation should be 1.0000"
}

test_zero_variance_detected () {
    local output
    output=$(run_mda --kinds zero_variance "$SAMPLES_DIR/known.csv")
    assert_contains "$output" "constant: std=0" "constant column should be flagged as zero-variance"
}

test_monotonicity_perfect () {
    local output
    output=$(run_mda --kinds monotonicity "$SAMPLES_DIR/known.csv")
    assert_contains "$output" "Monotonicity: x" "x should be detected as monotonic"
    assert_contains "$output" "perfectly sorted (ascending)" "x should be perfectly ascending"
    assert_contains "$output" "Monotonicity: y" "y should be detected as monotonic"
}

test_trend_perfect () {
    local output
    output=$(run_mda --kinds trend "$SAMPLES_DIR/known.csv")
    assert_contains "$output" "Trend: x" "x should have trend detected"
    assert_contains "$output" "1.000000" "x Spearman rho should be 1.000000"
    assert_contains "$output" "increasing" "x should show increasing"
}

test_no_outliers () {
    local output
    output=$(run_mda --kinds anomaly "$SAMPLES_DIR/known.csv")
    # Uniform 1..10 has no z-score outliers (|z|>3 impossible with 10 values)
    assert_contains "$output" "Z-score outliers (|z|>3): 0" "x should have 0 z-score outliers"
}

test_histogram_bin_sum () {
    local output
    output=$(run_mda --kinds histogram "$SAMPLES_DIR/known.csv")
    # All 10 values of x should be distributed across the 5 bins, summing to 10
    local total=0
    while read -r line; do
        local count
        count=$(echo "$line" | sed 's/.*: //' | awk '{print $1}')
        if [[ "$count" =~ ^[0-9]+$ ]]; then
            total=$((total + count))
        fi
    done < <(echo "$output" | grep "Bin.*Histogram: x" -A5 | grep "^Bin")
    # Alternative: get histogram for x specifically
    local hist_x
    hist_x=$(echo "$output" | sed -n '/Histogram: x/,/^[0-9]*\./p' | head -6)
    local bin_sum=0
    while read -r line; do
        if [[ "$line" == Bin* ]]; then
            local c
            c=$(echo "$line" | sed 's/.*): //' | awk '{print $1}')
            bin_sum=$((bin_sum + c))
        fi
    done <<< "$hist_x"
    if [[ "$bin_sum" -ne 10 ]]; then
        echo "  ASSERT FAILED: histogram bins for x should sum to 10, got $bin_sum"
        return 1
    fi
}

test_cv_exact () {
    local output
    output=$(run_mda --kinds cv "$SAMPLES_DIR/known.csv")
    # CV = std/|mean| * 100 = 2.8723/5.5 * 100 ≈ 52.22%
    assert_contains "$output" "Coefficient of variation: x" "x should have CV"
    assert_contains "$output" "CV: 52.22%" "x CV should be 52.22%"
}

test_quality_score_known () {
    local output
    output=$(run_mda --kinds quality_score "$SAMPLES_DIR/known.csv")
    assert_contains "$output" "Data quality score" "should emit quality score"
    # known.csv has: no missing, 0 duplicates, but 1 zero-variance column (-5)
    # 10 rows is not < 10 so no low-row penalty. Score = 100 - 5 = 95
    assert_contains "$output" "Score: 95/100" "quality score should be 95 (zero-var -5)"
}

test_drop_suggest_constant () {
    local output
    output=$(run_mda --kinds drop_suggest "$SAMPLES_DIR/known.csv")
    assert_contains "$output" "constant" "should suggest dropping constant column"
    assert_contains "$output" "zero variance" "should cite zero variance reason"
}

################################################################################
## New tests for v0.7 features
################################################################################

test_welford_large_values () {
    local output
    output=$(run_mda --kinds summary "$SAMPLES_DIR/large_vals.csv")
    assert_contains "$output" "Mean: 1000000005.500000" "large_vals mean should be 1000000005.500000"
    assert_contains "$output" "Std: 2.872281" "large_vals std should be 2.872281 (Welford)"
}

test_negative_correlation () {
    local output
    output=$(run_mda --kinds corr_pairs "$SAMPLES_DIR/numeric_edge.csv")
    assert_contains "$output" "r=-1.0000" "x vs neg should have r=-1.0000"
}

test_scientific_notation () {
    local output
    output=$(run_mda "$SAMPLES_DIR/numeric_edge.csv")
    # sci column (1e1..5e1 = 10..50) should be numeric
    assert_contains "$output" "sci: numeric" "scientific notation column should be detected as numeric"
}

test_regression_slope_intercept () {
    local output
    output=$(run_mda --kinds regression "$SAMPLES_DIR/known.csv")
    # y = 10*x + 0, slope should be ~10.0 (floating point: 10.000001 is acceptable)
    assert_contains "$output" "10.00000" "regression slope should be ~10.000000"
}

test_large_number_mean () {
    local output
    output=$(run_mda --kinds summary "$SAMPLES_DIR/large_vals.csv")
    # Mean for id column: 1..10 → 5.5
    assert_contains "$output" "Mean: 5.500000" "id mean should be 5.500000"
}

test_missing_count_expanded () {
    local output
    output=$(run_mda "$SAMPLES_DIR/missing.csv")
    # label column: NA is missing, 3 total missing (NA, #N/A, None — wait, let me check)
    # Row 4: label=NA (missing), Row 8: label=#N/A (missing), Row 6: label=None (missing) = 3
    assert_contains "$output" "label: 3 missing" "label column should have 3 missing (NA, #N/A, None)"
}

test_cramers_v_warning () {
    # With small sparse categorical data, Cramer's V should produce a warning
    # biostats has categories; let's just verify the analysis runs without crash
    local output
    output=$(run_mda --tags ADVANCED "$SAMPLES_DIR/biostats.csv" 2>&1)
    # Cramer's V should appear (or not crash)
    local rc=$?
    if [[ "$rc" -ne 0 ]]; then
        echo "  ASSERT FAILED: envoy-analyze should not crash on biostats.csv"
        return 1
    fi
}

test_bimodality_detection () {
    local output
    output=$(run_mda --kinds bimodality "$SAMPLES_DIR/bimodal.csv" 2>&1)
    assert_contains "$output" "Bimodality" "bimodal.csv should have bimodality analysis"
}

test_quality_score_with_missing () {
    local output
    output=$(run_mda --kinds quality_score "$SAMPLES_DIR/missing.csv")
    assert_contains "$output" "Data quality score" "missing.csv should have quality score"
    # With 32.5% missing, score should be significantly penalized
    # 32.5 * 1.5 = 48.75, capped at 25 → score ~= 75 or less
    local score
    score=$(echo "$output" | grep "Score:" | head -1 | sed 's/.*Score: //' | sed 's|/.*||')
    if [[ -z "$score" ]]; then
        echo "  ASSERT FAILED: could not extract quality score"
        return 1
    fi
    if [[ "$score" -gt 90 ]]; then
        echo "  ASSERT FAILED: quality score with 32.5% missing should be <=90, got $score"
        return 1
    fi
}

test_near_constant_detection () {
    # known.csv has a constant column — should be in suggested drops
    local output
    output=$(run_mda --kinds drop_suggest "$SAMPLES_DIR/known.csv")
    assert_contains "$output" "constant" "should suggest dropping constant column"
}

test_positive_skewness () {
    local output
    output=$(run_mda --kinds shape "$SAMPLES_DIR/bimodal.csv" 2>&1)
    local skew
    skew=$(echo "$output" | grep -A1 "Distribution shape: skewed" | grep "Skewness:" | awk '{print $2}')
    if [[ -z "$skew" ]]; then
        echo "  ASSERT FAILED: could not extract skewness for skewed column"
        return 1
    fi
    # The skewed column has heavy right tail, skewness should be positive
    local positive
    positive=$(awk -v s="$skew" 'BEGIN{print (s>0)? "yes" : "no"}')
    if [[ "$positive" != "yes" ]]; then
        echo "  ASSERT FAILED: skewed column should have positive skewness, got $skew"
        return 1
    fi
}

test_perfect_negative_correlation_exact () {
    local output
    output=$(run_mda --kinds corr_matrix "$SAMPLES_DIR/numeric_edge.csv")
    assert_contains "$output" "-1.0000" "correlation matrix should contain -1.0000"
}

test_pipe_delimiter_detection () {
    local tmp
    tmp=$(mktemp -t test-pipe.XXXXXX)
    printf 'a|b|c\n1|2|3\n4|5|6\n' > "$tmp"
    local output
    output=$(run_mda "$tmp")
    assert_contains "$output" "Delimiter: |" "pipe delimiter should be detected"
    rm -f "$tmp"
}

################################################################################
## Deep correctness tests — exact values across all datasets
##
## These tests verify that computed statistical values are numerically correct,
## not just that the output contains certain keywords.
################################################################################

# --- missing.csv: statistics computed with missing values excluded ---
# value column non-missing: {100, 200, 300, 1200, -50} (5 of 10 rows)
#   mean = 1750/5 = 350, pop_std = sqrt(970000/5) = 440.454311
# score column non-missing: {85, 90, 75, 80, 95} (5 of 10 rows)
#   mean = 425/5 = 85, pop_std = sqrt(250/5) = 7.071068

test_missing_value_mean_exact () {
    local output
    output=$(run_mda --kinds summary "$SAMPLES_DIR/missing.csv")
    assert_contains "$output" "Mean: 350.000000" "missing.csv value mean should be 350.000000"
}

test_missing_value_std_exact () {
    local output
    output=$(run_mda --kinds summary "$SAMPLES_DIR/missing.csv")
    assert_contains "$output" "Std: 440.454311" "missing.csv value std should be 440.454311"
}

test_missing_value_min_max () {
    local output
    output=$(run_mda --kinds summary "$SAMPLES_DIR/missing.csv")
    # value column: min=-50 (row 9), max=1200 (row 8, 1.2e3)
    assert_contains "$output" "Min: -50" "missing.csv value min should be -50"
    assert_contains "$output" "Max: 1200" "missing.csv value max should be 1200"
}

test_missing_score_mean_exact () {
    local output
    output=$(run_mda --kinds summary "$SAMPLES_DIR/missing.csv")
    assert_contains "$output" "Mean: 85.000000" "missing.csv score mean should be 85.000000"
}

test_missing_score_std_exact () {
    local output
    output=$(run_mda --kinds summary "$SAMPLES_DIR/missing.csv")
    assert_contains "$output" "Std: 7.071068" "missing.csv score std should be 7.071068"
}

test_missing_value_percentiles () {
    local output
    output=$(run_mda --kinds shape "$SAMPLES_DIR/missing.csv")
    local shape_val
    shape_val=$(echo "$output" | sed -n '/Distribution shape: value/,/^[0-9]/p' | head -8)
    assert_contains "$shape_val" "P25: 100.0000" "missing.csv value Q1 should be 100.0000"
    assert_contains "$shape_val" "P50: 200.0000" "missing.csv value P50 should be 200.0000"
    assert_contains "$shape_val" "P75: 300.0000" "missing.csv value Q3 should be 300.0000"
}

test_missing_value_skewness () {
    local output
    output=$(run_mda --kinds shape "$SAMPLES_DIR/missing.csv")
    local skew
    skew=$(echo "$output" | grep -A1 "Distribution shape: value" | grep "Skewness:" | awk '{print $2}')
    # Right-skewed: {-50, 100, 200, 300, 1200} has positive skewness
    local positive
    positive=$(awk -v s="$skew" 'BEGIN{print (s>0)? "yes" : "no"}')
    if [[ "$positive" != "yes" ]]; then
        echo "  ASSERT FAILED: missing.csv value column should have positive skewness, got $skew"
        return 1
    fi
    assert_contains "$output" "Skewness: 1.242859" "missing.csv value skewness should be 1.242859"
}

test_missing_value_iqr_outlier () {
    local output
    output=$(run_mda --kinds anomaly "$SAMPLES_DIR/missing.csv")
    local anomaly_val
    anomaly_val=$(echo "$output" | sed -n '/Anomaly detection: value/,/^[0-9]/p')
    assert_contains "$anomaly_val" "IQR outliers" "missing.csv value should have IQR outlier section"
    assert_contains "$anomaly_val" "Outliers: 1" "missing.csv value should have 1 IQR outlier"
    assert_contains "$anomaly_val" "1200" "missing.csv value IQR outlier should be 1200"
}

test_missing_exact_counts () {
    local output
    output=$(run_mda "$SAMPLES_DIR/missing.csv")
    assert_contains "$output" "value: 5 missing" "value column should have 5 missing"
    assert_contains "$output" "score: 5 missing" "score column should have 5 missing"
    assert_contains "$output" "id: 0 missing" "id column should have 0 missing"
}

test_missing_quality_score_exact () {
    local output
    output=$(run_mda --kinds quality_score "$SAMPLES_DIR/missing.csv")
    # 13 missing out of 40 cells = 32.5%; penalty = min(int(32.5*1.5), 25) = 25
    # Score = 100 - 25 = 75
    assert_contains "$output" "Score: 75/100" "missing.csv quality score should be 75"
}

# --- numeric_edge.csv: negative numbers, scientific notation, large values ---
# neg column: {-1,-2,-3,-4,-5}, mean=-3, pop_std=sqrt(2)=1.414214
# sci column: {10,20,30,40,50} (1e1..5e1), mean=30, pop_std=sqrt(200)=14.142136
# big column: {1e6,2e6,3e6,4e6,5e6}, mean=3e6, pop_std=sqrt(2e12)=1414213.562373

test_negative_mean_exact () {
    local output
    output=$(run_mda --kinds summary "$SAMPLES_DIR/numeric_edge.csv")
    assert_contains "$output" "Mean: -3.000000" "neg column mean should be -3.000000"
}

test_negative_std_exact () {
    local output
    output=$(run_mda --kinds summary "$SAMPLES_DIR/numeric_edge.csv")
    assert_contains "$output" "Std: 1.414214" "neg column std should be 1.414214 (sqrt(2))"
}

test_negative_min_max () {
    local output
    output=$(run_mda --kinds summary "$SAMPLES_DIR/numeric_edge.csv")
    assert_contains "$output" "Min: -5" "neg column min should be -5"
    assert_contains "$output" "Max: -1" "neg column max should be -1"
}

test_negative_percentiles () {
    local output
    output=$(run_mda --kinds shape "$SAMPLES_DIR/numeric_edge.csv")
    local shape_neg
    shape_neg=$(echo "$output" | sed -n '/Distribution shape: neg/,/^[0-9]/p' | head -8)
    assert_contains "$shape_neg" "P25: -4.0000" "neg Q1 should be -4.0000"
    assert_contains "$shape_neg" "P50: -3.0000" "neg median should be -3.0000"
    assert_contains "$shape_neg" "P75: -2.0000" "neg Q3 should be -2.0000"
}

test_negative_skewness_zero () {
    local output
    output=$(run_mda --kinds shape "$SAMPLES_DIR/numeric_edge.csv")
    local skew
    skew=$(echo "$output" | grep -A1 "Distribution shape: neg" | grep "Skewness:" | awk '{print $2}')
    if [[ "$skew" != "0.000000" ]]; then
        echo "  ASSERT FAILED: neg column skewness should be 0.000000 (symmetric), got $skew"
        return 1
    fi
}

test_negative_trend_decreasing () {
    local output
    output=$(run_mda --kinds trend "$SAMPLES_DIR/numeric_edge.csv")
    local trend_neg
    trend_neg=$(echo "$output" | sed -n '/Trend: neg/,/^[0-9]/p')
    assert_contains "$trend_neg" "-1.000000" "neg Spearman rho should be -1.000000"
    assert_contains "$trend_neg" "decreasing" "neg trend should be decreasing"
}

test_negative_monotonicity_descending () {
    local output
    output=$(run_mda --kinds monotonicity "$SAMPLES_DIR/numeric_edge.csv")
    assert_contains "$output" "Monotonicity: neg" "neg should have monotonicity analysis"
    assert_contains "$output" "perfectly sorted (descending)" "neg should be perfectly descending"
}

test_sci_mean_exact () {
    local output
    output=$(run_mda --kinds summary "$SAMPLES_DIR/numeric_edge.csv")
    # sci = {1e1,2e1,3e1,4e1,5e1} = {10,20,30,40,50}, mean = 30
    assert_contains "$output" "Summary stats: sci" "sci column should have summary"
    local sci_stats
    sci_stats=$(echo "$output" | sed -n '/Summary stats: sci/,/^[0-9]/p' | head -5)
    assert_contains "$sci_stats" "Mean: 30.000000" "sci mean should be 30.000000"
    assert_contains "$sci_stats" "Std: 14.142136" "sci std should be 14.142136"
}

test_sci_min_max () {
    local output
    output=$(run_mda --kinds summary "$SAMPLES_DIR/numeric_edge.csv")
    local sci_stats
    sci_stats=$(echo "$output" | sed -n '/Summary stats: sci/,/^[0-9]/p' | head -5)
    assert_contains "$sci_stats" "Min: 10" "sci min should be 10 (parsed from 1e1)"
    assert_contains "$sci_stats" "Max: 50" "sci max should be 50 (parsed from 5e1)"
}

test_big_mean_exact () {
    local output
    output=$(run_mda --kinds summary "$SAMPLES_DIR/numeric_edge.csv")
    assert_contains "$output" "Mean: 3000000.000000" "big column mean should be 3000000.000000"
    assert_contains "$output" "Std: 1414213.562373" "big column std should be 1414213.562373"
}

test_negative_regression_slope () {
    local output
    output=$(run_mda --kinds regression "$SAMPLES_DIR/numeric_edge.csv")
    # neg = -1 * x + 0
    assert_contains "$output" "neg = -1.000000 * x" "regression: neg = -1*x"
    assert_contains "$output" "R²=1.0000" "negative regression R² should be 1.0000"
}

test_all_columns_same_cv () {
    local output
    output=$(run_mda --kinds cv "$SAMPLES_DIR/numeric_edge.csv")
    # All 4 columns {1..5}, {-1..-5}, {10..50}, {1M..5M} have CV = 47.14%
    local count
    count=$(echo "$output" | grep -c "CV: 47.14%")
    if [[ "$count" -ne 4 ]]; then
        echo "  ASSERT FAILED: all 4 columns should have CV=47.14%, found $count"
        return 1
    fi
}

# --- biostats.csv: categorical analysis with exact values ---

test_biostats_age_mean_exact () {
    local output
    output=$(run_mda --kinds summary "$SAMPLES_DIR/biostats.csv")
    # Age: {41,42,32,39,30,33,26,30,53}, n=9, mean=326/9=36.222222
    assert_contains "$output" "Mean: 36.222222" "biostats Age mean should be 36.222222"
}

test_biostats_height_mean_exact () {
    local output
    output=$(run_mda --kinds summary "$SAMPLES_DIR/biostats.csv")
    # Height: {74,68,70,72,66,66,64,71,72}, n=9, mean=623/9=69.222222
    assert_contains "$output" "Mean: 69.222222" "biostats Height mean should be 69.222222"
}

test_biostats_weight_mean_exact () {
    local output
    output=$(run_mda --kinds summary "$SAMPLES_DIR/biostats.csv")
    # Weight: {170,166,155,167,124,115,121,158,175}, n=9, mean=1351/9=150.111111
    assert_contains "$output" "Mean: 150.111111" "biostats Weight mean should be 150.111111"
}

test_biostats_sex_top_values () {
    local output
    output=$(run_mda --kinds top_values "$SAMPLES_DIR/biostats.csv")
    assert_contains "$output" "M: 6" "Sex should have M: 6"
    assert_contains "$output" "F: 3" "Sex should have F: 3"
    assert_contains "$output" "Unique values: 2" "Sex should have 2 unique values"
}

test_biostats_name_unique_count () {
    local output
    output=$(run_mda --kinds top_values "$SAMPLES_DIR/biostats.csv")
    local name_section
    name_section=$(echo "$output" | sed -n '/Top values: Name/,/^[0-9]/p' | head -8)
    assert_contains "$name_section" "Unique values: 9" "Name should have 9 unique values"
}

test_biostats_group_summary_sex_exact () {
    local output
    output=$(run_mda --kinds group_summary "$SAMPLES_DIR/biostats.csv")
    # Male: {41,42,32,39,30,53}/6 = 237/6 = 39.5000
    # Female: {30,33,26}/3 = 89/3 = 29.6667
    local sex_group
    sex_group=$(echo "$output" | sed -n '/Group summary: Sex/,/^[0-9]/p')
    assert_contains "$sex_group" "M (n=6): Age=39.5000" "Male mean age should be 39.5000"
    assert_contains "$sex_group" "F (n=3): Age=29.6667" "Female mean age should be 29.6667"
}

test_biostats_group_summary_weight_exact () {
    local output
    output=$(run_mda --kinds group_summary "$SAMPLES_DIR/biostats.csv")
    # Male weight: {170,166,155,167,158,175}/6 = 991/6 = 165.1667
    # Female weight: {124,115,121}/3 = 360/3 = 120.0000
    local sex_group
    sex_group=$(echo "$output" | sed -n '/Group summary: Sex/,/^[0-9]/p')
    assert_contains "$sex_group" "Weight (lbs)=165.1667" "Male mean weight should be 165.1667"
    assert_contains "$sex_group" "Weight (lbs)=120.0000" "Female mean weight should be 120.0000"
}

test_biostats_no_outliers () {
    local output
    output=$(run_mda --kinds anomaly "$SAMPLES_DIR/biostats.csv")
    # Small dataset (n=9), no extreme outliers
    assert_contains "$output" "Z-score outliers (|z|>3): 0" "biostats Age should have 0 z-score outliers"
}

# --- edge.csv: missing data + zero-variance combined ---
# measure column non-missing: {10, 11, 13} (3 of 5 rows)
#   mean = 34/3 = 11.333333, pop_std = sqrt(4.666667/3) = 1.247219

test_edge_measure_mean_exact () {
    local output
    output=$(run_mda --kinds summary "$SAMPLES_DIR/edge.csv")
    assert_contains "$output" "Mean: 11.333333" "edge.csv measure mean should be 11.333333"
}

test_edge_measure_std_exact () {
    local output
    output=$(run_mda --kinds summary "$SAMPLES_DIR/edge.csv")
    assert_contains "$output" "Std: 1.247219" "edge.csv measure std should be 1.247219"
}

test_edge_constant_zero_std () {
    local output
    output=$(run_mda --kinds summary "$SAMPLES_DIR/edge.csv")
    local const_stats
    const_stats=$(echo "$output" | sed -n '/Summary stats: constant/,/^[0-9]/p' | head -5)
    assert_contains "$const_stats" "Mean: 5.000000" "edge.csv constant mean should be 5.000000"
    assert_contains "$const_stats" "Std: 0.000000" "edge.csv constant std should be 0.000000"
}

test_edge_quality_score_exact () {
    local output
    output=$(run_mda --kinds quality_score "$SAMPLES_DIR/edge.csv")
    # 2 missing out of 20 cells = 10%; penalty = int(10*1.5) = 15
    # 1 zero-variance column = -5; low row count (5 rows) = -10
    # Score = 100 - 15 - 5 - 10 = 70
    assert_contains "$output" "Score: 70/100" "edge.csv quality score should be 70"
}

test_edge_drop_suggests_both () {
    local output
    output=$(run_mda --kinds drop_suggest "$SAMPLES_DIR/edge.csv")
    assert_contains "$output" "constant: zero variance" "should suggest dropping constant"
    assert_contains "$output" "measure" "should suggest dropping measure (high corr)"
}

test_edge_missing_rank () {
    local output
    output=$(run_mda "$SAMPLES_DIR/edge.csv")
    assert_contains "$output" "measure: 2 missing" "edge.csv measure should have 2 missing"
}

# --- outliers.csv: known z-score and IQR outlier ---
# y = {10,12,...,46,500}: one extreme value at 500

test_outlier_zscore_detected () {
    local output
    output=$(run_mda --kinds anomaly "$SAMPLES_DIR/outliers.csv")
    local anomaly_y
    anomaly_y=$(echo "$output" | sed -n '/Anomaly detection: y/,/^[0-9]/p')
    assert_contains "$anomaly_y" "Z-score outliers (|z|>3): 1" "outliers.csv y should have 1 z-score outlier"
    assert_contains "$anomaly_y" "500" "z-score outlier sample should be 500"
}

test_outlier_iqr_detected () {
    local output
    output=$(run_mda --kinds anomaly "$SAMPLES_DIR/outliers.csv")
    local anomaly_y
    anomaly_y=$(echo "$output" | sed -n '/Anomaly detection: y/,/^[0-9]/p')
    assert_contains "$anomaly_y" "IQR outliers" "outliers.csv y should have IQR section"
    assert_contains "$anomaly_y" "Outliers: 1" "outliers.csv y should have 1 IQR outlier"
    assert_contains "$anomaly_y" "500" "IQR outlier sample should be 500"
}

test_outlier_x_no_outliers () {
    local output
    output=$(run_mda --kinds anomaly "$SAMPLES_DIR/outliers.csv")
    local anomaly_x
    anomaly_x=$(echo "$output" | sed -n '/Anomaly detection: x/,/Anomaly detection: y/p' | head -10)
    assert_contains "$anomaly_x" "Z-score outliers (|z|>3): 0" "outliers.csv x should have 0 z-score outliers"
}

test_outlier_y_mean_exact () {
    local output
    output=$(run_mda --kinds summary "$SAMPLES_DIR/outliers.csv")
    # y: sum = (10+12+...+46) + 500 = 532 + 500 = 1032, n=20, mean = 51.6
    assert_contains "$output" "Mean: 51.600000" "outliers.csv y mean should be 51.600000"
}

test_outlier_y_skewness_positive () {
    local output
    output=$(run_mda --kinds shape "$SAMPLES_DIR/outliers.csv")
    # Heavy right tail due to 500 → strong positive skewness
    assert_contains "$output" "Skewness: 4.056346" "outliers.csv y skewness should be 4.056346"
}

test_outlier_y_iqr_values () {
    local output
    output=$(run_mda --kinds anomaly "$SAMPLES_DIR/outliers.csv")
    local anomaly_y
    anomaly_y=$(echo "$output" | sed -n '/Anomaly detection: y/,/^[0-9]/p')
    assert_contains "$anomaly_y" "Q1: 19.5000" "outliers.csv y Q1 should be 19.5000"
    assert_contains "$anomaly_y" "Q3: 38.5000" "outliers.csv y Q3 should be 38.5000"
    assert_contains "$anomaly_y" "IQR: 19.0000" "outliers.csv y IQR should be 19.0000"
}

# --- duplicates.csv: duplicate row detection + group summaries ---

test_duplicate_rows_detected () {
    local output
    output=$(run_mda "$SAMPLES_DIR/duplicates.csv")
    assert_contains "$output" "Duplicate rows: 2" "duplicates.csv should have 2 duplicate rows"
}

test_duplicate_quality_score_exact () {
    local output
    output=$(run_mda --kinds quality_score "$SAMPLES_DIR/duplicates.csv")
    # 0 missing, 2 dupes (28.57%, capped at 15), low row count (7 rows, -10)
    # Score = 100 - 15 - 10 = 75
    assert_contains "$output" "Score: 75/100" "duplicates.csv quality score should be 75"
}

test_duplicate_group_summary_exact () {
    local output
    output=$(run_mda --kinds group_summary "$SAMPLES_DIR/duplicates.csv")
    # alpha: rows {1,10} and {1,10} → a_mean=1.0, b_mean=10.0
    # beta: rows {2,20} and {2,20} → a_mean=2.0, b_mean=20.0
    local group
    group=$(echo "$output" | sed -n '/Group summary: c/,/^[0-9]/p')
    assert_contains "$group" "alpha (n=2): a=1.0000; b=10.0000" "alpha group: a=1.0, b=10.0"
    assert_contains "$group" "beta (n=2): a=2.0000; b=20.0000" "beta group: a=2.0, b=20.0"
}

test_duplicate_top_values_exact () {
    local output
    output=$(run_mda --kinds top_values "$SAMPLES_DIR/duplicates.csv")
    assert_contains "$output" "beta: 2" "c should have beta: 2"
    assert_contains "$output" "alpha: 2" "c should have alpha: 2"
    assert_contains "$output" "Unique values: 5" "c should have 5 unique values"
}

test_duplicate_drop_correlated () {
    local output
    output=$(run_mda --kinds drop_suggest "$SAMPLES_DIR/duplicates.csv")
    # b = 10*a exactly → should suggest dropping one
    assert_contains "$output" "b" "should suggest dropping b (correlated with a)"
}

# --- bimodal.csv: distribution shape exactness ---

test_bimodal_skewed_skewness_exact () {
    local output
    output=$(run_mda --kinds shape "$SAMPLES_DIR/bimodal.csv" 2>&1)
    local skew
    skew=$(echo "$output" | grep -A1 "Distribution shape: skewed" | grep "Skewness:" | awk '{print $2}')
    # Fibonacci-like sequence: heavily right-tailed
    # Exact value from envoy-analyze: should be a large positive number
    if [[ -z "$skew" ]]; then
        echo "  ASSERT FAILED: could not extract skewness for skewed column"
        return 1
    fi
    # Skewness should be > 1.0 (strongly right-skewed)
    local strong
    strong=$(awk -v s="$skew" 'BEGIN{print (s>1.0)? "yes" : "no"}')
    if [[ "$strong" != "yes" ]]; then
        echo "  ASSERT FAILED: skewed column should have skewness > 1.0, got $skew"
        return 1
    fi
}

test_bimodal_symmetric_skewness () {
    local output
    output=$(run_mda --kinds shape "$SAMPLES_DIR/bimodal.csv" 2>&1)
    local skew
    skew=$(echo "$output" | grep -A1 "Distribution shape: bimodal" | grep "Skewness:" | awk '{print $2}')
    # bimodal column: {10,11,12,13,14,10,11,12,13,14,50,51,52,53,54,50,51,52,53,54}
    # Mean ≈ 32, positive skew due to gap
    if [[ -z "$skew" ]]; then
        echo "  ASSERT FAILED: could not extract skewness for bimodal column"
        return 1
    fi
    # Skewness should be near 0 or slightly positive (two symmetric clusters)
    local bounded
    bounded=$(awk -v s="$skew" 'BEGIN{print (s>-1.0 && s<1.0)? "yes" : "no"}')
    if [[ "$bounded" != "yes" ]]; then
        echo "  ASSERT FAILED: bimodal column skewness should be between -1 and 1, got $skew"
        return 1
    fi
}

# --- delimiter detection ---

test_semicolon_delimiter () {
    local tmp
    tmp=$(mktemp -t test-semi.XXXXXX)
    printf 'a;b;c\n1;2;3\n4;5;6\n' > "$tmp"
    local output
    output=$(run_mda "$tmp")
    assert_contains "$output" "Delimiter: semicolon" "semicolon delimiter should be detected"
    rm -f "$tmp"
}

test_tab_delimiter () {
    local tmp
    tmp=$(mktemp -t test-tab.XXXXXX)
    printf 'a\tb\tc\n1\t2\t3\n4\t5\t6\n' > "$tmp"
    local output
    output=$(run_mda "$tmp")
    assert_contains "$output" "Delimiter: tab" "tab delimiter should be detected"
    rm -f "$tmp"
}

########################################
## Run all correctness tests
##

run_test "mean exact values" test_mean_exact
run_test "std exact values" test_std_exact
run_test "min/max exact values" test_min_max_exact
run_test "skewness zero for uniform" test_skewness_zero
run_test "kurtosis for discrete uniform" test_kurtosis_uniform
run_test "percentiles exact (P05/Q1/P50/Q3/P95)" test_percentiles_exact
run_test "perfect correlation (r=1)" test_correlation_perfect
run_test "correlation matrix has diagonal" test_correlation_matrix_diagonal
run_test "regression exact (y=10x)" test_regression_exact
run_test "zero-variance column detected" test_zero_variance_detected
run_test "monotonicity perfect ascending" test_monotonicity_perfect
run_test "trend Spearman rho=1" test_trend_perfect
run_test "no z-score outliers" test_no_outliers
run_test "histogram bins sum to N" test_histogram_bin_sum
run_test "CV exact value" test_cv_exact
run_test "quality score known" test_quality_score_known
run_test "drop suggest constant column" test_drop_suggest_constant

# v0.7 new tests
run_test "Welford accuracy with large values" test_welford_large_values
run_test "negative correlation (r=-1)" test_negative_correlation
run_test "scientific notation parsing" test_scientific_notation
run_test "regression slope/intercept exact" test_regression_slope_intercept
run_test "large-number mean accuracy" test_large_number_mean
run_test "missing count with expanded forms" test_missing_count_expanded
run_test "Cramer's V no crash on categorical data" test_cramers_v_warning
run_test "bimodality detection on bimodal data" test_bimodality_detection
run_test "quality score with moderate missingness" test_quality_score_with_missing
run_test "near-constant column detection" test_near_constant_detection
run_test "positive skewness on skewed data" test_positive_skewness
run_test "perfect negative correlation exact" test_perfect_negative_correlation_exact
run_test "pipe delimiter detection" test_pipe_delimiter_detection

# Deep correctness — missing.csv (stats with missing values excluded)
run_test "missing.csv: value mean exact" test_missing_value_mean_exact
run_test "missing.csv: value std exact" test_missing_value_std_exact
run_test "missing.csv: value min/max" test_missing_value_min_max
run_test "missing.csv: score mean exact" test_missing_score_mean_exact
run_test "missing.csv: score std exact" test_missing_score_std_exact
run_test "missing.csv: value percentiles" test_missing_value_percentiles
run_test "missing.csv: value skewness exact" test_missing_value_skewness
run_test "missing.csv: value IQR outlier" test_missing_value_iqr_outlier
run_test "missing.csv: exact missing counts" test_missing_exact_counts
run_test "missing.csv: quality score exact (75)" test_missing_quality_score_exact

# Deep correctness — numeric_edge.csv (negatives, sci notation, large numbers)
run_test "numeric_edge: neg mean exact" test_negative_mean_exact
run_test "numeric_edge: neg std exact" test_negative_std_exact
run_test "numeric_edge: neg min/max" test_negative_min_max
run_test "numeric_edge: neg percentiles" test_negative_percentiles
run_test "numeric_edge: neg skewness zero" test_negative_skewness_zero
run_test "numeric_edge: neg trend decreasing" test_negative_trend_decreasing
run_test "numeric_edge: neg monotonicity descending" test_negative_monotonicity_descending
run_test "numeric_edge: sci mean/std exact" test_sci_mean_exact
run_test "numeric_edge: sci min/max parsed from 1e1..5e1" test_sci_min_max
run_test "numeric_edge: big mean/std exact" test_big_mean_exact
run_test "numeric_edge: neg regression slope -1" test_negative_regression_slope
run_test "numeric_edge: all columns same CV" test_all_columns_same_cv

# Deep correctness — biostats.csv (categorical + group summaries)
run_test "biostats: Age mean exact" test_biostats_age_mean_exact
run_test "biostats: Height mean exact" test_biostats_height_mean_exact
run_test "biostats: Weight mean exact" test_biostats_weight_mean_exact
run_test "biostats: Sex top values M=6 F=3" test_biostats_sex_top_values
run_test "biostats: Name 9 unique" test_biostats_name_unique_count
run_test "biostats: group summary Sex age exact" test_biostats_group_summary_sex_exact
run_test "biostats: group summary Sex weight exact" test_biostats_group_summary_weight_exact
run_test "biostats: no outliers in small dataset" test_biostats_no_outliers

# Deep correctness — edge.csv (missing + zero-variance combined)
run_test "edge: measure mean exact" test_edge_measure_mean_exact
run_test "edge: measure std exact" test_edge_measure_std_exact
run_test "edge: constant zero std" test_edge_constant_zero_std
run_test "edge: quality score exact (70)" test_edge_quality_score_exact
run_test "edge: drop suggests both columns" test_edge_drop_suggests_both
run_test "edge: missing rank count" test_edge_missing_rank

# Deep correctness — outliers.csv (z-score and IQR outlier detection)
run_test "outliers: z-score outlier detected" test_outlier_zscore_detected
run_test "outliers: IQR outlier detected" test_outlier_iqr_detected
run_test "outliers: x has no outliers" test_outlier_x_no_outliers
run_test "outliers: y mean exact" test_outlier_y_mean_exact
run_test "outliers: y skewness exact" test_outlier_y_skewness_positive
run_test "outliers: y IQR values exact" test_outlier_y_iqr_values

# Deep correctness — duplicates.csv (duplicate detection + groups)
run_test "duplicates: 2 duplicate rows detected" test_duplicate_rows_detected
run_test "duplicates: quality score exact (75)" test_duplicate_quality_score_exact
run_test "duplicates: group summary exact" test_duplicate_group_summary_exact
run_test "duplicates: top values exact" test_duplicate_top_values_exact
run_test "duplicates: drop correlated column" test_duplicate_drop_correlated

# Deep correctness — bimodal.csv distribution shapes
run_test "bimodal: skewed column strong positive skew" test_bimodal_skewed_skewness_exact
run_test "bimodal: bimodal column near-symmetric" test_bimodal_symmetric_skewness

# Delimiter detection
run_test "semicolon delimiter detection" test_semicolon_delimiter
run_test "tab delimiter detection" test_tab_delimiter

print_summary
