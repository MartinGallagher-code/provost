#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Tests for: --numeric-columns / --categorical-columns (ENV-025)
##           --missing-values (ENV-026)
##           --threshold AND/OR composition (ENV-027)
################################################################################
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo "=== Column Overrides / Missing Values / Threshold Composition ==="

TMPDIR="${TMPDIR:-/tmp}"
_FIXTURE="$TMPDIR/env025_fixture.csv"

_write_fixture () {
    cat > "$_FIXTURE" <<'EOF'
zip_code,age,status
90210,25,active
10001,32,UNKNOWN
78701,NA,inactive
60601,45,active
30303,28,active
EOF
}

# ENV-025 ---------------------------------------------------------------

test_numeric_columns_override () {
    _write_fixture
    local out
    out=$(bash "$MDA_SCRIPT" --all --numeric-columns age "$_FIXTURE" 2>&1)
    assert_contains "$out" "age: numeric" "age should still be numeric"
}

test_categorical_columns_forces_categorical () {
    _write_fixture
    local out
    out=$(bash "$MDA_SCRIPT" --all --categorical-columns zip_code "$_FIXTURE" 2>&1)
    assert_contains "$out" "zip_code: categorical (forced" "zip_code should be forced categorical"
}

test_numeric_columns_unknown_errors () {
    _write_fixture
    local out code=0
    out=$(bash "$MDA_SCRIPT" --numeric-columns nonexistent "$_FIXTURE" 2>&1) || code=$?
    [[ "$code" -ne 0 ]] || { echo "  ASSERT FAILED: unknown column should fail"; return 1; }
    assert_contains "$out" "unknown column" "should report unknown column"
}

test_numeric_and_categorical_overlap_errors () {
    _write_fixture
    local out code=0
    out=$(bash "$MDA_SCRIPT" --numeric-columns age --categorical-columns age "$_FIXTURE" 2>&1) || code=$?
    [[ "$code" -ne 0 ]] || { echo "  ASSERT FAILED: overlap should fail"; return 1; }
    assert_contains "$out" "cannot appear in both" "should reject overlapping column"
}

test_override_case_insensitive () {
    _write_fixture
    local out
    out=$(bash "$MDA_SCRIPT" --all --categorical-columns ZIP_CODE "$_FIXTURE" 2>&1)
    assert_contains "$out" "zip_code: categorical (forced" "match should be case-insensitive"
}

# ENV-026 ---------------------------------------------------------------

test_missing_values_custom_list () {
    _write_fixture
    local out
    # "UNKNOWN" and "inactive" together account for 2 rows of `status`.
    out=$(bash "$MDA_SCRIPT" --all --missing-values "UNKNOWN,inactive" "$_FIXTURE" 2>&1)
    assert_contains "$out" "status: 2 missing" "should treat UNKNOWN and inactive as missing"
}

test_missing_values_case_insensitive () {
    _write_fixture
    local out
    out=$(bash "$MDA_SCRIPT" --all --missing-values "unknown" --missing-values-case-insensitive "$_FIXTURE" 2>&1)
    assert_contains "$out" "status: 1 missing" "case-insensitive should match UNKNOWN"
}

test_missing_empty_always_missing () {
    # Even with a custom list, empty string must still count as missing.
    local fix="$TMPDIR/env026_empty.csv"
    cat > "$fix" <<'EOF'
a,b
1,X
,X
EOF
    local out
    out=$(bash "$MDA_SCRIPT" --all --missing-values "zzz" "$fix" 2>&1)
    assert_contains "$out" "a: 1 missing" "empty string should remain missing"
    rm -f "$fix"
}

# ENV-027 ---------------------------------------------------------------

test_threshold_and_passes_when_both_pass () {
    _write_fixture
    local out code=0
    out=$(bash "$MDA_SCRIPT" --all --threshold "age>=0 AND age<=200" "$_FIXTURE" 2>&1) || code=$?
    [[ "$code" -eq 0 ]] || { echo "  ASSERT FAILED: AND both pass should exit 0 (got $code)"; return 1; }
    assert_contains "$out" "Verdict: PASS" "combined AND should pass"
}

