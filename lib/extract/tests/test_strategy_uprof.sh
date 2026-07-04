#!/bin/bash
################################################################################
## Strategy Tests: uprof
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: uprof"
echo "========================================"

test_uprof_detect () {
    local output
    output=$(run_mfe -d -s uprof "$SAMPLES_DIR/uprof/basic.txt" 2>&1)
    assert_contains "$output" "applicable" "should detect uprof output"
}

test_uprof_values () {
    local output
    output=$(run_mfe -r -s uprof "$SAMPLES_DIR/uprof/basic.txt")
    assert_contains "$output" "ipc 1.85" "should extract IPC"
    assert_contains "$output" "retired_instructions 4523456789" "should extract retired instructions"
    assert_contains "$output" "cache_miss_rate 3.45" "should extract cache miss rate"
    assert_contains "$output" "branch_miss_rate 1.22" "should extract branch miss rate"
    assert_contains "$output" "l1_hit_rate 96.8" "should extract L1 hit rate"
    assert_contains "$output" "l2_hit_rate 89.2" "should extract L2 hit rate"
    assert_contains "$output" "elapsed_time 15.230" "should extract elapsed time"
}

test_uprof_not_json () {
    local tmpfile=$(mktemp)
    printf '{"name": "test"}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s uprof "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "should not match JSON"
}

run_test "uprof: detection" test_uprof_detect
run_test "uprof: specific values" test_uprof_values
run_test "uprof: not detected for JSON" test_uprof_not_json

print_summary
