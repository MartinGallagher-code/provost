#!/bin/bash
################################################################################
## Strategy Tests: maven-output
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: maven-output"
echo "========================================"

test_maven_output_basic () {
    local output
    output=$(run_mfe -r -s maven-output "$SAMPLES_DIR/maven-output/basic.txt")
    assert_contains "$output" "build.result SUCCESS" "should extract build result"
    assert_contains "$output" "build.time 8.234_s" "should extract build time"
    assert_contains "$output" "build.memory 42M/256M" "should extract build memory"
    assert_contains "$output" "tests.run 42" "should extract tests run"
    assert_contains "$output" "tests.failures 0" "should extract test failures"
    assert_contains "$output" "tests.errors 0" "should extract test errors"
    assert_contains "$output" "tests.skipped 2" "should extract tests skipped"
}

test_maven_output_not_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"name": "test", "value": 42}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s maven-output "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "should not apply to JSON"
}

test_maven_output_not_gradle () {
    local output
    output=$(run_mfe -d -s maven-output "$SAMPLES_DIR/gradle-output/basic.txt" 2>&1)
    assert_contains "$output" "not applicable" "should not apply to Gradle output"
}

run_test "maven-output: basic extraction" test_maven_output_basic
run_test "maven-output: not detected for JSON" test_maven_output_not_json
run_test "maven-output: not detected for Gradle output" test_maven_output_not_gradle

print_summary
