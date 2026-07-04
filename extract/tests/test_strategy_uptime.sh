#!/bin/bash
################################################################################
## Strategy Tests: uptime
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: uptime"
echo "========================================"

test_detect () {
    local output
    output=$(run_mfe -d -s uptime "$SAMPLES_DIR/uptime/basic.txt" 2>&1)
    assert_contains "$output" "detected as applicable" "uptime should detect uptime output"
}

test_extract_basic () {
    local output
    output=$(run_mfe -r -s uptime "$SAMPLES_DIR/uptime/basic.txt")
    assert_contains "$output" "load_avg_1min 0.22" "should extract 1min load average"
    assert_contains "$output" "load_avg_5min 0.62" "should extract 5min load average"
    assert_contains "$output" "load_avg_15min 0.82" "should extract 15min load average"
    assert_contains "$output" "users 0" "should extract user count"
    assert_contains "$output" "uptime_minutes 14" "should extract uptime minutes"
}

test_extract_days () {
    local output
    output=$(run_mfe -r -s uptime "$SAMPLES_DIR/uptime/days.txt")
    assert_contains "$output" "load_avg_1min 1.25" "should extract 1min load average"
    assert_contains "$output" "load_avg_5min 0.98" "should extract 5min load average"
    assert_contains "$output" "load_avg_15min 0.76" "should extract 15min load average"
    assert_contains "$output" "users 3" "should extract user count"
    assert_contains "$output" "uptime_days 42" "should extract uptime days"
}

run_test "uptime: detection" test_detect
run_test "uptime: extraction (minutes)" test_extract_basic
run_test "uptime: extraction (days)" test_extract_days

print_summary
