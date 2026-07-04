#!/bin/bash
################################################################################
## Strategy Tests: top-snapshot
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: top-snapshot"
echo "========================================"

test_top_snapshot_basic () {
    local output
    output=$(run_mfe -r -s top-snapshot "$SAMPLES_DIR/top-snapshot/basic.txt")
    assert_contains "$output" "load_avg_1min" "should extract load avg 1min"
    assert_contains "$output" "1.23" "should extract load avg 1min value"
    assert_contains "$output" "Safari" "should extract Safari process"
    assert_contains "$output" "Terminal" "should extract Terminal process"
}

test_top_snapshot_header_stats () {
    local output
    output=$(run_mfe -r -s top-snapshot "$SAMPLES_DIR/top-snapshot/basic.txt")
    assert_contains "$output" "processes_total" "should extract total processes"
    assert_contains "$output" "285" "should extract total processes count"
    assert_contains "$output" "cpu_user" "should extract CPU user"
    assert_contains "$output" "physmem_used" "should extract PhysMem used"
    assert_contains "$output" "8192M" "should extract PhysMem used value"
}

test_top_snapshot_not_applicable_for_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"key": "value", "count": 42}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s top-snapshot "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "top-snapshot should not apply to JSON"
}

run_test "top-snapshot: basic extraction (load avg, processes)" test_top_snapshot_basic
run_test "top-snapshot: header stats" test_top_snapshot_header_stats
run_test "top-snapshot: not applicable for JSON" test_top_snapshot_not_applicable_for_json

print_summary
