#!/bin/bash
################################################################################
## Strategy Tests: pem-chain
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: pem-chain"
echo "========================================"

test_pem_chain_basic () {
    local output
    output=$(run_mfe -r -s pem-chain "$SAMPLES_DIR/pem-chain/basic.pem")
    assert_contains "$output" "cert1.type CERTIFICATE" "should extract first cert type"
    assert_contains "$output" "cert2.type CERTIFICATE" "should extract second cert type"
    assert_contains "$output" "cert1.size" "should extract first cert size"
    assert_contains "$output" "cert2.size" "should extract second cert size"
    assert_contains "$output" "total_certificates 2" "should count total certificates"
}

test_pem_chain_not_detected_for_json () {
    local output
    output=$(run_mfe -d -s pem-chain "$SAMPLES_DIR/json/basic.json" 2>&1)
    assert_contains "$output" "not applicable" "should not apply to JSON"
}

test_pem_chain_not_detected_for_openssl () {
    local output
    output=$(run_mfe -d -s pem-chain "$SAMPLES_DIR/openssl/basic.txt" 2>&1)
    assert_contains "$output" "not applicable" "should not apply to openssl text output"
}

run_test "pem-chain: basic extraction" test_pem_chain_basic
run_test "pem-chain: not detected for JSON" test_pem_chain_not_detected_for_json
run_test "pem-chain: not detected for openssl" test_pem_chain_not_detected_for_openssl

print_summary
