#!/bin/bash
################################################################################
## Strategy Tests: time-output
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: time-output"
echo "========================================"

test_time_output_basic () {
    local output
    output=$(run_mfe -r -s time-output "$SAMPLES_DIR/time-output/basic.txt")
    assert_contains "$output" "real" "should extract real field"
    assert_contains "$output" "user" "should extract user field"
    assert_contains "$output" "sys" "should extract sys field"
}

test_time_output_all_three_fields () {
    local output
    output=$(run_mfe -r -s time-output "$SAMPLES_DIR/time-output/basic.txt")
    assert_contains "$output" "0m1.234s" "should extract real time value"
    assert_contains "$output" "0m0.567s" "should extract user time value"
    assert_contains "$output" "0m0.123s" "should extract sys time value"
}

test_time_output_not_applicable_for_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"key": "value", "count": 42}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s time-output "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "time-output should not apply to JSON"
}

run_test "time-output: basic extraction" test_time_output_basic
run_test "time-output: all three time fields" test_time_output_all_three_fields
run_test "time-output: not applicable for JSON" test_time_output_not_applicable_for_json

print_summary
