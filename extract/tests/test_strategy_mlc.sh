#!/bin/bash
################################################################################
## Strategy Tests: mlc
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: mlc"
echo "========================================"

test_mlc_latency () {
    local output
    output=$(run_mfe -r -s mlc "$SAMPLES_DIR/mlc/basic.txt")
    assert_contains "$output" "node0.idle_latency_ns 89.5" "should extract node0 latency"
    assert_contains "$output" "node1.idle_latency_ns 89.1" "should extract node1 latency"
}

test_mlc_bandwidth () {
    local output
    output=$(run_mfe -r -s mlc "$SAMPLES_DIR/mlc/basic.txt")
    assert_contains "$output" "peak.ALL_Reads_MB_per_s 45678.9" "should extract all-reads BW"
    assert_contains "$output" "peak.1:1_Reads-Writes_MB_per_s 38765.2" "should extract 1:1 BW"
}

test_mlc_not_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"name": "test", "value": 42}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s mlc "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "mlc should not apply to JSON"
}

run_test "mlc: idle latency extraction" test_mlc_latency
run_test "mlc: bandwidth extraction" test_mlc_bandwidth
run_test "mlc: not detected for JSON" test_mlc_not_json

print_summary
