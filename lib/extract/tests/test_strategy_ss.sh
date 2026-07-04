#!/bin/bash
################################################################################
## Strategy Tests: ss
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: ss"
echo "========================================"

test_detect () {
    local output
    output=$(run_mfe -d -s ss "$SAMPLES_DIR/ss/basic.txt" 2>&1)
    assert_contains "$output" "detected as applicable" "ss should detect ss -tuln output"
}

test_extract () {
    local output
    output=$(run_mfe -r -s ss "$SAMPLES_DIR/ss/basic.txt")
    assert_contains "$output" "socket1_netid tcp" "should extract first socket netid"
    assert_contains "$output" "socket1_state LISTEN" "should extract first socket state"
    assert_contains "$output" "socket1_local 0.0.0.0:22" "should extract first socket local addr"
    assert_contains "$output" "socket1_peer 0.0.0.0:*" "should extract first socket peer addr"
    assert_contains "$output" "socket4_netid udp" "should extract UDP socket"
    assert_contains "$output" "socket4_state UNCONN" "should extract UDP state"
}

test_field_selection () {
    local output
    output=$(run_mfe -r -s ss "$SAMPLES_DIR/ss/basic.txt")
    assert_contains "$output" "socket2_local 0.0.0.0:80" "should extract port 80 listener"
    assert_contains "$output" "socket3_local [::]:443" "should extract IPv6 port 443"
    assert_not_contains "$output" "Recv-Q" "should not contain raw header"
}

run_test "ss: detection" test_detect
run_test "ss: extraction" test_extract
run_test "ss: field selection" test_field_selection

print_summary
