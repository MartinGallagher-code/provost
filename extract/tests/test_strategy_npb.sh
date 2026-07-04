#!/bin/bash
################################################################################
## Strategy Tests: npb
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: npb"
echo "========================================"

test_npb_detect () {
    local output
    output=$(run_mfe -d -s npb "$SAMPLES_DIR/npb/basic.txt" 2>&1)
    assert_contains "$output" "applicable" "should detect npb output"
}

test_npb_values () {
    local output
    output=$(run_mfe -r -s npb "$SAMPLES_DIR/npb/basic.txt")
    assert_contains "$output" "benchmark CG" "should extract benchmark name"
    assert_contains "$output" "class C" "should extract class"
    assert_contains "$output" "iterations 75" "should extract iterations"
    assert_contains "$output" "time_seconds 12.34" "should extract time"
    assert_contains "$output" "mops_total 5678.90" "should extract Mop/s total"
    assert_contains "$output" "mops_per_process 1419.73" "should extract Mop/s per process"
    assert_contains "$output" "num_processes 4" "should extract process count"
    assert_contains "$output" "verification SUCCESSFUL" "should extract verification"
    assert_contains "$output" "operation_type floating_point" "should extract operation type"
}

test_npb_not_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"name": "test"}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s npb "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "should not match JSON"
}

run_test "npb: detection" test_npb_detect
run_test "npb: specific values" test_npb_values
run_test "npb: not detected for JSON" test_npb_not_json

print_summary
