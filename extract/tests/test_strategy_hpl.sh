#!/bin/bash
################################################################################
## Strategy Tests: hpl
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: hpl"
echo "========================================"

test_hpl_basic () {
    local output
    output=$(run_mfe -r -s hpl "$SAMPLES_DIR/hpl/basic.txt")
    assert_contains "$output" "n 1000" "should extract first N"
    assert_contains "$output" "nb 80" "should extract NB"
    assert_contains "$output" "gflops 1.48e+00" "should extract first GFLOPS"
}

test_hpl_multi_size () {
    local output
    output=$(run_mfe -r -s hpl "$SAMPLES_DIR/hpl/basic.txt")
    assert_contains "$output" "run2.n 2000" "should extract second N"
    assert_contains "$output" "run2.gflops 1.71e+00" "should extract second GFLOPS"
    assert_contains "$output" "residual_check PASSED" "should extract residual check"
}

test_hpl_not_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"name": "test", "value": 42}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s hpl "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "hpl should not apply to JSON"
}

run_test "hpl: basic extraction" test_hpl_basic
run_test "hpl: multi-size and residual check" test_hpl_multi_size
run_test "hpl: not detected for JSON" test_hpl_not_json

print_summary
