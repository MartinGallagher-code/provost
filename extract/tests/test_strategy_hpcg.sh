#!/bin/bash
################################################################################
## Strategy Tests: hpcg
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: hpcg"
echo "========================================"

test_hpcg_detect () {
    local output
    output=$(run_mfe -d -s hpcg "$SAMPLES_DIR/hpcg/basic.txt" 2>&1)
    assert_contains "$output" "applicable" "should detect hpcg output"
}

test_hpcg_values () {
    local output
    output=$(run_mfe -r -s hpcg "$SAMPLES_DIR/hpcg/basic.txt")
    assert_contains "$output" "gflops 3.45678" "should extract GFLOP/s"
    assert_contains "$output" "problem_size 104 x 104 x 104" "should extract problem dimensions"
    assert_contains "$output" "time_seconds 62.3245" "should extract time"
    assert_contains "$output" "iterations 50" "should extract CG set count"
    assert_contains "$output" "scaled_residual 2.34567e-15" "should extract scaled residual"
    assert_contains "$output" "validity VALID" "should extract validity"
    assert_contains "$output" "memory 1.23_GB" "should extract memory"
}

test_hpcg_not_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"name": "test"}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s hpcg "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "should not match JSON"
}

run_test "hpcg: detection" test_hpcg_detect
run_test "hpcg: specific values" test_hpcg_values
run_test "hpcg: not detected for JSON" test_hpcg_not_json

print_summary
