#!/bin/bash
################################################################################
## Strategy Tests: ibstat
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: ibstat"
echo "========================================"

test_ibstat_detect () {
    local output
    output=$(run_mfe -d -s ibstat "$SAMPLES_DIR/ibstat/basic.txt" 2>&1)
    assert_contains "$output" "applicable" "should detect ibstat output"
}

test_ibstat_values () {
    local output
    output=$(run_mfe -r -s ibstat "$SAMPLES_DIR/ibstat/basic.txt")
    assert_contains "$output" "ca1.name mlx5_0" "should extract CA name"
    assert_contains "$output" "ca1.ca_type MT4123" "should extract CA type"
    assert_contains "$output" "ca1.num_ports 1" "should extract number of ports"
    assert_contains "$output" "ca1.firmware_version 20.31.1014" "should extract firmware version"
    assert_contains "$output" "ca1.port1.state Active" "should extract port state"
    assert_contains "$output" "ca1.port1.physical_state LinkUp" "should extract physical state"
    assert_contains "$output" "ca1.port1.rate 200" "should extract port rate"
    assert_contains "$output" "ca1.port1.lid 47" "should extract base lid"
    assert_contains "$output" "ca1.port1.sm_lid 1" "should extract SM lid"
    assert_contains "$output" "ca1.port1.link_layer InfiniBand" "should extract link layer"
}

test_ibstat_not_json () {
    local tmpfile=$(mktemp)
    printf '{"name": "test"}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s ibstat "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "should not match JSON"
}

run_test "ibstat: detection" test_ibstat_detect
run_test "ibstat: specific values" test_ibstat_values
run_test "ibstat: not detected for JSON" test_ibstat_not_json

print_summary
