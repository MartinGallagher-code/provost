#!/bin/bash
################################################################################
## Strategy Tests: curl-headers
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: curl-headers"
echo "========================================"

test_curl_basic () {
    local output
    output=$(run_mfe -r -s curl-headers "$SAMPLES_DIR/curl-headers/basic.txt")
    assert_contains "$output" "request.method GET" "should extract request method"
    assert_contains "$output" "request.path /index.html" "should extract request path"
    assert_contains "$output" "response.status 200" "should extract response status"
}

test_curl_request_response_headers () {
    local output
    output=$(run_mfe -r -s curl-headers "$SAMPLES_DIR/curl-headers/basic.txt")
    assert_contains "$output" "request.Host example.com" "should extract request Host header"
    assert_contains "$output" "response.content-type text/html; charset=UTF-8" "should extract response content-type"
    assert_contains "$output" "response.content-length 1256" "should extract response content-length"
    assert_contains "$output" "response.server ECS (dcb/7F83)" "should extract response server"
}

test_curl_not_detected_for_json () {
    local output
    output=$(run_mfe -d -s curl-headers "$SAMPLES_DIR/json/basic.json" 2>&1)
    assert_contains "$output" "not applicable" "curl-headers should not apply to JSON"
}

run_test "curl-headers: basic extraction" test_curl_basic
run_test "curl-headers: request + response headers" test_curl_request_response_headers
run_test "curl-headers: not detected for JSON" test_curl_not_detected_for_json

print_summary
