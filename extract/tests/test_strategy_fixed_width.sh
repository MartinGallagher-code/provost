#!/bin/bash
################################################################################
## Strategy Tests: fixed-width
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: fixed-width"
echo "========================================"

test_fw_basic () {
    local output
    output=$(run_mfe -r -s fixed-width "$SAMPLES_DIR/fixed-width/basic.txt")
    # `-r` is RAW: values keep their spaces rather than being encoded as `_`.
    assert_contains "$output" "row1.Name Task Alpha" "should extract row1 Name"
    assert_contains "$output" "row1.Status Active" "should extract row1 Status"
    assert_contains "$output" "row1.Priority High" "should extract row1 Priority"
    assert_contains "$output" "row1.Count 42" "should extract row1 Count"
}

test_fw_multi_word_values () {
    local output
    output=$(run_mfe -r -s fixed-width "$SAMPLES_DIR/fixed-width/basic.txt")
    assert_contains "$output" "row1.Name Task Alpha" "should handle multi-word name in row1"
    assert_contains "$output" "row2.Name Task Beta" "should handle multi-word name in row2"
    assert_contains "$output" "row3.Name Task Gamma" "should handle multi-word name in row3"
    assert_contains "$output" "row3.Status Complete" "should extract row3 Status"
    assert_contains "$output" "row3.Count 99" "should extract row3 Count"
}

test_fw_not_detected_for_json () {
    local output
    output=$(run_mfe -d -s fixed-width "$SAMPLES_DIR/json/basic.json" 2>&1)
    assert_contains "$output" "not applicable" "fixed-width should not apply to JSON"
}

run_test "fixed-width: basic extraction" test_fw_basic
run_test "fixed-width: multi-word values" test_fw_multi_word_values
run_test "fixed-width: not detected for JSON" test_fw_not_detected_for_json

print_summary
