#!/bin/bash
################################################################################
## Strategy Tests: wrk
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: wrk"
echo "========================================"

test_wrk_basic () {
    local output
    output=$(run_mfe -r -s wrk "$SAMPLES_DIR/wrk/basic.txt")
    assert_contains "$output" "threads 4" "should extract threads"
    assert_contains "$output" "connections 100" "should extract connections"
    assert_contains "$output" "requests_per_sec 49317.33" "should extract req/sec"
    assert_contains "$output" "transfer_per_sec 7.45MB" "should extract transfer/sec"
    assert_contains "$output" "latency_avg 250.12us" "should extract latency avg"
}

test_wrk_latency_distribution () {
    local output
    output=$(run_mfe -r -s wrk "$SAMPLES_DIR/wrk/basic.txt")
    assert_contains "$output" "latency_p50 245.00us" "should extract p50 latency"
    assert_contains "$output" "latency_p99 1.23ms" "should extract p99 latency"
    assert_contains "$output" "total_requests 1479520" "should extract total requests"
}

test_wrk_errors () {
    local output
    output=$(run_mfe -r -s wrk "$SAMPLES_DIR/wrk/errors.txt")
    assert_contains "$output" "socket_errors_read 5" "should extract read errors"
    assert_contains "$output" "socket_errors_timeout 2" "should extract timeout errors"
    assert_contains "$output" "requests_per_sec 18197.70" "should extract req/sec with errors"
}

test_wrk_not_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"name": "test", "value": 42}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s wrk "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "wrk should not apply to JSON"
}

run_test "wrk: basic extraction" test_wrk_basic
run_test "wrk: latency distribution" test_wrk_latency_distribution
run_test "wrk: socket errors" test_wrk_errors
run_test "wrk: not detected for JSON" test_wrk_not_json

print_summary
