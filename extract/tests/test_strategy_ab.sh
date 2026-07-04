#!/bin/bash
################################################################################
## Strategy Tests: ab (Apache Bench)
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: ab"
echo "========================================"

test_ab_basic () {
    local output
    output=$(run_mfe -r -s ab "$SAMPLES_DIR/ab/basic.txt")
    assert_contains "$output" "server_software nginx/1.18.0" "should extract server software"
    assert_contains "$output" "server_hostname localhost" "should extract hostname"
    assert_contains "$output" "server_port 8080" "should extract port"
    assert_contains "$output" "concurrency_level 50" "should extract concurrency level"
}

test_ab_metrics () {
    local output
    output=$(run_mfe -r -s ab "$SAMPLES_DIR/ab/basic.txt")
    assert_contains "$output" "requests_per_second 4264.39" "should extract requests/sec"
    assert_contains "$output" "time_per_request_ms 11.725" "should extract time per request"
    assert_contains "$output" "complete_requests 10000" "should extract complete requests"
    assert_contains "$output" "failed_requests 0" "should extract failed requests"
}

test_ab_not_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"name": "test", "value": 42}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s ab "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "ab should not apply to JSON"
}

test_ab_no_csv_false_positive () {
    local output
    output=$(run_mfe -d -s csv "$SAMPLES_DIR/ab/basic.txt" 2>&1)
    assert_contains "$output" "not applicable" "csv should not false-match ab output"
}

test_ab_auto_no_csv () {
    local output
    output=$(run_mfe "$SAMPLES_DIR/ab/basic.txt")
    assert_not_contains "$output" "STRAT-csv" "auto-detect should not include csv results for ab"
}

run_test "ab: basic extraction" test_ab_basic
run_test "ab: metrics extraction" test_ab_metrics
run_test "ab: not detected for JSON" test_ab_not_json
run_test "ab: csv does not false-match" test_ab_no_csv_false_positive
run_test "ab: auto-detect excludes csv" test_ab_auto_no_csv

print_summary
