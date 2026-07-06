#!/bin/bash
################################################################################
## Strategy Tests: perf-stat
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: perf-stat"
echo "========================================"

test_perf_stat_basic () {
    local output
    output=$(run_mfe -r -s perf-stat "$SAMPLES_DIR/perf-stat/basic.txt")
    assert_contains "$output" "cycles" "should extract cycles counter"
    assert_contains "$output" "instructions" "should extract instructions counter"
    assert_contains "$output" "cache_misses" "should extract cache-misses counter"
    assert_contains "$output" "branch_misses" "should extract branch-misses counter"
    assert_contains "$output" "1234567" "should extract cycles count without commas"
    assert_contains "$output" "456789" "should extract instructions count without commas"
}

test_perf_stat_time_fields () {
    local output
    output=$(run_mfe -r -s perf-stat "$SAMPLES_DIR/perf-stat/basic.txt")
    assert_contains "$output" "time_elapsed" "should extract time elapsed"
    assert_contains "$output" "0.385432100" "should extract elapsed time value"
    assert_contains "$output" "seconds_user" "should extract user seconds"
    assert_contains "$output" "seconds_sys" "should extract sys seconds"
}

test_perf_stat_not_applicable_for_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"key": "value", "count": 42}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s perf-stat "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "perf-stat should not apply to JSON"
}

run_test "perf-stat: basic extraction" test_perf_stat_basic
run_test "perf-stat: time fields" test_perf_stat_time_fields
run_test "perf-stat: not applicable for JSON" test_perf_stat_not_applicable_for_json

print_summary
