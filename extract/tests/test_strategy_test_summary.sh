#!/bin/bash
################################################################################
## Strategy Tests: test-summary
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: test-summary"
echo "========================================"

test_test_summary_pytest_basic () {
    local output
    output=$(run_mfe -r -s test-summary "$SAMPLES_DIR/test-summary/basic.txt")
    assert_contains "$output" "total_passed 42" "should extract passed count"
    assert_contains "$output" "total_failed 2" "should extract failed count"
    assert_contains "$output" "total_skipped 1" "should extract skipped count"
    assert_contains "$output" "duration 3.45s" "should extract duration"
    assert_contains "$output" "framework pytest" "should identify pytest framework"
}

test_test_summary_jest () {
    local output
    output=$(run_mfe -r -s test-summary "$SAMPLES_DIR/test-summary/jest.txt")
    assert_contains "$output" "total_passed 12" "should extract Jest passed count"
    assert_contains "$output" "total_failed 3" "should extract Jest failed count"
    assert_contains "$output" "total_tests 15" "should extract Jest total tests"
    assert_contains "$output" "suites_passed 2" "should extract suites passed"
    assert_contains "$output" "suites_failed 1" "should extract suites failed"
    assert_contains "$output" "suites_total 3" "should extract suites total"
    assert_contains "$output" "duration 4.567s" "should extract Jest duration"
    assert_contains "$output" "framework jest" "should identify jest framework"
}

test_test_summary_not_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"name": "test", "value": 42}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s test-summary "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "test-summary should not apply to JSON"
}

run_test "test-summary: basic pytest extraction" test_test_summary_pytest_basic
run_test "test-summary: Jest format extraction" test_test_summary_jest
run_test "test-summary: not detected for JSON" test_test_summary_not_json

print_summary
