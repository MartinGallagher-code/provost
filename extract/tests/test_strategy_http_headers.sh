#!/bin/bash
################################################################################
## Strategy Tests: http-headers
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: http-headers"
echo "========================================"

test_http_basic () {
    local output
    output=$(run_mfe -r -s http-headers "$SAMPLES_DIR/http-headers/basic.txt")
    assert_contains "$output" "HTTP-Status 200" "should extract status code"
    assert_contains "$output" "Content-Type" "should extract Content-Type"
    assert_contains "$output" "text/html" "should extract content type value"
    assert_contains "$output" "Server" "should extract Server"
    assert_contains "$output" "Content-Length" "should extract Content-Length"
    assert_contains "$output" "1234" "should extract length value"
}

test_http_sample3 () {
    local output
    output=$(run_mfe -r -s http-headers "$SAMPLES_DIR/warc-headers/bbc-response.txt")
    assert_contains "$output" "HTTP-Status 200" "should extract HTTP 200"
    assert_contains "$output" "Server" "should extract Server header"
    assert_contains "$output" "Apache" "should extract Apache value"
    assert_contains "$output" "Set-Cookie" "should extract Set-Cookie"
}

test_http_status_text () {
    local output
    output=$(run_mfe -r -s http-headers "$SAMPLES_DIR/http-headers/basic.txt")
    assert_contains "$output" "HTTP-Status-Text" "should extract status text"
    assert_contains "$output" "OK" "should extract OK"
}

test_http_not_detected_for_json () {
    local output
    output=$(run_mfe -d -s http-headers "$SAMPLES_DIR/json/basic.json" 2>&1)
    assert_contains "$output" "not applicable" "http-headers should not apply to JSON"
}

run_test "http-headers: basic extraction" test_http_basic
run_test "http-headers: sample-3 WARC+HTTP" test_http_sample3
run_test "http-headers: status text extracted" test_http_status_text
run_test "http-headers: not detected for JSON" test_http_not_detected_for_json

print_summary
