#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Tests for: known-answer correctness on synthetic datasets (ENV-124)
##
## The pre-existing `test_correctness.sh` covers the core summary stats and
## `samples/known.csv`'s perfect-linear case in depth. This file extends
## that coverage to the four computations that the original suite only
## smoke-tested:
##
##   1. Benford's Law chi-squared on a Benford-drawn sample (PASS) AND a
##      uniform-drawn sample (FAIL) — pins both the formula and the data.
##   2. Cramer's V on hand-computed contingency tables, plus the
##      expected-frequency-<5 warning for sparse cells.
##   3. Spearman rho on non-trivial inputs: a square-monotonic +1.0, a
##      negative-monotonic −1.0, and a single-adjacent-swap value (15-row,
##      ρ = 0.996429) that catches off-by-one errors in the rank tie code.
##   4. Bimodality detection on a seeded two-cluster distribution where
##      both peak heights are independently verifiable.
##
## Truth values come from `_compute_known_truths.py` (see that file's
## docstring). Re-run `python3 tests/_compute_known_truths.py --print` to
## regenerate the truth table.
################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo "Known-Answer Extended Tests (ENV-124)"
echo "========================================"

################################################################################
## Benford's Law — exact chi-squared values
################################################################################

test_benford_pass_chi2_exact () {
    # known_benford.csv `benford` column: 200 rows drawn from a log-uniform
    # distribution (matches Benford). Hand-computed chi² = 2.68; well under
    # the 15.507 critical value, so the analysis must report PASS.
    local out
    out=$(run_mda --kinds benford "$SAMPLES_DIR/known_benford.csv")
    assert_contains "$out" "Chi-squared: 2.68" "benford column chi² should be 2.68" || return 1
    # PASS verdict appears on the same item.
    assert_contains "$out" "PASS (distribution follows Benford" "benford column should PASS the chi² test"
}

test_benford_fail_chi2_exact () {
    # known_benford.csv `uniform` column: 200 rows from uniform(1, 9999)
    # → first digits do NOT follow Benford. Hand-computed chi² = 51.02,
    # well above critical → FAIL.
    local out
    out=$(run_mda --kinds benford "$SAMPLES_DIR/known_benford.csv")
    assert_contains "$out" "Chi-squared: 51.02" "uniform column chi² should be 51.02" || return 1
    assert_contains "$out" "FAIL (deviation from Benford" "uniform column should FAIL the chi² test"
}

################################################################################
## Cramer's V — exact contingency-table values
################################################################################

test_cramers_v_device_os_exact () {
    # known_categorical.csv: device(2) × os(5) contingency, hand-computed
    # V ≈ 0.7643 (matches the awk's "iterate observed cells only"
    # implementation in lib/_categorical.sh::run_cramers_v).
    local out
    out=$(run_mda --kinds cramers_v "$SAMPLES_DIR/known_categorical.csv")
    assert_contains "$out" "device vs os: V=0.764" "device vs os V should be ~0.764" || return 1
    # The strong-association label must accompany V > 0.5.
    assert_contains "$out" "strong association" "V=0.764 should be labelled strong association"
}

test_cramers_v_low_expected_warning () {
    # device × os has cells with expected frequency < 5 (the rare
    # phone↔Linux / laptop↔iOS combinations) → the >20% low-expected
    # warning fires.
    local out
    out=$(run_mda --kinds cramers_v "$SAMPLES_DIR/known_categorical.csv")
    assert_contains "$out" "expected frequencies <5" "low-expected warning should fire on sparse cells"
}

################################################################################
## Spearman rho — three known values on non-trivial 15-row data
################################################################################

test_spearman_perfect_increasing () {
    local out
    out=$(run_mda --kinds trend "$SAMPLES_DIR/known_spearman.csv")
    # x and y (= x²) both strictly monotonic in row order → ρ = +1.0.
    assert_contains "$out" "Trend: x" "x trend item should be present" || return 1
    assert_contains "$out" "Spearman rho vs row order: 1.000000" "ρ for x should be 1.000000"
}

test_spearman_perfect_decreasing () {
    local out
    out=$(run_mda --kinds trend "$SAMPLES_DIR/known_spearman.csv")
    # z = -x → strict reverse monotonic → ρ = -1.0.
    if ! [[ "$out" == *"Trend: z"* ]]; then
        echo "  ASSERT FAILED: z trend item missing"; return 1
    fi
    # Pull out the line that follows "Trend: z" and assert its rho.
    local zblock
    zblock=$(awk '/Trend: z$/,/Trend: noisy$/' <<< "$out")
    assert_contains "$zblock" "Spearman rho vs row order: -1.000000" "ρ for z should be -1.000000"
}

