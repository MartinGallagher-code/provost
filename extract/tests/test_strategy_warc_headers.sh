#!/bin/bash
################################################################################
## Strategy Tests: warc-headers
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: warc-headers"
echo "========================================"

test_warc_basic () {
    local output
    output=$(run_mfe -r -s warc-headers "$SAMPLES_DIR/warc-headers/basic.txt")
    assert_contains "$output" "WARC-Version" "should extract WARC version"
    assert_contains "$output" "1.0" "should extract version number"
    assert_contains "$output" "WARC-Type" "should extract WARC-Type"
    assert_contains "$output" "resource" "should extract type value"
    assert_contains "$output" "WARC-Date" "should extract date"
    assert_contains "$output" "Content-Length" "should extract Content-Length"
}

test_warc_sample3 () {
    local output
    output=$(run_mfe -r -s warc-headers "$SAMPLES_DIR/warc-headers/bbc-response.txt")
    assert_contains "$output" "WARC-Version 1.0" "should extract version 1.0"
    assert_contains "$output" "WARC-Type response" "should extract type response"
    assert_contains "$output" "WARC-IP-Address" "should extract IP address"
    assert_contains "$output" "212.58.244.61" "should extract IP value"
}

test_warc_sample4 () {
    local output
    output=$(run_mfe -r -s warc-headers "$SAMPLES_DIR/warc-headers/bbc-conversion.txt")
    assert_contains "$output" "WARC-Type conversion" "should extract conversion type"
    assert_contains "$output" "WARC-Target-URI" "should extract target URI"
}

test_warc_not_detected_for_json () {
    local output
    output=$(run_mfe -d -s warc-headers "$SAMPLES_DIR/json/basic.json" 2>&1)
    assert_contains "$output" "not applicable" "warc-headers should not apply to JSON"
}

run_test "warc-headers: basic extraction" test_warc_basic
run_test "warc-headers: sample-3 WARC response" test_warc_sample3
run_test "warc-headers: sample-4 WARC conversion" test_warc_sample4
run_test "warc-headers: not detected for JSON" test_warc_not_detected_for_json

print_summary
