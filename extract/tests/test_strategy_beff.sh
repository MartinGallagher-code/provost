#!/bin/bash
################################################################################
## Strategy Tests: beff
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: beff"
echo "========================================"

test_beff_detect () {
    local output
    output=$(run_mfe -d -s beff "$SAMPLES_DIR/beff/basic.txt" 2>&1)
    assert_contains "$output" "applicable" "should detect beff output"
}

test_beff_values () {
    local output
    output=$(run_mfe -r -s beff "$SAMPLES_DIR/beff/basic.txt")
    assert_contains "$output" "b_eff_value 2901.23" "should extract b_eff value"
    assert_contains "$output" "ring_bandwidth 3456.78" "should extract ring bandwidth"
    assert_contains "$output" "random_bandwidth 2345.67" "should extract random bandwidth"
    assert_contains "$output" "num_processes 8" "should extract process count"
    assert_contains "$output" "msglen_range 1 ... 4194304" "should extract message length range"
}

test_beff_not_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"name": "test"}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s beff "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "should not match JSON"
}

run_test "beff: detection" test_beff_detect
run_test "beff: specific values" test_beff_values
run_test "beff: not detected for JSON" test_beff_not_json

print_summary
