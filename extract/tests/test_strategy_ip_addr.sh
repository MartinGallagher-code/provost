#!/bin/bash
################################################################################
## Strategy Tests: ip-addr
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: ip-addr"
echo "========================================"

test_detect () {
    local output
    output=$(run_mfe -d -s ip-addr "$SAMPLES_DIR/ip-addr/basic.txt" 2>&1)
    assert_contains "$output" "detected as applicable" "ip-addr should detect ip -o addr output"
}

# Each address line becomes an indexed row group (entry<N>.<field>) so the
# capture tidy melt renders one row per address with shared columns.
test_extract () {
    local output
    output=$(run_mfe -r -s ip-addr "$SAMPLES_DIR/ip-addr/basic.txt")
    assert_contains "$output" "entry1.iface lo" "first address is on lo"
    assert_contains "$output" "entry1.family inet" "first address is inet"
    assert_contains "$output" "entry1.address 127.0.0.1/8" "loopback address"
    assert_contains "$output" "entry1.scope host" "loopback scope host"
    assert_contains "$output" "entry3.iface eth0" "third address is on eth0"
    assert_contains "$output" "entry3.address 10.0.1.50/16" "eth0 address"
    assert_contains "$output" "entry3.brd 10.0.255.255" "eth0 broadcast"
    assert_contains "$output" "entry3.scope global" "eth0 scope global"
    assert_contains "$output" "entry4.family inet6" "eth0 also has an inet6 address"
    assert_contains "$output" "total_entries 5" "five addresses"
}

# Must not fight ip-route (routing table) or plain JSON.
test_not_ip_route () {
    local output
    output=$(run_mfe -d -s ip-addr "$SAMPLES_DIR/ip-route/sample1.txt" 2>&1)
    assert_contains "$output" "not applicable" "ip-addr should not match ip route output"
}

test_not_json () {
    local output
    output=$(run_mfe -d -s ip-addr "$SAMPLES_DIR/json/basic.json" 2>&1)
    assert_contains "$output" "not applicable" "ip-addr should not match JSON"
}

run_test "ip-addr: detection" test_detect
run_test "ip-addr: extraction" test_extract
run_test "ip-addr: not confused with ip route" test_not_ip_route
run_test "ip-addr: not detected for JSON" test_not_json

print_summary
