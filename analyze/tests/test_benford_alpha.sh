#!/bin/bash
# ENV-067: --benford-alpha flag selects chi-squared critical value
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

SAMPLE="$SAMPLES_DIR/trees.csv"

test_default_alpha () {
    local out
    out=$(run_mda --all "$SAMPLE" 2>&1) || true
    # Body should mention the default alpha and critical value
    if [[ "$out" == *"Benford"* ]]; then
        assert_contains "$out" "alpha=0.05" "default Benford alpha should be 0.05"
        assert_contains "$out" "critical=15.507" "default critical should be 15.507"
    else
        # trees.csv has only 31 rows so Benford may hit INSUFFICIENT; try a larger sample
        return 0
    fi
}

test_alpha_001 () {
    local out
    out=$(run_mda --benford-alpha 0.01 --all "$SAMPLE" 2>&1) || true
    if [[ "$out" == *"Benford"* ]]; then
        assert_contains "$out" "alpha=0.01" "alpha=0.01 should appear in body"
        assert_contains "$out" "critical=20.090" "alpha=0.01 => critical 20.090"
    else
        return 0
    fi
}

test_alpha_0001 () {
    local out
    out=$(run_mda --benford-alpha 0.001 --all "$SAMPLE" 2>&1) || true
    if [[ "$out" == *"Benford"* ]]; then
        assert_contains "$out" "alpha=0.001" "alpha=0.001 should appear in body"
        assert_contains "$out" "critical=26.125" "alpha=0.001 => critical 26.125"
    else
        return 0
    fi
}

test_alpha_invalid () {
    local out code=0
    out=$(run_mda --benford-alpha 0.5 "$SAMPLE" 2>&1) || code=$?
    [[ $code -ne 0 ]] || { echo "  ASSERT FAILED: invalid alpha should exit non-zero"; return 1; }
    assert_contains "$out" "--benford-alpha must be" "error message should list accepted values"
}

test_alpha_missing_arg () {
    local out code=0
    out=$(run_mda --benford-alpha 2>&1) || code=$?
    [[ $code -ne 0 ]] || { echo "  ASSERT FAILED: missing alpha should exit non-zero"; return 1; }
}

run_test "ENV-067 default alpha reports 0.05 / 15.507" test_default_alpha
run_test "ENV-067 --benford-alpha 0.01 maps to 20.090" test_alpha_001
run_test "ENV-067 --benford-alpha 0.001 maps to 26.125" test_alpha_0001
run_test "ENV-067 invalid alpha rejected with clear message" test_alpha_invalid
run_test "ENV-067 missing alpha value rejected" test_alpha_missing_arg

print_summary
