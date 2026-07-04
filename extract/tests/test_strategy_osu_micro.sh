#!/bin/bash
################################################################################
## Strategy Tests: osu-micro
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: osu-micro"
echo "========================================"

test_osu_micro_detect () {
    local output
    output=$(run_mfe -d -s osu-micro "$SAMPLES_DIR/osu-micro/basic.txt" 2>&1)
    assert_contains "$output" "applicable" "should detect osu-micro output"
}

test_osu_micro_values () {
    local output
    output=$(run_mfe -r -s osu-micro "$SAMPLES_DIR/osu-micro/basic.txt")
    assert_contains "$output" "benchmark_name MPI Latency Test" "should extract benchmark name"
    assert_contains "$output" "row1.size 0" "should extract first row size"
    assert_contains "$output" "row1.latency_us 0.22" "should extract first row latency"
    assert_contains "$output" "row22.size 1048576" "should extract last row size"
    assert_contains "$output" "row22.latency_us 312.45" "should extract last row latency"
    assert_contains "$output" "total_rows 22" "should extract total rows"
}

test_osu_micro_not_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"name": "test"}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s osu-micro "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "should not match JSON"
}

run_test "osu-micro: detection" test_osu_micro_detect
run_test "osu-micro: specific values" test_osu_micro_values
run_test "osu-micro: not detected for JSON" test_osu_micro_not_json

print_summary
