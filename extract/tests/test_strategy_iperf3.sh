#!/bin/bash
################################################################################
## Strategy Tests: iperf3
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: iperf3"
echo "========================================"

test_iperf3_basic_tcp () {
    local output
    output=$(run_mfe -r -s iperf3 "$SAMPLES_DIR/iperf3/basic.txt")
    assert_contains "$output" "host 10.0.0.1" "should extract host"
    assert_contains "$output" "port 5201" "should extract port"
    assert_contains "$output" "sender_bitrate 941_Mbits/sec" "should extract sender bitrate"
    assert_contains "$output" "receiver_bitrate 935_Mbits/sec" "should extract receiver bitrate"
    assert_contains "$output" "sender_retransmits 0" "should extract retransmits"
}

test_iperf3_udp () {
    local output
    output=$(run_mfe -r -s iperf3 "$SAMPLES_DIR/iperf3/udp.txt")
    assert_contains "$output" "protocol UDP" "should detect UDP protocol"
    assert_contains "$output" "jitter_ms 0.012" "should extract jitter"
    assert_contains "$output" "packet_loss_pct 0.64" "should extract packet loss"
}

test_iperf3_not_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"name": "test", "value": 42}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s iperf3 "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "iperf3 should not apply to JSON"
}

run_test "iperf3: basic TCP extraction" test_iperf3_basic_tcp
run_test "iperf3: UDP jitter and loss" test_iperf3_udp
run_test "iperf3: not detected for JSON" test_iperf3_not_json

print_summary
