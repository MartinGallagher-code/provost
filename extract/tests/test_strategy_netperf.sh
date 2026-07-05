#!/bin/bash
################################################################################
## Strategy Tests: netperf
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: netperf"
echo "========================================"

test_netperf_tcp_stream () {
    local output
    output=$(run_mfe -r -s netperf "$SAMPLES_DIR/netperf/basic.txt")
    assert_contains "$output" "test_type TCP_STREAM" "should extract test type"
    assert_contains "$output" "throughput_Mbps 941.23" "should extract throughput"
    assert_contains "$output" "elapsed_time 10.00" "should extract elapsed time"
    assert_contains "$output" "recv_socket_size 131072" "should extract recv socket size"
}

test_netperf_tcp_rr () {
    local output
    output=$(run_mfe -r -s netperf "$SAMPLES_DIR/netperf/rr.txt")
    assert_contains "$output" "test_type TCP_RR" "should extract RR test type"
    assert_contains "$output" "transactions_per_sec 12345.67" "should extract transaction rate"
    assert_contains "$output" "elapsed_time 10.00" "should extract elapsed time"
}

test_netperf_not_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"name": "test", "value": 42}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s netperf "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "netperf should not apply to JSON"
}

run_test "netperf: TCP STREAM extraction" test_netperf_tcp_stream
run_test "netperf: TCP RR extraction" test_netperf_tcp_rr
run_test "netperf: not detected for JSON" test_netperf_not_json

print_summary