test_threshold_and_fails_when_one_fails () {
    _write_fixture
    local out code=0
    out=$(bash "$MDA_SCRIPT" --all --threshold "age>=0 AND age<0" "$_FIXTURE" 2>&1) || code=$?
    [[ "$code" -ne 0 ]] || { echo "  ASSERT FAILED: AND with one failing should exit nonzero"; return 1; }
    assert_contains "$out" "Verdict: FAIL" "combined AND with a failing side should FAIL"
}

test_threshold_or_passes_when_either_passes () {
    _write_fixture
    local out code=0
    # age<0 fails, age>=0 passes — OR should pass
    out=$(bash "$MDA_SCRIPT" --all --threshold "age<0 OR age>=0" "$_FIXTURE" 2>&1) || code=$?
    [[ "$code" -eq 0 ]] || { echo "  ASSERT FAILED: OR with one passing should exit 0"; return 1; }
    assert_contains "$out" "Verdict: PASS" "OR with one passing should PASS"
}

test_threshold_parens_precedence () {
    _write_fixture
    local out code=0
    # (age<0 OR age>=0) AND age>=0 — all pass inside/out
    out=$(bash "$MDA_SCRIPT" --all --threshold "(age<0 OR age>=0) AND age>=0" "$_FIXTURE" 2>&1) || code=$?
    [[ "$code" -eq 0 ]] || { echo "  ASSERT FAILED: paren expr should exit 0"; return 1; }
    assert_contains "$out" "Verdict: PASS" "paren expr should PASS"
}

test_threshold_unknown_column_error () {
    _write_fixture
    local out code=0
    out=$(bash "$MDA_SCRIPT" --all --threshold "nonexistent>0" "$_FIXTURE" 2>&1) || code=$?
    [[ "$code" -ne 0 ]] || { echo "  ASSERT FAILED: unknown column should exit nonzero"; return 1; }
    assert_contains "$out" "not found" "should report column not found"
}

test_threshold_single_condition_backward_compat () {
    _write_fixture
    local out code=0
    out=$(bash "$MDA_SCRIPT" --all --threshold "age>=0" "$_FIXTURE" 2>&1) || code=$?
    [[ "$code" -eq 0 ]] || { echo "  ASSERT FAILED: single condition should still work"; return 1; }
    assert_contains "$out" "Verdict: PASS" "single-condition threshold should still PASS"
}

test_threshold_case_insensitive_operators () {
    _write_fixture
    local out code=0
    out=$(bash "$MDA_SCRIPT" --all --threshold "age>=0 and age<=200" "$_FIXTURE" 2>&1) || code=$?
    [[ "$code" -eq 0 ]] || { echo "  ASSERT FAILED: lowercase 'and' should work"; return 1; }
    assert_contains "$out" "Verdict: PASS" "lowercase 'and' should parse"
}

run_test "ENV-025: --numeric-columns keeps numeric classification" test_numeric_columns_override
run_test "ENV-025: --categorical-columns forces categorical" test_categorical_columns_forces_categorical
run_test "ENV-025: unknown column in --numeric-columns errors" test_numeric_columns_unknown_errors
run_test "ENV-025: overlapping --numeric and --categorical errors" test_numeric_and_categorical_overlap_errors
run_test "ENV-025: column match is case-insensitive" test_override_case_insensitive
run_test "ENV-026: custom --missing-values list works" test_missing_values_custom_list
run_test "ENV-026: --missing-values-case-insensitive works" test_missing_values_case_insensitive
run_test "ENV-026: empty string always counts as missing" test_missing_empty_always_missing
run_test "ENV-027: AND passes when both sides pass" test_threshold_and_passes_when_both_pass
run_test "ENV-027: AND fails when one side fails" test_threshold_and_fails_when_one_fails
run_test "ENV-027: OR passes when either side passes" test_threshold_or_passes_when_either_passes
run_test "ENV-027: parentheses control precedence" test_threshold_parens_precedence
run_test "ENV-027: unknown column in threshold errors" test_threshold_unknown_column_error
run_test "ENV-027: single-condition threshold still works" test_threshold_single_condition_backward_compat
run_test "ENV-027: lowercase 'and' / 'or' accepted" test_threshold_case_insensitive_operators

rm -f "$_FIXTURE"
print_summary
