#!/bin/bash
################################################################################
## Strategy Tests: network-hops (merges traceroute + mtr)
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: network-hops"
echo "========================================"

test_traceroute_detect () {
    local output
    output=$(run_mfe -d -s network-hops "$SAMPLES_DIR/traceroute/basic.txt" 2>&1)
    assert_contains "$output" "detected as applicable" "network-hops should detect traceroute output"
}

test_traceroute_extract () {
    local output
    output=$(run_mfe -r -s network-hops "$SAMPLES_DIR/traceroute/basic.txt")
    assert_contains "$output" "destination example.com" "should extract destination"
    assert_contains "$output" "destination_ip 93.184.216.34" "should extract destination IP"
    assert_contains "$output" "hop1_host gateway" "should extract hop 1 hostname"
    assert_contains "$output" "hop1_ip 192.168.1.1" "should extract hop 1 IP"
    assert_contains "$output" "hop1_rtt 1.234" "should extract hop 1 RTT"
    assert_contains "$output" "hop3_host *" "should extract timeout hop"
    assert_contains "$output" "hop4_host core-rtr.isp.net" "should extract hop 4 hostname"
}

test_traceroute_fields () {
    local output
    output=$(run_mfe -r -s network-hops "$SAMPLES_DIR/traceroute/basic.txt")
    assert_contains "$output" "hop2_ip 10.0.0.1" "should extract hop 2 IP"
    assert_contains "$output" "hop2_rtt 5.123" "should extract hop 2 RTT"
    assert_contains "$output" "hop4_ip 203.0.113.1" "should extract hop 4 IP"
    assert_not_contains "$output" "hops max" "should not contain raw header text"
}

test_mtr_detect () {
    local output
    output=$(run_mfe -d -s network-hops "$SAMPLES_DIR/mtr/basic.txt" 2>&1)
    assert_contains "$output" "applicable" "network-hops should detect mtr output"
}

test_mtr_not_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"name": "test", "value": 42}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s network-hops "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "should not detect JSON"
}

test_mtr_extract () {
    local output
    output=$(run_mfe -r -s network-hops "$SAMPLES_DIR/mtr/basic.txt")
    assert_contains "$output" "source_host webserver01" "should extract source host"
    assert_contains "$output" "start_time 2024-01-15T10:30:00+0000" "should extract start time"
    assert_contains "$output" "hop1_host gateway" "should extract hop 1 host"
    assert_contains "$output" "hop1_loss 0.0%" "should extract hop 1 loss"
    assert_contains "$output" "hop1_sent 10" "should extract hop 1 sent"
    assert_contains "$output" "hop2_avg 5.4" "should extract hop 2 avg"
    assert_contains "$output" "hop5_host example.com" "should extract hop 5 host"
    assert_contains "$output" "hop5_worst 22.5" "should extract hop 5 worst"
}

test_mtr_field_selection () {
    local output
    output=$(run_mfe -s network-hops "$SAMPLES_DIR/mtr/basic.txt" hop1_host,hop5_avg,source_host)
    assert_contains "$output" "gateway" "should include hop 1 host"
    assert_contains "$output" "20.3" "should include hop 5 avg"
    assert_contains "$output" "webserver01" "should include source host"
    assert_not_contains "$output" "hop2_" "should exclude non-selected fields"
}

run_test "network-hops: traceroute detection" test_traceroute_detect
run_test "network-hops: traceroute extraction" test_traceroute_extract
run_test "network-hops: traceroute field selection" test_traceroute_fields
run_test "network-hops: mtr detection" test_mtr_detect
run_test "network-hops: not detected for JSON" test_mtr_not_json
run_test "network-hops: mtr extraction" test_mtr_extract
run_test "network-hops: mtr field selection" test_mtr_field_selection

print_summary
