#!/bin/bash
################################################################################
## Strategy Tests: junit-xml
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: junit-xml"
echo "========================================"

test_junit_xml_basic () {
    local output
    output=$(run_mfe -r -s junit-xml "$SAMPLES_DIR/junit-xml/basic.txt")
    assert_contains "$output" "suite.name MyTests" "should extract suite name"
    assert_contains "$output" "suite.tests 3" "should extract test count"
    assert_contains "$output" "suite.failures 1" "should extract failure count"
    assert_contains "$output" "suite.errors 0" "should extract error count"
    assert_contains "$output" "suite.time 1.234" "should extract suite time"
}

test_junit_xml_testcases () {
    local output
    output=$(run_mfe -r -s junit-xml "$SAMPLES_DIR/junit-xml/basic.txt")
    assert_contains "$output" "test1.name testAdd" "should extract first test name"
    assert_contains "$output" "test1.classname com.example.MathTest" "should extract first test classname"
    assert_contains "$output" "test1.time 0.123" "should extract first test time"
    assert_contains "$output" "test1.status pass" "should mark passing test"
    assert_contains "$output" "test2.name testSubtract" "should extract second test name"
    assert_contains "$output" "test2.status fail" "should mark failed test"
    assert_contains "$output" "test2.failure_message Expected 5 but was 4" "should extract failure message"
    assert_contains "$output" "test3.name testConcat" "should extract third test name"
    assert_contains "$output" "test3.classname com.example.StringTest" "should extract third test classname"
    assert_contains "$output" "test3.status pass" "should mark third test as pass"
}

test_junit_xml_not_for_html () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '<html><head><title>Test</title></head><body><p>Hello</p></body></html>\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s junit-xml "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "should not detect HTML"
}

run_test "junit-xml: basic extraction" test_junit_xml_basic
run_test "junit-xml: per-testcase extraction" test_junit_xml_testcases
run_test "junit-xml: not detected for HTML" test_junit_xml_not_for_html

print_summary
