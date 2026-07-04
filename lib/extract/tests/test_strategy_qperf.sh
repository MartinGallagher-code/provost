#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: qperf"
echo "========================================"

test_qperf_basic () {
    local output
    output=$(run_mfe -r -s qperf "$SAMPLES_DIR/qperf/basic.txt")
    assert_contains "$output" "tcp_bw.bw" "should extract tcp bandwidth"
    assert_contains "$output" "tcp_lat.latency" "should extract tcp latency"
    assert_contains "$output" "udp_lat.latency" "should extract udp latency"
}

test_qperf_values () {
    local output
    output=$(run_mfe -r -s qperf "$SAMPLES_DIR/qperf/basic.txt")
    assert_contains "$output" "tcp_bw.bw 11.2_GB/sec" "should extract correct tcp bw"
    assert_contains "$output" "tcp_lat.latency 12.3_us" "should extract correct latency"
    assert_contains "$output" "udp_bw.send_bw 4.56_GB/sec" "should extract udp send bw"
}

test_qperf_not_json () {
    local tmpfile=$(mktemp)
    printf '{"name": "test"}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s qperf "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "should not match JSON"
}

run_test "qperf: basic extraction" test_qperf_basic
run_test "qperf: specific values" test_qperf_values
run_test "qperf: not detected for JSON" test_qperf_not_json

print_summary
