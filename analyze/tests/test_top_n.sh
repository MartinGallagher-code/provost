#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo "========================================"
echo "EnvoyAnalyze --top-n Tests"
echo "========================================"

########################################
## --top-n TESTS
########################################

test_top_n_3 () {
    local output
    output=$(run_mda --all --top-n 3 "$SAMPLES_DIR/trees.csv" 2>/dev/null)
    local count
    count=$(echo "$output" | grep -cE '^[0-9]+\. \[')
    if [[ "$count" -ne 3 ]]; then
        echo "  ASSERT FAILED: --top-n 3 should show exactly 3 findings, got $count"
        return 1
    fi
}

test_top_n_1 () {
    local output
    output=$(run_mda --all --top-n 1 "$SAMPLES_DIR/trees.csv" 2>/dev/null)
    local count
    count=$(echo "$output" | grep -cE '^[0-9]+\. \[')
    if [[ "$count" -ne 1 ]]; then
        echo "  ASSERT FAILED: --top-n 1 should show exactly 1 finding, got $count"
        return 1
    fi
}

test_top_n_0 () {
    local output
    output=$(run_mda --all --top-n 0 "$SAMPLES_DIR/trees.csv" 2>/dev/null)
    local count
    count=$(echo "$output" | grep -cE '^[0-9]+\. \[' || true)
    if [[ "$count" -ne 0 ]]; then
        echo "  ASSERT FAILED: --top-n 0 should show no findings, got $count"
        return 1
    fi
}

test_top_n_missing_value () {
    local rc=0
    run_mda --top-n 2>/dev/null || rc=$?
    if [[ $rc -eq 0 ]]; then
        echo "  ASSERT FAILED: --top-n without a number should error"
        return 1
    fi
}

test_top_n_large_shows_all () {
    local output_all output_topn
    output_all=$(run_mda --all "$SAMPLES_DIR/trees.csv" 2>/dev/null)
    output_topn=$(run_mda --all --top-n 9999 "$SAMPLES_DIR/trees.csv" 2>/dev/null)
    local count_all count_topn
    count_all=$(echo "$output_all" | grep -cE '^[0-9]+\. \[')
    count_topn=$(echo "$output_topn" | grep -cE '^[0-9]+\. \[')
    if [[ "$count_all" -ne "$count_topn" ]]; then
        echo "  ASSERT FAILED: --top-n 9999 should show all $count_all findings, got $count_topn"
        return 1
    fi
}

test_top_n_non_numeric () {
    local rc=0
    run_mda --top-n abc "$SAMPLES_DIR/trees.csv" 2>/dev/null || rc=$?
    if [[ $rc -eq 0 ]]; then
        echo "  ASSERT FAILED: --top-n abc should error"
        return 1
    fi
}

test_top_n_with_good_filter () {
    local output
    output=$(run_mda --top-n 2 "$SAMPLES_DIR/trees.csv" 2>/dev/null)
    local count
    count=$(echo "$output" | grep -cE '^[0-9]+\. \[')
    if [[ "$count" -gt 2 ]]; then
        echo "  ASSERT FAILED: --top-n 2 with --good default should show at most 2, got $count"
        return 1
    fi
}

test_top_n_json_format () {
    local output
    output=$(run_mda --all --top-n 2 --format json "$SAMPLES_DIR/trees.csv" 2>/dev/null)
    assert_contains "$output" '"id":' "JSON output should contain id fields"
    # Count JSON items (number of "id": occurrences)
    local count
    count=$(echo "$output" | grep -oE '"id":[0-9]+' | wc -l)
    if [[ "$count" -ne 2 ]]; then
        echo "  ASSERT FAILED: --top-n 2 JSON should have exactly 2 items, got $count"
        return 1
    fi
}

########################################
## RUN ALL TESTS
########################################

echo ""
echo "--- --top-n flag ---"
run_test "top-n 3 shows 3 findings" test_top_n_3
run_test "top-n 1 shows 1 finding" test_top_n_1
run_test "top-n 0 shows no findings" test_top_n_0
run_test "top-n without value errors" test_top_n_missing_value
run_test "top-n large N shows all" test_top_n_large_shows_all
run_test "top-n non-numeric errors" test_top_n_non_numeric
run_test "top-n with good filter" test_top_n_with_good_filter
run_test "top-n with JSON format" test_top_n_json_format

print_summary
