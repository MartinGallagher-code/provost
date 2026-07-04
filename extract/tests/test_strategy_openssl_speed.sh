#!/bin/bash
################################################################################
## Strategy Tests: openssl-speed
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: openssl-speed"
echo "========================================"

test_openssl_speed_algorithms () {
    local output
    output=$(run_mfe -r -s openssl-speed "$SAMPLES_DIR/openssl-speed/basic.txt")
    assert_contains "$output" "aes-128-cbc.16_bytes 200725.22k" "should extract aes-128-cbc 16 bytes"
    assert_contains "$output" "aes-256-cbc.64_bytes 223549.44k" "should extract aes-256-cbc 64 bytes"
    assert_contains "$output" "sha256.256_bytes 522389.08k" "should extract sha256 256 bytes"
}

test_openssl_speed_version () {
    local output
    output=$(run_mfe -r -s openssl-speed "$SAMPLES_DIR/openssl-speed/basic.txt")
    assert_contains "$output" "openssl_version" "should extract OpenSSL version"
}

test_openssl_speed_not_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"name": "test", "value": 42}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s openssl-speed "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "openssl-speed should not apply to JSON"
}

run_test "openssl-speed: algorithm throughput extraction" test_openssl_speed_algorithms
run_test "openssl-speed: version extraction" test_openssl_speed_version
run_test "openssl-speed: not detected for JSON" test_openssl_speed_not_json

print_summary
