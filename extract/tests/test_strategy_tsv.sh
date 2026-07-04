#!/bin/bash
################################################################################
## Strategy Tests: tsv
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: tsv"
echo "========================================"

test_tsv_basic () {
    local output
    output=$(run_mfe -r -s tsv "$SAMPLES_DIR/tsv/basic.tsv")
    assert_contains "$output" "Name" "should extract Name header"
    assert_contains "$output" "John" "should extract value John"
    assert_contains "$output" "Age" "should extract Age header"
    assert_contains "$output" "30" "should extract value 30"
    assert_contains "$output" "City" "should extract City header"
    assert_contains "$output" "Portland" "should extract value Portland"
}

test_tsv_field_selection () {
    local output
    output=$(run_mfe -s tsv "$SAMPLES_DIR/tsv/basic.tsv" 1,2)
    assert_contains "$output" "Name" "should contain field 1"
    assert_contains "$output" "Age" "should contain field 2"
}

test_tsv_multiple_rows () {
    local output
    output=$(run_mfe -r -s tsv "$SAMPLES_DIR/tsv/basic.tsv")
    assert_contains "$output" "Jane" "should extract second row value Jane"
    assert_contains "$output" "Seattle" "should extract second row value Seattle"
}

test_tsv_not_detected_for_json () {
    local output
    output=$(run_mfe -d -s tsv "$SAMPLES_DIR/json/basic.json" 2>&1)
    assert_contains "$output" "not applicable" "tsv should not apply to JSON"
}

run_test "tsv: basic extraction" test_tsv_basic
run_test "tsv: field selection" test_tsv_field_selection
run_test "tsv: multiple rows" test_tsv_multiple_rows
run_test "tsv: not detected for JSON" test_tsv_not_detected_for_json

print_summary
