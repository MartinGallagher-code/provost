#!/bin/bash
################################################################################
## Strategy Tests: strace-summary
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: strace-summary"
echo "========================================"

test_detect () {
    local output
    output=$(run_mfe -d -s strace-summary "$SAMPLES_DIR/strace-summary/basic.txt" 2>&1)
    assert_contains "$output" "applicable" "should detect strace summary output"

    # Should not detect JSON
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"name": "test", "value": 42}\n' > "$tmpfile"
    output=$(run_mfe -d -s strace-summary "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "should not detect JSON"
}

test_extract () {
    local output
    output=$(run_mfe -r -s strace-summary "$SAMPLES_DIR/strace-summary/basic.txt")
    assert_contains "$output" "syscall1_name read" "should extract first syscall name"
    assert_contains "$output" "syscall1_time_pct 42.86" "should extract first syscall time pct"
    assert_contains "$output" "syscall1_seconds 0.003000" "should extract first syscall seconds"
    assert_contains "$output" "syscall1_calls 250" "should extract first syscall calls"
    assert_contains "$output" "syscall3_name open" "should extract open syscall"
    assert_contains "$output" "syscall3_errors 10" "should extract open errors"
    assert_contains "$output" "total_seconds 0.007000" "should extract total seconds"
    assert_contains "$output" "total_calls 950" "should extract total calls"
    assert_contains "$output" "total_errors 10" "should extract total errors"
}

test_field_selection () {
    local output
    output=$(run_mfe -s strace-summary "$SAMPLES_DIR/strace-summary/basic.txt" syscall1_name,total_calls)
    assert_contains "$output" "read" "should include selected syscall name"
    assert_contains "$output" "950" "should include total calls"
    assert_not_contains "$output" "syscall2_" "should exclude non-selected fields"
}

run_test "strace-summary: detection" test_detect
run_test "strace-summary: extraction" test_extract
run_test "strace-summary: field selection" test_field_selection

print_summary
