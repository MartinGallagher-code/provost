#!/bin/bash
################################################################################
## Strategy Tests: npm-list
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: npm-list"
echo "========================================"

test_npm_list_basic () {
    local output
    output=$(run_mfe -r -s npm-list "$SAMPLES_DIR/npm-list/basic.txt")
    assert_contains "$output" "express 4.18.2" "should extract express"
    assert_contains "$output" "lodash 4.17.21" "should extract lodash"
    assert_contains "$output" "typescript 5.0.4" "should extract typescript"
    assert_contains "$output" "jest 29.5.0" "should extract jest"
}

test_npm_list_root_package () {
    local output
    output=$(run_mfe -r -s npm-list "$SAMPLES_DIR/npm-list/basic.txt")
    assert_contains "$output" "my_project 1.0.0" "should extract root package"
}

test_npm_list_backtick_tree () {
    local output
    output=$(run_mfe -r -s npm-list "$SAMPLES_DIR/npm-list/basic.txt")
    assert_contains "$output" "jest 29.5.0" "should handle backtick tree marker"
}

test_npm_list_not_detected_for_json () {
    local output
    output=$(run_mfe -d -s npm-list "$SAMPLES_DIR/json/basic.json" 2>&1)
    assert_contains "$output" "not applicable" "npm-list should not apply to JSON"
}

run_test "npm-list: basic extraction" test_npm_list_basic
run_test "npm-list: root package" test_npm_list_root_package
run_test "npm-list: backtick tree marker" test_npm_list_backtick_tree
run_test "npm-list: not detected for JSON" test_npm_list_not_detected_for_json

print_summary
