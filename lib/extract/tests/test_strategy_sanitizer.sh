#!/bin/bash
################################################################################
## Strategy Tests: sanitizer
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: sanitizer"
echo "========================================"

test_sanitizer_basic () {
    local output
    output=$(run_mfe -r -s sanitizer "$SAMPLES_DIR/sanitizer/basic.txt")
    assert_contains "$output" "sanitizer AddressSanitizer" "should extract sanitizer name"
    assert_contains "$output" "error_type heap-buffer-overflow" "should extract error type"
    assert_contains "$output" "address 0x602000000014" "should extract address"
}

test_sanitizer_error_location () {
    local output
    output=$(run_mfe -r -s sanitizer "$SAMPLES_DIR/sanitizer/basic.txt")
    assert_contains "$output" "file /home/user/src/main.c" "should extract file"
    assert_contains "$output" "line 42" "should extract line number"
    assert_contains "$output" "function main" "should extract function name"
}

test_sanitizer_not_detected_for_json () {
    local output
    output=$(run_mfe -d -s sanitizer "$SAMPLES_DIR/json/basic.json" 2>&1)
    assert_contains "$output" "not applicable" "sanitizer should not apply to JSON"
}

run_test "sanitizer: basic extraction" test_sanitizer_basic
run_test "sanitizer: error type and location" test_sanitizer_error_location
run_test "sanitizer: not detected for JSON" test_sanitizer_not_detected_for_json

print_summary
