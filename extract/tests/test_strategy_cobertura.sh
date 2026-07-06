#!/bin/bash
################################################################################
## Strategy Tests: cobertura
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: cobertura"
echo "========================================"

test_cobertura_basic () {
    local output
    output=$(run_mfe -r -s cobertura "$SAMPLES_DIR/cobertura/basic.xml")
    assert_contains "$output" "line-rate 0.85" "should extract line-rate"
    assert_contains "$output" "branch-rate 0.72" "should extract branch-rate"
    assert_contains "$output" "lines-covered 340" "should extract lines-covered"
    assert_contains "$output" "lines-valid 400" "should extract lines-valid"
    assert_contains "$output" "version 5.3" "should extract version"
    assert_contains "$output" "package1.name com.example.app" "should extract first package name"
    assert_contains "$output" "package1.line-rate 0.90" "should extract first package line-rate"
    assert_contains "$output" "package2.name com.example.utils" "should extract second package name"
    assert_contains "$output" "package2.line-rate 0.80" "should extract second package line-rate"
}

test_cobertura_not_detected_for_xml () {
    local output
    output=$(run_mfe -d -s cobertura "$SAMPLES_DIR/xml-elements/basic.xml" 2>&1)
    assert_contains "$output" "not applicable" "cobertura should not apply to regular XML"
}

test_cobertura_not_detected_for_json () {
    local output
    output=$(run_mfe -d -s cobertura "$SAMPLES_DIR/json/basic.json" 2>&1)
    assert_contains "$output" "not applicable" "cobertura should not apply to JSON"
}

run_test "cobertura: basic extraction" test_cobertura_basic
run_test "cobertura: not detected for regular XML" test_cobertura_not_detected_for_xml
run_test "cobertura: not detected for JSON" test_cobertura_not_detected_for_json

print_summary
