#!/bin/bash
################################################################################
## Strategy Tests: grafana-dashboard
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: grafana-dashboard"
echo "========================================"

test_grafana_dashboard_basic () {
    local output
    output=$(run_mfe -r -s grafana-dashboard "$SAMPLES_DIR/grafana-dashboard/basic.json")
    assert_contains "$output" "title System_Monitoring" "should extract title"
    assert_contains "$output" "uid abc123def" "should extract uid"
    assert_contains "$output" "schemaVersion 39" "should extract schemaVersion"
    assert_contains "$output" "panel1.title CPU_Usage" "should extract panel1 title"
    assert_contains "$output" "panel1.type timeseries" "should extract panel1 type"
    assert_contains "$output" "panel2.title Memory_Usage" "should extract panel2 title"
    assert_contains "$output" "panel2.type gauge" "should extract panel2 type"
}

test_grafana_dashboard_not_detected_for_plain_json () {
    local output
    output=$(run_mfe -d -s grafana-dashboard "$SAMPLES_DIR/json/basic.json" 2>&1)
    assert_contains "$output" "not applicable" "grafana-dashboard should not apply to plain JSON"
}

test_grafana_dashboard_not_detected_for_har () {
    local output
    output=$(run_mfe -d -s grafana-dashboard "$SAMPLES_DIR/har/basic.har" 2>&1)
    assert_contains "$output" "not applicable" "grafana-dashboard should not apply to HAR JSON"
}

run_test "grafana-dashboard: basic extraction" test_grafana_dashboard_basic
run_test "grafana-dashboard: not detected for plain JSON" test_grafana_dashboard_not_detected_for_plain_json
run_test "grafana-dashboard: not detected for HAR JSON" test_grafana_dashboard_not_detected_for_har

print_summary
