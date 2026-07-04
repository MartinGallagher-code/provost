#!/bin/bash
################################################################################
## Strategy Tests: likwid
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: likwid"
echo "========================================"

test_likwid_detect () {
    local output
    output=$(run_mfe -d -s likwid "$SAMPLES_DIR/likwid/basic.txt" 2>&1)
    assert_contains "$output" "applicable" "should detect likwid output"
}

test_likwid_values () {
    local output
    output=$(run_mfe -r -s likwid "$SAMPLES_DIR/likwid/basic.txt")
    assert_contains "$output" "group_name FLOPS_DP" "should extract group name"
    assert_contains "$output" "runtime 2.54321" "should extract runtime"
    assert_contains "$output" "event1_name INSTR_RETIRED_ANY" "should extract first event name"
    assert_contains "$output" "event1_counter FIXC0" "should extract first event counter"
    assert_contains "$output" "event1_value 1234567890" "should extract first event value"
    assert_contains "$output" "event2_name CPU_CLK_UNHALTED_CORE" "should extract second event name"
    assert_contains "$output" "cpi 0.80" "should extract CPI metric"
    assert_contains "$output" "mflop_per_s 179.56" "should extract MFLOP/s metric"
}

test_likwid_not_json () {
    local tmpfile=$(mktemp)
    printf '{"name": "test"}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s likwid "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "should not match JSON"
}

run_test "likwid: detection" test_likwid_detect
run_test "likwid: specific values" test_likwid_values
run_test "likwid: not detected for JSON" test_likwid_not_json

print_summary
