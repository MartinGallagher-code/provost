#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Strategy Tests: toml
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: toml"
echo "========================================"

test_toml_basic () {
    local output
    output=$(run_mfe -r -s toml "$SAMPLES_DIR/toml/basic.toml")
    # `-r` is RAW: values keep their spaces rather than being encoded as `_`.
    assert_contains "$output" "title My Project" "should extract title"
    assert_contains "$output" "database.host localhost" "should extract database.host"
    assert_contains "$output" "database.port 5432" "should extract database.port"
}

test_toml_dotted_sections () {
    local output
    output=$(run_mfe -r -s toml "$SAMPLES_DIR/toml/basic.toml")
    assert_contains "$output" "server.http.port 8080" "should extract dotted section key"
    assert_contains "$output" "server.http.host 0.0.0.0" "should extract dotted section host"
}

test_toml_array_tables () {
    local output
    output=$(run_mfe -r -s toml "$SAMPLES_DIR/toml/basic.toml")
    assert_contains "$output" "targets.0.name production" "should extract first array table entry"
    assert_contains "$output" "targets.1.name staging" "should extract second array table entry"
    assert_contains "$output" "targets.0.url https://prod.example.com" "should extract first array URL"
    assert_contains "$output" "targets.1.url https://staging.example.com" "should extract second array URL"
}

test_toml_not_detected_for_json () {
    local output
    output=$(run_mfe -d -s toml "$SAMPLES_DIR/json/basic.json" 2>&1)
    assert_contains "$output" "not applicable" "toml should not apply to JSON"
}

run_test "toml: basic extraction" test_toml_basic
run_test "toml: dotted sections" test_toml_dotted_sections
run_test "toml: array tables" test_toml_array_tables
run_test "toml: not detected for JSON" test_toml_not_detected_for_json

print_summary
