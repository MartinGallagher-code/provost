#!/bin/bash
################################################################################
## Strategy Tests: geekbench
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: geekbench"
echo "========================================"

test_geekbench_scores () {
    local output
    output=$(run_mfe -r -s geekbench "$SAMPLES_DIR/geekbench/basic.txt")
    assert_contains "$output" "single_core_score 2345" "should extract single-core score"
    assert_contains "$output" "multi_core_score 18765" "should extract multi-core score"
}

test_geekbench_per_test () {
    local output
    output=$(run_mfe -r -s geekbench "$SAMPLES_DIR/geekbench/basic.txt")
    assert_contains "$output" "test1.name AES-XTS" "should extract first test name"
    assert_contains "$output" "test1.score 3456" "should extract first test score"
    assert_contains "$output" "test5.name HTML5" "should extract HTML5 test"
}

test_geekbench_not_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"name": "test", "value": 42}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s geekbench "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "geekbench should not apply to JSON"
}

run_test "geekbench: score extraction" test_geekbench_scores
run_test "geekbench: per-test extraction" test_geekbench_per_test
run_test "geekbench: not detected for JSON" test_geekbench_not_json

print_summary
