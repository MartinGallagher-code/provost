#!/bin/bash
################################################################################
## Strategy Tests: ansible-output
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: ansible-output"
echo "========================================"

test_ansible_output_basic () {
    local output
    output=$(run_mfe -r -s ansible-output "$SAMPLES_DIR/ansible-output/basic.txt")
    assert_contains "$output" "play1.name Deploy_web_application" "should extract play name"
    assert_contains "$output" "host1.name web-server-1" "should extract first host name"
    assert_contains "$output" "host1.ok 4" "should extract first host ok count"
    assert_contains "$output" "host1.changed 3" "should extract first host changed count"
    assert_contains "$output" "host1.unreachable 0" "should extract first host unreachable count"
    assert_contains "$output" "host1.failed 0" "should extract first host failed count"
    assert_contains "$output" "host3.skipped 1" "should extract third host skipped count"
}

test_ansible_output_not_detected_for_json () {
    local output
    output=$(run_mfe -d -s ansible-output "$SAMPLES_DIR/json/basic.json" 2>&1)
    assert_contains "$output" "not applicable" "should not apply to JSON"
}

test_ansible_output_not_detected_for_colons () {
    local output
    output=$(run_mfe -d -s ansible-output "$SAMPLES_DIR/colons/basic.txt" 2>&1)
    assert_contains "$output" "not applicable" "should not apply to colon-separated data"
}

run_test "ansible-output: basic extraction" test_ansible_output_basic
run_test "ansible-output: not detected for JSON" test_ansible_output_not_detected_for_json
run_test "ansible-output: not detected for colons" test_ansible_output_not_detected_for_colons

print_summary
