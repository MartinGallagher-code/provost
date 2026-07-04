#!/bin/bash
################################################################################
## Strategy Tests: vertical-line
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: vertical-line"
echo "========================================"

test_vl_basic () {
    local output
    output=$(run_mfe -r -s vertical-line "$SAMPLES_DIR/vertical-line/basic.txt")
    assert_contains "$output" "Name" "should extract Name column"
    assert_contains "$output" "Alice" "should extract value Alice"
    assert_contains "$output" "Score" "should extract Score column"
    assert_contains "$output" "95" "should extract value 95"
    assert_contains "$output" "Grade" "should extract Grade column"
    assert_contains "$output" "A" "should extract value A"
}

test_vl_sample2 () {
    local output
    output=$(run_mfe -r -s vertical-line "$SAMPLES_DIR/vertical-line/benchmark.txt")
    assert_contains "$output" "Benchmark" "should extract Benchmark column"
    assert_contains "$output" "BM_memcpy/32" "should extract benchmark name"
    assert_contains "$output" "Time" "should extract Time column"
    assert_contains "$output" "Iterations" "should extract Iterations column"
    # Values with units should be combined properly
    assert_contains "$output" "11_ns" "Time value should include unit"
}

test_vl_field_selection () {
    local output
    output=$(run_mfe -s vertical-line "$SAMPLES_DIR/vertical-line/basic.txt" 1,2)
    assert_contains "$output" "Name" "should contain field 1"
    assert_contains "$output" "Score" "should contain field 2"
}

test_vl_equals_separator () {
    local tmpfile
    tmpfile=$(mktemp)
    printf "Col1  Col2\n========\nAA    BB\nCC    DD\n" > "$tmpfile"
    local output
    output=$(run_mfe -r -s vertical-line "$tmpfile")
    rm -f "$tmpfile"
    assert_contains "$output" "Col1" "should handle === separators"
    assert_contains "$output" "AA" "should extract data"
}

test_vl_not_detected_for_json () {
    local output
    output=$(run_mfe -d -s vertical-line "$SAMPLES_DIR/json/basic.json" 2>&1)
    assert_contains "$output" "not applicable" "vertical-line should not apply to JSON"
}

run_test "vertical-line: basic table extraction" test_vl_basic
run_test "vertical-line: sample-2 benchmark table" test_vl_sample2
run_test "vertical-line: field selection" test_vl_field_selection
run_test "vertical-line: equals separator" test_vl_equals_separator
run_test "vertical-line: not detected for JSON" test_vl_not_detected_for_json

print_summary
