#!/bin/bash
################################################################################
## Strategy Tests: coverage
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: coverage"
echo "========================================"

test_coverage_basic () {
    local output
    output=$(run_mfe -r -s coverage "$SAMPLES_DIR/coverage/basic.txt")
    # Check individual file coverage
    assert_contains "$output" "main.coverage 93%" "should extract main.py coverage"
    assert_contains "$output" "utils.coverage 100%" "should extract utils.py coverage"
    assert_contains "$output" "parser.coverage 82%" "should extract parser.py coverage"
    # Check statements and missed
    assert_contains "$output" "main.statements 42" "should extract main.py statements"
    assert_contains "$output" "utils.missed 0" "should extract utils.py missed"
    assert_contains "$output" "parser.missed 12" "should extract parser.py missed"
}

test_coverage_total () {
    local output
    output=$(run_mfe -r -s coverage "$SAMPLES_DIR/coverage/basic.txt")
    assert_contains "$output" "total_statements 135" "should extract total statements"
    assert_contains "$output" "total_missed 15" "should extract total missed"
    assert_contains "$output" "total_coverage 89%" "should extract total coverage"
}

test_coverage_not_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"name": "test", "value": 42}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s coverage "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "coverage should not apply to JSON"
}

test_coverage_preamble_detect () {
    # Verify detection works when input has non-matching preamble lines
    local tmpfile
    tmpfile=$(mktemp)
    printf 'Reading tracefile coverage.info\nSummary coverage rate:\n  lines......: 89.2%% (120 of 135 lines)\n  functions..: 95.0%% (19 of 20 functions)\n' > "$tmpfile"
    local output
    output=$(run_mfe -r -s coverage "$tmpfile")
    rm -f "$tmpfile"
    assert_contains "$output" "lines_coverage 89.2%" "should detect lcov-style with preamble"
}

run_test "coverage: basic extraction" test_coverage_basic
run_test "coverage: total line extraction" test_coverage_total
run_test "coverage: detection with preamble lines" test_coverage_preamble_detect
run_test "coverage: not detected for JSON" test_coverage_not_json

print_summary
