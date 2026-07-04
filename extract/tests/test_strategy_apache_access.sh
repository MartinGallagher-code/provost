#!/bin/bash
################################################################################
## Strategy Tests: apache-access
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: apache-access"
echo "========================================"

test_apache_access_basic () {
    local output
    output=$(run_mfe -r -s apache-access "$SAMPLES_DIR/apache-access/basic.txt")
    # 3 lines x 9 fields = 27 fields
    assert_contains "$output" "line1.ip 192.168.1.1" "should extract line1 IP"
    assert_contains "$output" "line1.method GET" "should extract line1 method"
    assert_contains "$output" "line1.path /index.html" "should extract line1 path"
    assert_contains "$output" "line1.status 200" "should extract line1 status"
    assert_contains "$output" "line1.size 1234" "should extract line1 size"
    assert_contains "$output" "line2.ip 10.0.0.2" "should extract line2 IP"
    assert_contains "$output" "line2.user admin" "should extract line2 user"
    assert_contains "$output" "line3.ip 172.16.0.1" "should extract line3 IP"
}

test_apache_access_ip_and_status () {
    local output
    output=$(run_mfe -r -s apache-access "$SAMPLES_DIR/apache-access/basic.txt")
    assert_contains "$output" "line2.status 302" "should extract 302 status"
    assert_contains "$output" "line3.status 304" "should extract 304 status"
    assert_contains "$output" "line2.method POST" "should extract POST method"
}

test_apache_access_referrer_and_agent () {
    local output
    output=$(run_mfe -r -s apache-access "$SAMPLES_DIR/apache-access/basic.txt")
    assert_contains "$output" "line1.referrer https://example.com" "should extract referrer"
    assert_contains "$output" "line2.user_agent curl/7.88.0" "should extract user agent"
    assert_contains "$output" "line2.referrer -" "should extract dash referrer"
}

test_apache_access_not_detected_for_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"key": "value", "count": 42}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s apache-access "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "apache-access should not apply to JSON"
}

test_apache_access_preamble_detect () {
    # Verify detection works when input has non-matching preamble lines
    local tmpfile
    tmpfile=$(mktemp)
    printf 'Server: Apache/2.4.41\nDate: Mon, 01 Jan 2024\n\n192.168.1.1 - user [01/Jan/2024:00:00:00 +0000] "GET /index.html HTTP/1.1" 200 1234 "-" "curl/7.88.0"\n' > "$tmpfile"
    local output
    output=$(run_mfe -r -s apache-access "$tmpfile")
    rm -f "$tmpfile"
    assert_contains "$output" "line1.ip 192.168.1.1" "should detect and extract with preamble"
    assert_contains "$output" "line1.method GET" "should extract method with preamble"
}

run_test "apache-access: basic extraction" test_apache_access_basic
run_test "apache-access: IP and status fields" test_apache_access_ip_and_status
run_test "apache-access: referrer and user agent" test_apache_access_referrer_and_agent
run_test "apache-access: detection with preamble lines" test_apache_access_preamble_detect
run_test "apache-access: not detected for JSON" test_apache_access_not_detected_for_json

print_summary
