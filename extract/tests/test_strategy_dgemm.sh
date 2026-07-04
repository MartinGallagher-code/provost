#!/bin/bash
################################################################################
## Strategy Tests: dgemm
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: dgemm"
echo "========================================"

test_dgemm_basic () {
    local output
    output=$(run_mfe -r -s dgemm "$SAMPLES_DIR/dgemm/basic.txt")
    assert_contains "$output" "gflops 45.67" "should extract GFLOPS"
    assert_contains "$output" "matrix_size 1000" "should extract matrix size"
    assert_contains "$output" "peak_gflops 53.4" "should extract peak GFLOPS"
    assert_contains "$output" "efficiency 85.5%" "should extract efficiency"
}

test_dgemm_multi_size () {
    local output
    output=$(run_mfe -r -s dgemm "$SAMPLES_DIR/dgemm/multi-size.txt")
    assert_contains "$output" "matrix_size 500" "should extract first matrix size"
    assert_contains "$output" "gflops 38.23" "should extract first GFLOPS"
    assert_contains "$output" "run2.matrix_size 1000" "should extract second matrix size"
    assert_contains "$output" "run4.gflops 50.15" "should extract fourth GFLOPS"
}

test_dgemm_not_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"name": "test", "value": 42}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s dgemm "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "dgemm should not apply to JSON"
}

run_test "dgemm: basic extraction" test_dgemm_basic
run_test "dgemm: multi-size extraction" test_dgemm_multi_size
run_test "dgemm: not detected for JSON" test_dgemm_not_json

print_summary
