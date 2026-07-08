#!/bin/bash
################################################################################
## Strategy Tests: github-actions
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: github-actions"
echo "========================================"

test_github_actions_basic () {
    local output
    output=$(run_mfe -r -s github-actions "$SAMPLES_DIR/github-actions/basic.txt")
    assert_contains "$output" "group1.name Run npm ci" "should extract group1 name"
    assert_contains "$output" "run1.command npm ci" "should extract run1 command"
    assert_contains "$output" "group2.name Run npm test" "should extract group2 name"
    assert_contains "$output" "error1.file src/auth.test.js" "should extract error file"
    assert_contains "$output" "error1.line 42" "should extract error line"
    assert_contains "$output" "error1.message" "should extract error message"
    assert_contains "$output" "warning1.message" "should extract warning message"
    assert_contains "$output" "notice1.message" "should extract notice message"
    assert_contains "$output" "group3.name Run npm run build" "should extract group3 name"
    assert_contains "$output" "run3.command npm run build" "should extract run3 command"
}

test_github_actions_not_detected_for_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"key": "value", "count": 42}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s github-actions "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "should not apply to JSON"
}

test_github_actions_not_detected_for_test_summary () {
    local output
    output=$(run_mfe -d -s github-actions "$SAMPLES_DIR/test-summary/basic.txt" 2>&1)
    assert_contains "$output" "not applicable" "should not apply to test summary"
}

run_test "github-actions: basic extraction" test_github_actions_basic
run_test "github-actions: not detected for JSON" test_github_actions_not_detected_for_json
run_test "github-actions: not detected for test summary" test_github_actions_not_detected_for_test_summary

print_summary
