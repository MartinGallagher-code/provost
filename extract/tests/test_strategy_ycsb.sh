#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: ycsb"
echo "========================================"

test_ycsb_basic () {
    local output
    output=$(run_mfe -r -s ycsb "$SAMPLES_DIR/ycsb/basic.txt")
    assert_contains "$output" "overall.throughput_ops_per_sec" "should extract throughput"
    assert_contains "$output" "read.operations" "should extract read ops"
    assert_contains "$output" "update.operations" "should extract update ops"
}

test_ycsb_values () {
    local output
    output=$(run_mfe -r -s ycsb "$SAMPLES_DIR/ycsb/basic.txt")
    assert_contains "$output" "overall.throughput_ops_per_sec 95030.88" "should extract correct throughput"
    assert_contains "$output" "overall.runtime_ms 10523" "should extract correct runtime"
    assert_contains "$output" "read.avg_latency_us 4.56" "should extract read avg latency"
    assert_contains "$output" "update.p99_latency_us 45" "should extract update p99"
}

test_ycsb_not_json () {
    local tmpfile=$(mktemp)
    printf '{"name": "test"}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s ycsb "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "should not match JSON"
}

run_test "ycsb: basic extraction" test_ycsb_basic
run_test "ycsb: specific values" test_ycsb_values
run_test "ycsb: not detected for JSON" test_ycsb_not_json

print_summary
