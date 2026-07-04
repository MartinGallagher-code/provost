#!/bin/bash
################################################################################
## Strategy Tests: unixbench
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: unixbench"
echo "========================================"

test_unixbench_basic () {
    local output
    output=$(run_mfe -r -s unixbench "$SAMPLES_DIR/unixbench/basic.txt")
    assert_contains "$output" "system_index_score 876.2" "should extract system index score"
    assert_contains "$output" "parallel_copies 2" "should extract parallel copies"
}

test_unixbench_per_test () {
    local output
    output=$(run_mfe -r -s unixbench "$SAMPLES_DIR/unixbench/basic.txt")
    assert_contains "$output" "test1.index 1234.5" "should extract Dhrystone index"
    assert_contains "$output" "test2.index 987.6" "should extract Whetstone index"
    assert_contains "$output" "test5.index 876.5" "should extract Pipe index"
}

test_unixbench_not_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"name": "test", "value": 42}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s unixbench "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "unixbench should not apply to JSON"
}

run_test "unixbench: basic extraction" test_unixbench_basic
run_test "unixbench: per-test extraction" test_unixbench_per_test
run_test "unixbench: not detected for JSON" test_unixbench_not_json

print_summary
