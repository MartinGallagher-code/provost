#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Strategy Tests: syslog
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: syslog"
echo "========================================"

test_syslog_basic () {
    local output
    output=$(run_extract -r -s syslog "$SAMPLES_DIR/syslog/basic.txt")
    # Should have 3 lines worth of fields (14 total: 5+5+4, line3 has no pid)
    assert_contains "$output" "line1.timestamp" "should extract line1 timestamp"
    assert_contains "$output" "line1.timestamp Jan 12 14:23:45" "should have correct timestamp value"
    assert_contains "$output" "line1.hostname myhost" "should extract line1 hostname"
    assert_contains "$output" "line1.process sshd" "should extract line1 process"
    assert_contains "$output" "line1.pid 1234" "should extract line1 pid"
    assert_contains "$output" "line2.timestamp" "should extract line2 timestamp"
    assert_contains "$output" "line3.timestamp" "should extract line3 timestamp"
    assert_contains "$output" "line3.process kernel" "should extract kernel process"
}

test_syslog_hostname_process () {
    local output
    output=$(run_extract -r -s syslog "$SAMPLES_DIR/syslog/basic.txt")
    assert_contains "$output" "line2.hostname myhost" "should extract line2 hostname"
    assert_contains "$output" "line2.process cron" "should extract cron process"
    assert_contains "$output" "line2.pid 5678" "should extract cron pid"
}

test_syslog_message () {
    local output
    output=$(run_extract -r -s syslog "$SAMPLES_DIR/syslog/basic.txt")
    assert_contains "$output" "line1.message" "should extract message"
    assert_contains "$output" "Accepted publickey" "should extract message"
}

test_syslog_not_detected_for_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"key": "value", "count": 42}\n' > "$tmpfile"
    local output
    output=$(run_extract -d -s syslog "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "syslog should not apply to JSON"
}

run_test "syslog: basic extraction" test_syslog_basic
run_test "syslog: hostname and process fields" test_syslog_hostname_process
run_test "syslog: message extraction" test_syslog_message
run_test "syslog: not detected for JSON" test_syslog_not_detected_for_json

print_summary
