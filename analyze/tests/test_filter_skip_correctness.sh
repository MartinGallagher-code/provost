#!/bin/bash
################################################################################
## Tests for: filter-aware computation skip preserves output byte-identically
## (ENV-126).
##
## The optimisation gates `run_correlation_analyses`, `run_cramers_v`, and
## `run_group_summaries` behind a `_will_keep_kind` check. The whole point is
## that the user-visible output of any filtered run is unchanged: skipping is
## a *performance* optimisation, not a behaviour change.
##
## These tests run the same filtered command twice — once with the default
## `EF_FILTER_SKIP=1` (skip enabled) and once with the escape-hatch
## `EF_FILTER_SKIP=0` (skip disabled) — and assert the two outputs match.
## Any divergence means the gate is dropping work that the un-skipped
## pipeline produces, which is the regression we care about catching.
##
## The escape hatch lives in `lib/_helpers.sh::_will_keep_kind`; it always
## returns 0 (true) when `EF_FILTER_SKIP=0` is exported.
################################################################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo "Filter-Skip Correctness Tests (ENV-126)"
echo "========================================"

# Pick a sample with enough columns to exercise correlation, group summaries,
# and Cramer's V — biostats has mixed numeric+categorical columns.
DATASET="$SAMPLES_DIR/biostats.csv"

# Strict byte-identical check: for runs with no `--kinds` filter active,
# every gate in `_will_keep_kind` short-circuits to true, so the skip
# path computes exactly what the no-skip path computes.
_diff_skipped_vs_unskipped () {
    local desc="$1"
    shift
    local args=("$@")
    local skipped unskipped
    skipped=$(EF_FILTER_SKIP=1 bash "$MDA_SCRIPT" "${args[@]}" "$DATASET" 2>&1) \
        || { echo "  ASSERT FAILED: skipped run failed for: $desc"; return 1; }
    unskipped=$(EF_FILTER_SKIP=0 bash "$MDA_SCRIPT" "${args[@]}" "$DATASET" 2>&1) \
        || { echo "  ASSERT FAILED: unskipped run failed for: $desc"; return 1; }
    if [[ "$skipped" != "$unskipped" ]]; then
        echo "  ASSERT FAILED: $desc — skipped vs unskipped output differs"
        diff <(echo "$skipped") <(echo "$unskipped") | head -20 | sed 's/^/    /'
        return 1
    fi
    return 0
}

# Content-only check: for `--kinds X` runs the skip path may renumber
# items (skipped analyses don't add to ITEM_TITLES, so survivors get
# lower numbers) and may suppress stderr warnings that came from the
# now-skipped functions. Both are intentional. The kept items'
# *bodies* must still match line-for-line modulo those leading number
# prefixes.
_compare_kept_item_bodies () {
    local desc="$1"
    shift
    local args=("$@")
    local skipped unskipped
    # Only stdout for this comparison; stderr warnings from skipped
    # functions are expected to differ.
    skipped=$(EF_FILTER_SKIP=1 bash "$MDA_SCRIPT" "${args[@]}" "$DATASET" 2>/dev/null) \
        || { echo "  ASSERT FAILED: skipped run failed for: $desc"; return 1; }
    unskipped=$(EF_FILTER_SKIP=0 bash "$MDA_SCRIPT" "${args[@]}" "$DATASET" 2>/dev/null) \
        || { echo "  ASSERT FAILED: unskipped run failed for: $desc"; return 1; }
    # Strip leading "N. " item numbers so renumbering doesn't show up
    # as a difference, and drop blank lines.
    local strip_skipped strip_unskipped
    strip_skipped=$(echo "$skipped" | sed -E 's/^[0-9]+\. //' | grep -v '^$' | sort)
    strip_unskipped=$(echo "$unskipped" | sed -E 's/^[0-9]+\. //' | grep -v '^$' | sort)
    if [[ "$strip_skipped" != "$strip_unskipped" ]]; then
        echo "  ASSERT FAILED: $desc — kept-item bodies differ"
        diff <(echo "$strip_skipped") <(echo "$strip_unskipped") | head -20 | sed 's/^/    /'
        return 1
    fi
    return 0
}

