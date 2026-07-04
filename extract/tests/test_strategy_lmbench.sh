#!/bin/bash
################################################################################
## Strategy Tests: lmbench
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: lmbench"
echo "========================================"

test_lmbench_basic () {
    local output
    output=$(run_mfe -r -s lmbench "$SAMPLES_DIR/lmbench/basic.txt")
    assert_contains "$output" "processor.null_call_us" "should extract null call latency"
    assert_contains "$output" "memory.l1_cache_ns" "should extract L1 cache latency"
    assert_contains "$output" "context.2p_0K_us" "should extract context switch"
}

test_lmbench_values () {
    local output
    output=$(run_mfe -r -s lmbench "$SAMPLES_DIR/lmbench/basic.txt")
    assert_contains "$output" "processor.null_call_us 0.27" "should extract correct null call"
    assert_contains "$output" "memory.l1_cache_ns 1.23" "should extract correct L1"
    assert_contains "$output" "system.mhz 3600" "should extract CPU MHz"
}

test_lmbench_not_json () {
    local tmpfile=$(mktemp)
    printf '{"name": "test"}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s lmbench "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "should not match JSON"
}

run_test "lmbench: basic extraction" test_lmbench_basic
run_test "lmbench: specific values" test_lmbench_values
run_test "lmbench: not detected for JSON" test_lmbench_not_json

print_summary
