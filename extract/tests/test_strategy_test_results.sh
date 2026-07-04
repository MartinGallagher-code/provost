#!/bin/bash
################################################################################
## Strategy Tests: test-results (merges go-test + cargo-test)
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: test-results"
echo "========================================"

test_go_test_basic () {
    local output
    output=$(run_mfe -r -s test-results "$SAMPLES_DIR/go-test/basic.txt")
    assert_contains "$output" "test1.name TestAdd" "should extract first test name"
    assert_contains "$output" "test1.result PASS" "should extract first test result"
    assert_contains "$output" "test1.time 0.00s" "should extract first test time"
    assert_contains "$output" "test4.name TestDivide" "should extract fourth test name"
    assert_contains "$output" "test4.result FAIL" "should extract fourth test result"
    assert_contains "$output" "test5.name TestDivideByZero" "should extract fifth test name"
    assert_contains "$output" "test5.result PASS" "should extract fifth test result"
    assert_contains "$output" "coverage 87.5%" "should extract coverage"
    assert_contains "$output" "package github.com/user/mathlib" "should extract package"
    assert_contains "$output" "total_time 0.234s" "should extract total time"
}

test_go_test_not_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"name": "test", "value": 42}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s test-results "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "should not apply to JSON"
}

test_go_test_not_test_summary () {
    local output
    output=$(run_mfe -d -s test-results "$SAMPLES_DIR/test-summary/basic.txt" 2>&1)
    assert_contains "$output" "not applicable" "should not apply to test-summary"
}

test_cargo_detect () {
    local output
    output=$(run_mfe -d -s test-results "$SAMPLES_DIR/cargo-test/basic.txt" 2>&1)
    assert_contains "$output" "detected as applicable" "test-results should detect cargo test output"
}

test_cargo_extract () {
    local output
    output=$(run_mfe -r -s test-results "$SAMPLES_DIR/cargo-test/basic.txt")
    # Field names normalized: testN.name / testN.result (dot convention)
    assert_contains "$output" "test1.name tests::test_add" "should extract first test name"
    assert_contains "$output" "test1.result ok" "should extract first test result"
    assert_contains "$output" "test5.name tests::test_edge_case" "should extract fifth test name"
    assert_contains "$output" "test5.result FAILED" "should extract fifth test result"
    assert_contains "$output" "status FAILED" "should extract overall status"
    assert_contains "$output" "passed 4" "should extract passed count"
    assert_contains "$output" "failed 1" "should extract failed count"
    assert_contains "$output" "ignored 0" "should extract ignored count"
    assert_contains "$output" "duration 0.15s" "should extract duration"
    assert_contains "$output" "total_tests 5" "should extract total tests"
}

test_cargo_all_pass () {
    local output
    output=$(run_mfe -r -s test-results "$SAMPLES_DIR/cargo-test/all-pass.txt")
    assert_contains "$output" "status ok" "should extract ok status"
    assert_contains "$output" "passed 3" "should extract passed count"
    assert_contains "$output" "failed 0" "should extract failed count of 0"
    assert_contains "$output" "total_tests 3" "should calculate total from passed+failed"
    assert_contains "$output" "duration 0.08s" "should extract duration"
    assert_not_contains "$output" "FAILED" "should not contain FAILED result"
}

run_test "test-results: go test basic extraction" test_go_test_basic
run_test "test-results: not detected for JSON" test_go_test_not_json
run_test "test-results: go test not detected for test-summary" test_go_test_not_test_summary
run_test "test-results: cargo test detection" test_cargo_detect
run_test "test-results: cargo test extraction" test_cargo_extract
run_test "test-results: cargo all-pass extraction" test_cargo_all_pass

print_summary
