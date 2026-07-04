#!/bin/bash
################################################################################
## Strategy Tests: iptables
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: iptables"
echo "========================================"

test_iptables_basic () {
    local output
    output=$(run_mfe -r -s iptables "$SAMPLES_DIR/iptables/basic.txt")
    assert_contains "$output" "chain1.name INPUT" "should extract first chain name"
    assert_contains "$output" "chain1.policy ACCEPT" "should extract first chain policy"
    assert_contains "$output" "chain2.name FORWARD" "should extract second chain name"
    assert_contains "$output" "chain2.policy DROP" "should extract second chain policy"
    assert_contains "$output" "chain3.name OUTPUT" "should extract third chain name"
    assert_contains "$output" "chain1.rule1.target ACCEPT" "should extract rule target"
    assert_contains "$output" "chain1.rule2.protocol tcp" "should extract rule protocol"
    assert_contains "$output" "chain1.rule2.source 0.0.0.0/0" "should extract rule source"
    assert_contains "$output" "chain1.rule4.target DROP" "should extract DROP rule target"
}

test_iptables_not_detected_for_json () {
    local output
    output=$(run_mfe -d -s iptables "$SAMPLES_DIR/json/basic.json" 2>&1)
    assert_contains "$output" "not applicable" "should not apply to JSON"
}

test_iptables_not_detected_for_aligned_columns () {
    local output
    output=$(run_mfe -d -s iptables "$SAMPLES_DIR/aligned-columns/basic.txt" 2>&1)
    assert_contains "$output" "not applicable" "should not apply to aligned columns"
}

run_test "iptables: basic extraction" test_iptables_basic
run_test "iptables: not detected for JSON" test_iptables_not_detected_for_json
run_test "iptables: not detected for aligned columns" test_iptables_not_detected_for_aligned_columns

print_summary
