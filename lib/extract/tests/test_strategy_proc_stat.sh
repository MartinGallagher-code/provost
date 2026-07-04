#!/bin/bash
################################################################################
## Strategy Tests: proc-stat
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: proc-stat"
echo "========================================"

test_proc_stat_basic () {
    local output
    output=$(run_mfe -r -s proc-stat "$SAMPLES_DIR/proc-stat/basic.txt")
    assert_contains "$output" "MemTotal" "should extract MemTotal field"
    assert_contains "$output" "MemFree" "should extract MemFree field"
    assert_contains "$output" "SwapTotal" "should extract SwapTotal field"
    assert_contains "$output" "SwapFree" "should extract SwapFree field"
}

test_proc_stat_values_with_units () {
    local output
    output=$(run_mfe -r -s proc-stat "$SAMPLES_DIR/proc-stat/basic.txt")
    assert_contains "$output" "16384000_kB" "should include unit in MemTotal value"
    assert_contains "$output" "4096000_kB" "should include unit in MemFree value"
    assert_contains "$output" "512000_kB" "should include unit in Buffers value"
}

test_proc_stat_not_applicable_for_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"key": "value", "count": 42}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s proc-stat "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "proc-stat should not apply to JSON"
}

run_test "proc-stat: basic extraction" test_proc_stat_basic
run_test "proc-stat: values include units" test_proc_stat_values_with_units
run_test "proc-stat: not applicable for JSON" test_proc_stat_not_applicable_for_json

print_summary
