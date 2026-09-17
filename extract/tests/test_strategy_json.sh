#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Strategy Tests: json
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: json"
echo "========================================"

test_json_basic () {
    local output
    output=$(run_mfe -r -s json "$SAMPLES_DIR/json/basic.json")
    assert_contains "$output" "name" "should extract name"
    assert_contains "$output" "test-project" "should extract value test-project"
    assert_contains "$output" "version" "should extract version"
    assert_contains "$output" "1.2.3" "should extract value 1.2.3"
    assert_contains "$output" "count" "should extract count"
    assert_contains "$output" "42" "should extract value 42"
    assert_contains "$output" "enabled" "should extract enabled"
    assert_contains "$output" "true" "should extract value true"
}

test_json_sample1 () {
    local output
    output=$(run_mfe -r -s json "$SAMPLES_DIR/json/benchmark.json")
    assert_contains "$output" "date" "should extract date"
    assert_contains "$output" "num_cpus" "should extract num_cpus"
    assert_contains "$output" "40" "should extract value 40"
    assert_contains "$output" "iterations" "should extract iterations"
}

test_json_field_selection () {
    local output
    output=$(run_mfe -s json "$SAMPLES_DIR/json/basic.json" 1,3)
    assert_contains "$output" "name" "should contain field 1"
    assert_contains "$output" "count" "should contain field 3"
    assert_not_contains "$output" "version" "should not contain unselected field"
}

test_json_not_detected_for_non_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf "Name: value\nKey: data\n" > "$tmpfile"
    local output
    output=$(run_mfe -d -s json "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "json should not apply to non-JSON"
}

test_json_stdin () {
    local output
    output=$(echo '{"color": "blue", "size": 10}' | run_mfe -r -s json)
    assert_contains "$output" "color" "should extract color from stdin"
    assert_contains "$output" "blue" "should extract value blue"
    assert_contains "$output" "size" "should extract size"
    assert_contains "$output" "10" "should extract value 10"
}

run_test "json: basic extraction" test_json_basic
run_test "json: sample-1 benchmark data" test_json_sample1
run_test "json: field selection" test_json_field_selection
run_test "json: not detected for non-JSON" test_json_not_detected_for_non_json
run_test "json: stdin input" test_json_stdin

print_summary
