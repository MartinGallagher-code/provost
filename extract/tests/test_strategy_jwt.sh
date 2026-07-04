#!/bin/bash
################################################################################
## Strategy Tests: jwt
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: jwt"
echo "========================================"

test_jwt_basic () {
    local output
    output=$(run_mfe -r -s jwt "$SAMPLES_DIR/jwt/basic.txt")
    assert_contains "$output" "header.alg RS256" "should extract header alg"
    assert_contains "$output" "header.typ JWT" "should extract header typ"
    assert_contains "$output" "payload.sub 1234567890" "should extract payload sub"
    assert_contains "$output" "payload.name John_Doe" "should extract payload name"
    assert_contains "$output" "payload.iat 1516239022" "should extract payload iat"
}

test_jwt_not_detected_for_json () {
    local output
    output=$(run_mfe -d -s jwt "$SAMPLES_DIR/json/basic.json" 2>&1)
    assert_contains "$output" "not applicable" "should not apply to JSON"
}

test_jwt_not_detected_for_plain_text () {
    local output
    output=$(run_mfe -d -s jwt "$SAMPLES_DIR/colons/basic.txt" 2>&1)
    assert_contains "$output" "not applicable" "should not apply to plain text"
}

run_test "jwt: basic extraction" test_jwt_basic
run_test "jwt: not detected for JSON" test_jwt_not_detected_for_json
run_test "jwt: not detected for plain text" test_jwt_not_detected_for_plain_text

print_summary