test_spearman_single_adjacent_swap () {
    # `noisy` column: 1..15 with positions 8,9 swapped. Sum of d² = 2,
    # so ρ = 1 - 6·2 / (15 · (15²-1)) = 0.996429. This pins the tie-handling
    # path in the awk Spearman impl — any off-by-one in rank averaging
    # would shift this number.
    local out
    out=$(run_mda --kinds trend "$SAMPLES_DIR/known_spearman.csv")
    local nblock
    nblock=$(awk '/Trend: noisy$/,0' <<< "$out")
    assert_contains "$nblock" "Spearman rho vs row order: 0.996429" "ρ for noisy should be exactly 0.996429"
}

################################################################################
## Bimodality — verifiable peak heights
################################################################################

test_bimodality_yes_on_seeded_two_clusters () {
    # known_bimodal_seeded.csv: 25 values clustered around 10, 25 around
    # 90. The 10-bin histogram puts ~24 in bin 0 and ~22 in bin 9 with a
    # clean valley. Detector must flag YES with two peaks.
    local out
    out=$(run_mda --kinds bimodality "$SAMPLES_DIR/known_bimodal_seeded.csv")
    assert_contains "$out" "Bimodal: YES" "seeded two-cluster data should be flagged bimodal" || return 1
    assert_contains "$out" "Peaks detected: 2" "should detect exactly 2 peaks"
}

test_bimodality_peak_heights_match_seed () {
    # Truth: with seed=4, peak heights are 24 and 22 (the 25 values per
    # cluster spread over a few bins each, leaving 24/22 in the dominant
    # bins). Hard-coded because the dataset is deterministic.
    local out
    out=$(run_mda --kinds bimodality "$SAMPLES_DIR/known_bimodal_seeded.csv")
    assert_contains "$out" "Peak heights: 24, 22" "peak heights should match the seeded distribution"
}

################################################################################
## Sabotage smoke — make sure these tests would actually catch a bug
##
## The point of known-answer tests is that they fail when the underlying
## formula breaks. We can't sabotage the production code from here, but
## we can sanity-check that our assertions are tight enough to fail
## against a *different* dataset — proving they aren't substring-matching
## something benign.
################################################################################

test_assertions_are_dataset_specific () {
    # Run the tool on a different dataset (anscombe) and confirm none of
    # the very-specific strings the tests above look for appear there.
    # This is the "would my test pass for the wrong reasons?" check.
    local out
    out=$(run_mda "$SAMPLES_DIR/anscombe.csv" 2>&1)
    assert_not_contains "$out" "Chi-squared: 2.68" "Benford 2.68 must not appear in unrelated dataset" || return 1
    assert_not_contains "$out" "Chi-squared: 51.02" "Benford 51.02 must not appear in unrelated dataset" || return 1
    assert_not_contains "$out" "Spearman rho vs row order: 0.996429" "Spearman 0.996429 must not appear in unrelated dataset" || return 1
    assert_not_contains "$out" "Peak heights: 24, 22" "Bimodality 24,22 must not appear in unrelated dataset"
}

################################################################################
## Truth-generator script must remain runnable — guards against drift
################################################################################

test_truth_generator_runs () {
    # If the helper script breaks (Python syntax error, missing module,
    # whatever) someone can't regenerate the samples. Catch that at CI
    # rather than at next change.
    local out rc=0
    out=$(python3 "$SCRIPT_DIR/_compute_known_truths.py" --print 2>&1) || rc=$?
    [[ "$rc" -eq 0 ]] || {
        echo "  ASSERT FAILED: truth-generator script crashed (rc=$rc)"
        echo "$out" | head -10 | sed 's/^/    /'
        return 1
    }
    assert_contains "$out" "benford_chi2 = 2.68" "truth-generator output should pin Benford chi²" || return 1
    assert_contains "$out" "cramers_v_device_os = 0.7643" "truth-generator output should pin Cramer's V" || return 1
    assert_contains "$out" "spearman_x_noisy = 0.996429" "truth-generator output should pin Spearman ρ"
}

run_test "benford pass chi² = 2.68" test_benford_pass_chi2_exact
run_test "benford fail chi² = 51.02" test_benford_fail_chi2_exact
run_test "cramers V (device vs os) = 0.764" test_cramers_v_device_os_exact
run_test "cramers V low-expected-frequency warning" test_cramers_v_low_expected_warning
run_test "spearman ρ = +1.000000 (strict monotonic)" test_spearman_perfect_increasing
run_test "spearman ρ = -1.000000 (reverse monotonic)" test_spearman_perfect_decreasing
run_test "spearman ρ = 0.996429 (single adjacent swap)" test_spearman_single_adjacent_swap
run_test "bimodality YES on seeded 2-cluster data" test_bimodality_yes_on_seeded_two_clusters
run_test "bimodality peak heights match seed" test_bimodality_peak_heights_match_seed
run_test "assertions are dataset-specific (sabotage smoke)" test_assertions_are_dataset_specific
run_test "truth-generator script remains runnable" test_truth_generator_runs

print_summary
