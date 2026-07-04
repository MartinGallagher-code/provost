#!/bin/bash
################################################################################
## Strategy Tests: stream
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: stream"
echo "========================================"

test_stream_basic () {
    local output
    output=$(run_mfe -r -s stream "$SAMPLES_DIR/stream/basic.txt")
    assert_contains "$output" "copy.best_rate_MB_per_s 25012.3" "should extract Copy rate"
    assert_contains "$output" "scale.best_rate_MB_per_s 24589.1" "should extract Scale rate"
    assert_contains "$output" "add.best_rate_MB_per_s 27123.4" "should extract Add rate"
    assert_contains "$output" "triad.best_rate_MB_per_s 26876.5" "should extract Triad rate"
}

test_stream_metadata () {
    local output
    output=$(run_mfe -r -s stream "$SAMPLES_DIR/stream/basic.txt")
    assert_contains "$output" "array_size 10000000" "should extract array size"
    assert_contains "$output" "num_threads 4" "should extract thread count"
}

test_stream_timing () {
    local output
    output=$(run_mfe -r -s stream "$SAMPLES_DIR/stream/basic.txt")
    assert_contains "$output" "copy.min_time 0.006397" "should extract Copy min time"
    assert_contains "$output" "copy.max_time 0.006538" "should extract Copy max time"
    assert_contains "$output" "triad.avg_time 0.009042" "should extract Triad avg time"
}

test_stream_not_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"name": "test", "value": 42}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s stream "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "stream should not apply to JSON"
}

run_test "stream: bandwidth rate extraction" test_stream_basic
run_test "stream: metadata extraction" test_stream_metadata
run_test "stream: timing extraction" test_stream_timing
run_test "stream: not detected for JSON" test_stream_not_json

print_summary
