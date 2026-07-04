#!/bin/bash
################################################################################
## Strategy Tests: tau
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: tau"
echo "========================================"

test_tau_detect () {
    local output
    output=$(run_mfe -d -s tau "$SAMPLES_DIR/tau/basic.txt" 2>&1)
    assert_contains "$output" "applicable" "should detect tau output"
}

test_tau_values () {
    local output
    output=$(run_mfe -r -s tau "$SAMPLES_DIR/tau/basic.txt")
    assert_contains "$output" "func1_name compute" "should extract first function name"
    assert_contains "$output" "func1_calls 5000" "should extract first function calls"
    assert_contains "$output" "func1_exclusive_time 45.230" "should extract first exclusive time"
    assert_contains "$output" "func1_inclusive_time 120.560" "should extract first inclusive time"
    assert_contains "$output" "func1_percent 37.5" "should extract first percent"
    assert_contains "$output" "func2_name transform" "should extract second function name"
    assert_contains "$output" "func3_name allocate" "should extract third function name"
    assert_contains "$output" "func4_name initialize" "should extract fourth function name"
}

test_tau_not_json () {
    local tmpfile=$(mktemp)
    printf '{"name": "test"}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s tau "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "should not match JSON"
}

run_test "tau: detection" test_tau_detect
run_test "tau: specific values" test_tau_values
run_test "tau: not detected for JSON" test_tau_not_json

print_summary
