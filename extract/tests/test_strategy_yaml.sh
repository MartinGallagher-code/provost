#!/bin/bash
################################################################################
## Strategy Tests: yaml
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: yaml"
echo "========================================"

test_yaml_basic () {
    local output
    output=$(run_mfe -r -s yaml "$SAMPLES_DIR/yaml/basic.yaml")
    assert_contains "$output" "name my-project" "should extract name"
    assert_contains "$output" "database.host localhost" "should extract database.host"
    assert_contains "$output" "database.port 5432" "should extract database.port"
}

test_yaml_nested_dot_notation () {
    local output
    output=$(run_mfe -r -s yaml "$SAMPLES_DIR/yaml/basic.yaml")
    assert_contains "$output" "server.host 0.0.0.0" "should extract server.host"
    assert_contains "$output" "server.port 8080" "should extract server.port"
    assert_contains "$output" "server.debug true" "should extract server.debug"
    assert_contains "$output" "database.name mydb" "should extract database.name"
}

test_yaml_array_entries () {
    local output
    output=$(run_mfe -r -s yaml "$SAMPLES_DIR/yaml/basic.yaml")
    assert_contains "$output" "tags.0 production" "should extract first array entry"
    assert_contains "$output" "tags.1 stable" "should extract second array entry"
}

test_yaml_not_detected_for_json () {
    local output
    output=$(run_mfe -d -s yaml "$SAMPLES_DIR/json/basic.json" 2>&1)
    assert_contains "$output" "not applicable" "yaml should not apply to JSON"
}

run_test "yaml: basic extraction" test_yaml_basic
run_test "yaml: nested keys with dot notation" test_yaml_nested_dot_notation
run_test "yaml: array entries" test_yaml_array_entries
run_test "yaml: not detected for JSON" test_yaml_not_detected_for_json

print_summary
