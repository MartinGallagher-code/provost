#!/bin/bash
################################################################################
## Strategy Tests: vmstat
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: vmstat"
echo "========================================"

test_vmstat_basic () {
    local output
    output=$(run_mfe -r -s vmstat "$SAMPLES_DIR/vmstat/basic.txt")
    assert_contains "$output" "running" "should extract running (mapped from r)"
    assert_contains "$output" "blocked" "should extract blocked (mapped from b)"
    assert_contains "$output" "free_memory" "should extract free_memory (mapped from free)"
    assert_contains "$output" "user_cpu" "should extract user_cpu (mapped from us)"
    assert_contains "$output" "idle_cpu" "should extract idle_cpu (mapped from id)"
}

test_vmstat_multi_row () {
    # v2.0: every sample row is an indexed record group (entry<N>.<field>) so the
    # capture tidy melt renders one row per sample.
    local output
    output=$(run_mfe -r -s vmstat "$SAMPLES_DIR/vmstat/basic.txt")
    assert_contains "$output" "entry1.running 2" "should extract first row running=2"
    assert_contains "$output" "entry1.free_memory 456789" "should extract first row free=456789"
    assert_contains "$output" "entry2.running 1" "should extract second row running=1"
    assert_contains "$output" "entry2.free_memory 456123" "should extract second row free=456123"
    assert_contains "$output" "total_entries 2" "two samples"
}

test_vmstat_not_applicable_for_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"key": "value", "count": 42}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s vmstat "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "vmstat should not apply to JSON"
}

run_test "vmstat: basic extraction (mapped names)" test_vmstat_basic
run_test "vmstat: multi-row data" test_vmstat_multi_row
run_test "vmstat: not applicable for JSON" test_vmstat_not_applicable_for_json

print_summary
