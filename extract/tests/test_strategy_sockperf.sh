#!/bin/bash
################################################################################
## Strategy Tests: sockperf
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: sockperf"
echo "========================================"

test_sockperf_basic () {
    local output
    output=$(run_mfe -r -s sockperf "$SAMPLES_DIR/sockperf/basic.txt")
    assert_contains "$output" "avg_latency_usec" "should extract avg latency"
    assert_contains "$output" "msg_per_sec" "should extract messages per second"
    assert_contains "$output" "p99_usec" "should extract p99 latency"
}

test_sockperf_details () {
    local output
    output=$(run_mfe -r -s sockperf "$SAMPLES_DIR/sockperf/basic.txt")
    assert_contains "$output" "avg_latency_usec 10.147" "should extract correct avg latency"
    assert_contains "$output" "msg_per_sec 48763" "should extract correct msg rate"
    assert_contains "$output" "runtime_sec 10.000" "should extract runtime"
}

test_sockperf_not_json () {
    local tmpfile=$(mktemp)
    printf '{"name": "test"}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s sockperf "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "should not match JSON"
}

run_test "sockperf: basic extraction" test_sockperf_basic
run_test "sockperf: detail values" test_sockperf_details
run_test "sockperf: not detected for JSON" test_sockperf_not_json

print_summary
