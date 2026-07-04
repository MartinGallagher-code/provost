#!/bin/bash
################################################################################
## Strategy Tests: journald
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: journald"
echo "========================================"

test_journald_basic () {
    local output
    output=$(run_mfe -r -s journald "$SAMPLES_DIR/journald/basic.txt")
    assert_contains "$output" "line1.timestamp" "should extract line1 timestamp"
    assert_contains "$output" "Jan_12_14_23_45" "should have correct timestamp"
    assert_contains "$output" "line1.hostname myhost" "should extract line1 hostname"
    assert_contains "$output" "line1.unit systemd" "should extract systemd unit"
    assert_contains "$output" "line1.pid 1" "should extract systemd pid"
    assert_contains "$output" "line2.unit sshd" "should extract sshd unit"
    assert_contains "$output" "line3.unit kernel" "should extract kernel unit"
}

test_journald_hostname_unit () {
    local output
    output=$(run_mfe -r -s journald "$SAMPLES_DIR/journald/basic.txt")
    assert_contains "$output" "line2.hostname myhost" "should extract line2 hostname"
    assert_contains "$output" "line2.pid 1234" "should extract sshd pid"
    assert_contains "$output" "line3.hostname myhost" "should extract line3 hostname"
}

test_journald_message () {
    local output
    output=$(run_mfe -r -s journald "$SAMPLES_DIR/journald/basic.txt")
    assert_contains "$output" "line1.message" "should extract message"
    assert_contains "$output" "Started_Daily_apt_download" "should have underscored message"
    assert_contains "$output" "line3.message" "should extract line3 message"
}

test_journald_not_detected_for_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"key": "value", "count": 42}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s journald "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "journald should not apply to JSON"
}

run_test "journald: basic extraction" test_journald_basic
run_test "journald: hostname and unit fields" test_journald_hostname_unit
run_test "journald: message extraction" test_journald_message
run_test "journald: not detected for JSON" test_journald_not_detected_for_json

print_summary
