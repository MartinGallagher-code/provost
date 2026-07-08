#!/bin/bash
################################################################################
## Strategy Tests: openssl
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: openssl"
echo "========================================"

test_openssl_basic () {
    local output
    output=$(run_mfe -r -s openssl "$SAMPLES_DIR/openssl/basic.txt")
    assert_contains "$output" "version 3" "should extract version"
    assert_contains "$output" "serial_number 12:34:56:78:9a:bc:de:f0" "should extract serial number"
    assert_contains "$output" "signature_algorithm sha256WithRSAEncryption" "should extract signature algorithm"
}

test_openssl_issuer_subject () {
    local output
    output=$(run_mfe -r -s openssl "$SAMPLES_DIR/openssl/basic.txt")
    assert_contains "$output" "issuer C=US, O=DigiCert Inc, CN=DigiCert Global Root G2" "should extract issuer"
    assert_contains "$output" "subject C=US, ST=California, O=Example Inc, CN=example.com" "should extract subject"
    assert_contains "$output" "not_before Jan 12 00:00:00 2024 GMT" "should extract not_before"
    assert_contains "$output" "not_after Jan 12 23:59:59 2025 GMT" "should extract not_after"
}

test_openssl_not_detected_for_json () {
    local output
    output=$(run_mfe -d -s openssl "$SAMPLES_DIR/json/basic.json" 2>&1)
    assert_contains "$output" "not applicable" "openssl should not apply to JSON"
}

run_test "openssl: basic extraction" test_openssl_basic
run_test "openssl: issuer/subject fields" test_openssl_issuer_subject
run_test "openssl: not detected for JSON" test_openssl_not_detected_for_json

print_summary
