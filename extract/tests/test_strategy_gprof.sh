#!/bin/bash
################################################################################
## Strategy Tests: gprof
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: gprof"
echo "========================================"

test_gprof_detect () {
    local output
    output=$(run_mfe -d -s gprof "$SAMPLES_DIR/gprof/basic.txt" 2>&1)
    assert_contains "$output" "applicable" "should detect gprof output"
}

test_gprof_values () {
    local output
    output=$(run_mfe -r -s gprof "$SAMPLES_DIR/gprof/basic.txt")
    assert_contains "$output" "func1_name compute_inner" "should extract first function name"
    assert_contains "$output" "func1_percent_time 42.86" "should extract first percent time"
    assert_contains "$output" "func1_cumulative_seconds 1.50" "should extract first cumulative seconds"
    assert_contains "$output" "func1_self_seconds 1.50" "should extract first self seconds"
    assert_contains "$output" "func1_calls 1000000" "should extract first calls count"
    assert_contains "$output" "func2_name transform_data" "should extract second function name"
    assert_contains "$output" "func2_percent_time 28.57" "should extract second percent time"
    assert_contains "$output" "func3_name sort_elements" "should extract third function name"
    assert_contains "$output" "func4_name allocate_buffer" "should extract fourth function name"
    assert_contains "$output" "func5_name initialize" "should extract fifth function name"
}

test_gprof_not_json () {
    local tmpfile=$(mktemp)
    printf '{"name": "test"}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s gprof "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "should not match JSON"
}

run_test "gprof: detection" test_gprof_detect
run_test "gprof: specific values" test_gprof_values
run_test "gprof: not detected for JSON" test_gprof_not_json

print_summary
