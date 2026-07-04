#!/bin/bash
################################################################################
## Strategy Tests: dns-record
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: dns-record"
echo "========================================"

test_dns_basic () {
    local output
    output=$(run_mfe -r -s dns-record "$SAMPLES_DIR/dns-record/basic.txt")
    assert_contains "$output" "record1.name example.com." "should extract record1 name"
    assert_contains "$output" "record1.ttl 300" "should extract record1 ttl"
    assert_contains "$output" "record1.type A" "should extract record1 type"
    assert_contains "$output" "record1.value 93.184.216.34" "should extract record1 value"
}

test_dns_multiple_types () {
    local output
    output=$(run_mfe -r -s dns-record "$SAMPLES_DIR/dns-record/basic.txt")
    assert_contains "$output" "record2.type AAAA" "should extract AAAA record type"
    assert_contains "$output" "record2.value 2606:2800:220:1:248:1893:25c8:1946" "should extract AAAA value"
    assert_contains "$output" "query_time" "should extract query time"
    assert_contains "$output" "server 8.8.8.8" "should extract server"
}

test_dns_not_detected_for_json () {
    local output
    output=$(run_mfe -d -s dns-record "$SAMPLES_DIR/json/basic.json" 2>&1)
    assert_contains "$output" "not applicable" "dns-record should not apply to JSON"
}

run_test "dns-record: basic extraction" test_dns_basic
run_test "dns-record: multiple record types" test_dns_multiple_types
run_test "dns-record: not detected for JSON" test_dns_not_detected_for_json

print_summary
