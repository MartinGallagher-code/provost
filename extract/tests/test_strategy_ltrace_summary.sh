#!/bin/bash
################################################################################
## Strategy Tests: ltrace-summary
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: ltrace-summary"
echo "========================================"

test_ltrace_summary_detect () {
    local output
    output=$(run_mfe -d -s ltrace-summary "$SAMPLES_DIR/ltrace-summary/basic.txt" 2>&1)
    assert_contains "$output" "applicable" "should detect ltrace-summary output"
}

test_ltrace_summary_values () {
    local output
    output=$(run_mfe -r -s ltrace-summary "$SAMPLES_DIR/ltrace-summary/basic.txt")
    assert_contains "$output" "func1_name malloc" "should extract first function name"
    assert_contains "$output" "func1_percent_time 35.71" "should extract first percent time"
    assert_contains "$output" "func1_seconds 0.005000" "should extract first seconds"
    assert_contains "$output" "func2_name free" "should extract second function name"
    assert_contains "$output" "func3_name strlen" "should extract third function name"
    assert_contains "$output" "func4_name memcpy" "should extract fourth function name"
    assert_contains "$output" "func5_name printf" "should extract fifth function name"
    assert_contains "$output" "total_seconds 0.014000" "should extract total seconds"
    assert_contains "$output" "total_calls 1000" "should extract total calls"
}

test_ltrace_summary_not_json () {
    local tmpfile=$(mktemp)
    printf '{"name": "test"}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s ltrace-summary "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "should not match JSON"
}

run_test "ltrace-summary: detection" test_ltrace_summary_detect
run_test "ltrace-summary: specific values" test_ltrace_summary_values
run_test "ltrace-summary: not detected for JSON" test_ltrace_summary_not_json

print_summary
