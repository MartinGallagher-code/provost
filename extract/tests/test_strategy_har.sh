#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Strategy Tests: har
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: har"
echo "========================================"

test_har_basic () {
    local output
    output=$(run_mfe -r -s har "$SAMPLES_DIR/har/basic.har")
    assert_contains "$output" "log.version 1.2" "should extract log.version"
    assert_contains "$output" "log.creator.name WebInspector" "should extract log.creator.name"
    assert_contains "$output" "log.creator.version 537.36" "should extract log.creator.version"
    assert_contains "$output" "entry1.request.method GET" "should extract entry1 request method"
    assert_contains "$output" "entry1.request.url https://api.example.com/users" "should extract entry1 request url"
    assert_contains "$output" "entry1.response.status 200" "should extract entry1 response status"
    assert_contains "$output" "entry2.request.method POST" "should extract entry2 request method"
    assert_contains "$output" "entry2.response.status 201" "should extract entry2 response status"
    assert_contains "$output" "entry2.response.statusText Created" "should extract entry2 response statusText"
}

test_har_not_detected_for_plain_json () {
    local output
    output=$(run_mfe -d -s har "$SAMPLES_DIR/json/basic.json" 2>&1)
    assert_contains "$output" "not applicable" "har should not apply to plain JSON"
}

test_har_not_detected_for_yaml () {
    local output
    output=$(run_mfe -d -s har "$SAMPLES_DIR/yaml/basic.yaml" 2>&1)
    assert_contains "$output" "not applicable" "har should not apply to YAML"
}

run_test "har: basic extraction" test_har_basic
run_test "har: not detected for plain JSON" test_har_not_detected_for_plain_json
run_test "har: not detected for YAML" test_har_not_detected_for_yaml

print_summary
