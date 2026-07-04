#!/bin/bash
################################################################################
## Strategy Tests: nmap
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: nmap"
echo "========================================"

test_nmap_basic () {
    local output
    output=$(run_mfe -r -s nmap "$SAMPLES_DIR/nmap/basic.txt")
    assert_contains "$output" "host example.com" "should extract host"
    assert_contains "$output" "ip 93.184.216.34" "should extract IP"
    assert_contains "$output" "latency 0.023s" "should extract latency"
}

test_nmap_multiple_ports () {
    local output
    output=$(run_mfe -r -s nmap "$SAMPLES_DIR/nmap/basic.txt")
    assert_contains "$output" "port1.port 22/tcp" "should extract port1 port"
    assert_contains "$output" "port1.state open" "should extract port1 state"
    assert_contains "$output" "port1.service ssh" "should extract port1 service"
    assert_contains "$output" "port1.version OpenSSH_8.9" "should extract port1 version"
    assert_contains "$output" "port2.port 80/tcp" "should extract port2 port"
    assert_contains "$output" "port2.service http" "should extract port2 service"
    assert_contains "$output" "port3.port 443/tcp" "should extract port3 port"
    assert_contains "$output" "port3.service https" "should extract port3 service"
}

test_nmap_not_detected_for_json () {
    local output
    output=$(run_mfe -d -s nmap "$SAMPLES_DIR/json/basic.json" 2>&1)
    assert_contains "$output" "not applicable" "nmap should not apply to JSON"
}

run_test "nmap: basic extraction" test_nmap_basic
run_test "nmap: multiple ports" test_nmap_multiple_ports
run_test "nmap: not detected for JSON" test_nmap_not_detected_for_json

print_summary
