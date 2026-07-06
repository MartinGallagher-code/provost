#!/bin/bash
################################################################################
## Strategy Tests: ethtool
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: ethtool"
echo "========================================"

test_detect () {
    local output
    output=$(run_mfe -d -s ethtool "$SAMPLES_DIR/ethtool/basic.txt" 2>&1)
    assert_contains "$output" "detected as applicable" "ethtool should detect ethtool output"
}

test_extract_interface () {
    local output
    output=$(run_mfe -r -s ethtool "$SAMPLES_DIR/ethtool/basic.txt")
    assert_contains "$output" "interface eth0" "should extract interface name"
}

test_extract_speed () {
    local output
    output=$(run_mfe -r -s ethtool "$SAMPLES_DIR/ethtool/basic.txt")
    assert_contains "$output" "speed 1000Mb/s" "should extract speed"
    assert_contains "$output" "duplex Full" "should extract duplex"
}

test_extract_link_info () {
    local output
    output=$(run_mfe -r -s ethtool "$SAMPLES_DIR/ethtool/basic.txt")
    assert_contains "$output" "auto_negotiation on" "should extract auto-negotiation"
    assert_contains "$output" "link_detected yes" "should extract link detected"
    assert_contains "$output" "port Twisted Pair" "should extract port type"
}

test_extract_driver () {
    local output
    output=$(run_mfe -r -s ethtool "$SAMPLES_DIR/ethtool/basic.txt")
    assert_contains "$output" "driver e1000e" "should extract driver name"
    assert_contains "$output" "firmware_version 0.13-3" "should extract firmware version"
    assert_contains "$output" "bus_info 0000:00:1f.6" "should extract bus info"
}

test_extract_ring () {
    local output
    output=$(run_mfe -r -s ethtool "$SAMPLES_DIR/ethtool/basic.txt")
    assert_contains "$output" "ring_rx 256" "should extract ring RX"
    assert_contains "$output" "ring_tx 256" "should extract ring TX"
}

run_test "ethtool: detection" test_detect
run_test "ethtool: interface name" test_extract_interface
run_test "ethtool: speed and duplex" test_extract_speed
run_test "ethtool: link info" test_extract_link_info
run_test "ethtool: driver info" test_extract_driver
run_test "ethtool: ring parameters" test_extract_ring

print_summary