test_default_run_unchanged () {
    # No filters — both runs should do the same work.
    _diff_skipped_vs_unskipped "default run (no filters)"
}

test_good_filter_unchanged () {
    _diff_skipped_vs_unskipped "--good filter" --good
}

test_all_filter_unchanged () {
    _diff_skipped_vs_unskipped "--all filter" --all
}

test_kinds_corr_only_unchanged () {
    # Skip path drops nothing here (corr is requested) but Cramer's V and
    # group_summary would be skipped — the kept items must still match.
    _compare_kept_item_bodies "--kinds corr_matrix,corr_pairs" --kinds corr_matrix,corr_pairs
}

test_kinds_threshold_only_unchanged () {
    # Monitor-mode shape: narrow --kinds with no correlation work required.
    # Skip path drops correlation entirely; the kept items (quality_score,
    # col_types) must still come out identical.
    _compare_kept_item_bodies "--kinds quality_score,col_types" --kinds quality_score,col_types
}

test_kinds_drop_suggest_unchanged () {
    # Regression: drop_suggest reads CORR_VALUES from run_correlation_analyses.
    # The skip gate must still run correlation when drop_suggest is kept,
    # so the high-correlation column shows up in the suggestion.
    _compare_kept_item_bodies "--kinds drop_suggest" --kinds drop_suggest
}

test_tags_advanced_unchanged () {
    _diff_skipped_vs_unskipped "--tags ADVANCED" --tags ADVANCED
}

test_summary_unchanged () {
    # --summary forces _will_keep_kind to always say yes. Both runs do the
    # full pipeline; output must match.
    _diff_skipped_vs_unskipped "--summary" --summary
}

test_mode_monitor_unchanged () {
    # --mode rewrites tags after analyses run; the gate forces full
    # computation when a non-explore mode is set, so output is identical.
    _diff_skipped_vs_unskipped "--mode monitor" --mode monitor
}

test_kinds_cramers_v_unchanged () {
    # cramers_v is gated separately. Asserting parity on kept-item bodies
    # covers the categorical-pair awk skip path.
    _compare_kept_item_bodies "--kinds cramers_v" --kinds cramers_v
}

test_drop_suggest_finds_high_corr_column () {
    # Direct regression for the dependency we discovered during
    # implementation: edge.csv has a `measure` column highly correlated
    # with another. With skip enabled, drop_suggest must still see
    # CORR_VALUES populated.
    local out
    out=$(EF_FILTER_SKIP=1 bash "$MDA_SCRIPT" --kinds drop_suggest "$SAMPLES_DIR/edge.csv" 2>&1) \
        || { echo "  ASSERT FAILED: edge.csv drop_suggest run failed"; return 1; }
    assert_contains "$out" "measure" "drop_suggest must still flag high-corr column under skip"
}

run_test "default run byte-identical" test_default_run_unchanged
run_test "--good byte-identical" test_good_filter_unchanged
run_test "--all byte-identical" test_all_filter_unchanged
run_test "--tags ADVANCED byte-identical" test_tags_advanced_unchanged
run_test "--summary byte-identical" test_summary_unchanged
run_test "--mode monitor byte-identical" test_mode_monitor_unchanged
run_test "--kinds corr_matrix,corr_pairs kept items match" test_kinds_corr_only_unchanged
run_test "--kinds quality_score,col_types kept items match" test_kinds_threshold_only_unchanged
run_test "--kinds drop_suggest preserves CORR dep" test_kinds_drop_suggest_unchanged
run_test "--kinds cramers_v kept items match" test_kinds_cramers_v_unchanged
run_test "drop_suggest finds high-corr col under skip (edge.csv)" test_drop_suggest_finds_high_corr_column

print_summary
