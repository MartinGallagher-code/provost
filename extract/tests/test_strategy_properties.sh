#!/bin/bash
################################################################################
## Strategy Tests: properties
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: properties"
echo "========================================"

test_properties_basic () {
    local output
    output=$(run_mfe -r -s properties "$SAMPLES_DIR/properties/basic.properties")
    assert_contains "$output" "db.host localhost" "should extract db.host"
    assert_contains "$output" "db.port 5432" "should extract db.port"
    assert_contains "$output" "server.port 8080" "should extract server.port"
    assert_contains "$output" "server.ssl.enabled true" "should extract server.ssl.enabled"
    assert_contains "$output" "logging.level.root INFO" "should extract logging.level.root"
    assert_contains "$output" "logging.file.name app.log" "should extract logging.file.name"
}

test_properties_database () {
    local output
    output=$(run_mfe -r -s properties "$SAMPLES_DIR/properties/database.properties")
    assert_contains "$output" "pool.maxActive 50" "should extract pool.maxActive"
    assert_contains "$output" "pool.maxWait 30000" "should extract pool.maxWait"
    assert_contains "$output" "jdbc.driver org.postgresql.Driver" "should extract jdbc.driver"
    assert_contains "$output" "jdbc.username app_user" "should extract jdbc.username"
}

test_properties_not_detected_for_ini () {
    local output
    output=$(run_mfe -d -s properties "$SAMPLES_DIR/ini/basic.ini" 2>&1)
    assert_contains "$output" "not applicable" "properties should not apply to INI (has sections)"
}

test_properties_not_detected_for_json () {
    local output
    output=$(run_mfe -d -s properties "$SAMPLES_DIR/json/basic.json" 2>&1)
    assert_contains "$output" "not applicable" "properties should not apply to JSON"
}

run_test "properties: basic extraction" test_properties_basic
run_test "properties: database extraction" test_properties_database
run_test "properties: not detected for INI" test_properties_not_detected_for_ini
run_test "properties: not detected for JSON" test_properties_not_detected_for_json

print_summary
