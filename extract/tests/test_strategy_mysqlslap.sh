#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: mysqlslap"
echo "========================================"

test_mysqlslap_basic () {
    local output
    output=$(run_mfe -r -s mysqlslap "$SAMPLES_DIR/mysqlslap/basic.txt")
    assert_contains "$output" "avg_seconds" "should extract avg seconds"
    assert_contains "$output" "clients" "should extract client count"
    assert_contains "$output" "queries_per_client" "should extract queries per client"
}

test_mysqlslap_values () {
    local output
    output=$(run_mfe -r -s mysqlslap "$SAMPLES_DIR/mysqlslap/basic.txt")
    assert_contains "$output" "avg_seconds 0.345" "should extract correct avg"
    assert_contains "$output" "clients 50" "should extract correct clients"
    assert_contains "$output" "run2.avg_seconds 1.234" "should extract second run avg"
    assert_contains "$output" "run2.clients 100" "should extract second run clients"
}

test_mysqlslap_not_json () {
    local tmpfile=$(mktemp)
    printf '{"name": "test"}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s mysqlslap "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "should not match JSON"
}

run_test "mysqlslap: basic extraction" test_mysqlslap_basic
run_test "mysqlslap: specific values" test_mysqlslap_values
run_test "mysqlslap: not detected for JSON" test_mysqlslap_not_json

print_summary
