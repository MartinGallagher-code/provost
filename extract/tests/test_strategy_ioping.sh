#!/bin/bash
################################################################################
## Strategy Tests: ioping
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: ioping"
echo "========================================"

test_ioping_latency () {
    local output
    output=$(run_mfe -r -s ioping "$SAMPLES_DIR/ioping/basic.txt")
    assert_contains "$output" "latency_avg 990 us" "should extract average latency"
    assert_contains "$output" "latency_min 223 us" "should extract min latency"
    assert_contains "$output" "latency_max 2.69 ms" "should extract max latency"
}

test_ioping_iops () {
    local output
    output=$(run_mfe -r -s ioping "$SAMPLES_DIR/ioping/basic.txt")
    assert_contains "$output" "requests_completed 20" "should extract request count"
    assert_contains "$output" "throughput 3.95_MiB/s" "should extract throughput"
}

test_ioping_not_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"name": "test", "value": 42}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s ioping "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "ioping should not apply to JSON"
}

run_test "ioping: latency extraction" test_ioping_latency
run_test "ioping: iops and throughput extraction" test_ioping_iops
run_test "ioping: not detected for JSON" test_ioping_not_json

print_summary
