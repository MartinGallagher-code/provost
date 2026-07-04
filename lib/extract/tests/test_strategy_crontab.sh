#!/bin/bash
################################################################################
## Strategy Tests: crontab
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: crontab"
echo "========================================"

test_crontab_basic () {
    local output
    output=$(run_mfe -r -s crontab "$SAMPLES_DIR/crontab/basic.txt")
    assert_contains "$output" "SHELL /bin/bash" "should extract SHELL env var"
    assert_contains "$output" "MAILTO admin@example.com" "should extract MAILTO env var"
    assert_contains "$output" "job1.minute 0" "should extract first job minute"
    assert_contains "$output" "job1.hour 2" "should extract first job hour"
    assert_contains "$output" "job1.command /usr/local/bin/backup-db.sh" "should extract first job command"
    assert_contains "$output" "job3.day_of_week 0" "should extract weekly job day_of_week"
    assert_contains "$output" "job5.schedule @reboot" "should extract reboot shortcut"
    assert_contains "$output" "job5.command /usr/local/bin/startup.sh" "should extract reboot command"
}

test_crontab_not_detected_for_json () {
    local output
    output=$(run_mfe -d -s crontab "$SAMPLES_DIR/json/basic.json" 2>&1)
    assert_contains "$output" "not applicable" "should not apply to JSON"
}

test_crontab_not_detected_for_env_vars () {
    local output
    output=$(run_mfe -d -s crontab "$SAMPLES_DIR/env-vars/basic.txt" 2>&1)
    assert_contains "$output" "not applicable" "should not apply to env-vars (no schedule fields)"
}

run_test "crontab: basic extraction" test_crontab_basic
run_test "crontab: not detected for JSON" test_crontab_not_detected_for_json
run_test "crontab: not detected for env-vars" test_crontab_not_detected_for_env_vars

print_summary
