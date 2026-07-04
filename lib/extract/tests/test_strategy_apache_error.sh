#!/bin/bash
################################################################################
## Strategy Tests: apache-error
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: apache-error"
echo "========================================"

test_apache_error_basic () {
    local output
    output=$(run_mfe -r -s apache-error "$SAMPLES_DIR/apache-error/basic.txt")
    # 3 lines: line1 has 4 fields, line2 has 4, line3 has 3 (no client)
    assert_contains "$output" "line1.timestamp" "should extract line1 timestamp"
    assert_contains "$output" "line1.severity error" "should extract error severity"
    assert_contains "$output" "line1.client 192.168.1.1" "should extract line1 client IP"
    assert_contains "$output" "line2.severity warn" "should extract warn severity"
    assert_contains "$output" "line3.severity notice" "should extract notice severity"
}

test_apache_error_severity () {
    local output
    output=$(run_mfe -r -s apache-error "$SAMPLES_DIR/apache-error/basic.txt")
    assert_contains "$output" "error" "should have error level"
    assert_contains "$output" "warn" "should have warn level"
    assert_contains "$output" "notice" "should have notice level"
}

test_apache_error_message () {
    local output
    output=$(run_mfe -r -s apache-error "$SAMPLES_DIR/apache-error/basic.txt")
    assert_contains "$output" "line1.message" "should extract message"
    assert_contains "$output" "File_does_not_exist" "should have underscored message"
    assert_contains "$output" "line3.message" "should extract line3 message"
}

test_apache_error_not_detected_for_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"key": "value", "count": 42}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s apache-error "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "apache-error should not apply to JSON"
}

test_apache_error_preamble_detect () {
    # Verify detection works when input has non-matching preamble lines
    local tmpfile
    tmpfile=$(mktemp)
    printf 'Apache Error Log\n================\n\n[Wed Jan 01 00:00:00.123456 2024] [error] [pid 12345] [client 192.168.1.1:54321] File does not exist: /var/www/html/missing.html\n' > "$tmpfile"
    local output
    output=$(run_mfe -r -s apache-error "$tmpfile")
    rm -f "$tmpfile"
    assert_contains "$output" "line1.severity error" "should detect and extract with preamble"
    assert_contains "$output" "line1.client 192.168.1.1" "should extract client IP with preamble"
}

run_test "apache-error: basic extraction" test_apache_error_basic
run_test "apache-error: severity extraction" test_apache_error_severity
run_test "apache-error: message extraction" test_apache_error_message
run_test "apache-error: detection with preamble lines" test_apache_error_preamble_detect
run_test "apache-error: not detected for JSON" test_apache_error_not_detected_for_json

print_summary
