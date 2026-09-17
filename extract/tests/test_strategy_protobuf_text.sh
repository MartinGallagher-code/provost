#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Strategy Tests: protobuf-text
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: protobuf-text"
echo "========================================"

test_protobuf_text_basic () {
    local output
    output=$(run_mfe -r -s protobuf-text "$SAMPLES_DIR/protobuf-text/basic.txt")
    assert_contains "$output" "name test_service" "should extract name"
    assert_contains "$output" "version 1.0.0" "should extract version"
    assert_contains "$output" "port 8080" "should extract port"
    assert_contains "$output" "config1.max_connections 100" "should extract config.max_connections"
    assert_contains "$output" "config1.timeout_ms 5000" "should extract config.timeout_ms"
    assert_contains "$output" "endpoints1.path /api/v1/users" "should extract first endpoints path"
    assert_contains "$output" "endpoints2.path /api/v1/data" "should extract second endpoints path"
    assert_contains "$output" "endpoints1.method GET" "should extract first endpoints method"
    assert_contains "$output" "endpoints2.method POST" "should extract second endpoints method"
}

test_protobuf_text_not_detected_for_json () {
    local output
    output=$(run_mfe -d -s protobuf-text "$SAMPLES_DIR/json/basic.json" 2>&1)
    assert_contains "$output" "not applicable" "protobuf-text should not apply to JSON"
}

test_protobuf_text_not_detected_for_yaml () {
    local output
    output=$(run_mfe -d -s protobuf-text "$SAMPLES_DIR/yaml/basic.yaml" 2>&1)
    assert_contains "$output" "not applicable" "protobuf-text should not apply to YAML"
}

test_protobuf_text_not_detected_for_colons () {
    local output
    output=$(run_mfe -d -s protobuf-text "$SAMPLES_DIR/colons/basic.txt" 2>&1)
    assert_contains "$output" "not applicable" "protobuf-text should not apply to simple colons (no braces)"
}

run_test "protobuf-text: basic extraction" test_protobuf_text_basic
run_test "protobuf-text: not detected for JSON" test_protobuf_text_not_detected_for_json
run_test "protobuf-text: not detected for YAML" test_protobuf_text_not_detected_for_yaml
run_test "protobuf-text: not detected for colons" test_protobuf_text_not_detected_for_colons

print_summary
