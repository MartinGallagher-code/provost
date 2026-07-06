#!/bin/bash
################################################################################
## Strategy Tests: imb
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: imb"
echo "========================================"

test_imb_detect () {
    local output
    output=$(run_mfe -d -s imb "$SAMPLES_DIR/imb/basic.txt" 2>&1)
    assert_contains "$output" "applicable" "should detect imb output"
}

test_imb_values () {
    local output
    output=$(run_mfe -r -s imb "$SAMPLES_DIR/imb/basic.txt")
    assert_contains "$output" "imb_version 2021.3" "should extract IMB version"
    assert_contains "$output" "num_processes 2" "should extract process count"
    assert_contains "$output" "bench1.name PingPong" "should extract benchmark name"
    assert_contains "$output" "bench1.row1.bytes 0" "should extract first row bytes"
    assert_contains "$output" "bench1.row1.t_avg_usec 0.22" "should extract first row latency"
    assert_contains "$output" "bench1.row24.bytes 4194304" "should extract last row bytes"
    assert_contains "$output" "bench1.row24.Mbytes_per_sec 4956.12" "should extract last row bandwidth"
    assert_contains "$output" "total_benchmarks 1" "should extract total benchmarks"
}

test_imb_not_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"name": "test"}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s imb "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "should not match JSON"
}

run_test "imb: detection" test_imb_detect
run_test "imb: specific values" test_imb_values
run_test "imb: not detected for JSON" test_imb_not_json

print_summary
