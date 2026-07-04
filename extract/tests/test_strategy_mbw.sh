#!/bin/bash
################################################################################
## Strategy Tests: mbw
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: mbw"
echo "========================================"

test_mbw_basic () {
    local output
    output=$(run_mfe -r -s mbw "$SAMPLES_DIR/mbw/basic.txt")
    assert_contains "$output" "avg_memcpy.throughput_MiB_per_s 2900.389" "should extract MEMCPY avg throughput"
    assert_contains "$output" "avg_dumb.throughput_MiB_per_s 2064.657" "should extract DUMB avg throughput"
    assert_contains "$output" "avg_mcblock.throughput_MiB_per_s 2589.067" "should extract MCBLOCK avg throughput"
}

test_mbw_individual_runs () {
    local output
    output=$(run_mfe -r -s mbw "$SAMPLES_DIR/mbw/basic.txt")
    assert_contains "$output" "memcpy.throughput_MiB_per_s 2921.123" "should extract first MEMCPY run"
    assert_contains "$output" "dumb.throughput_MiB_per_s 2073.890" "should extract first DUMB run"
    assert_contains "$output" "mcblock.throughput_MiB_per_s 2592.345" "should extract first MCBLOCK run"
}

test_mbw_not_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"name": "test", "value": 42}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s mbw "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "mbw should not apply to JSON"
}

run_test "mbw: average throughput extraction" test_mbw_basic
run_test "mbw: individual run extraction" test_mbw_individual_runs
run_test "mbw: not detected for JSON" test_mbw_not_json

print_summary
