#!/bin/bash
################################################################################
## Strategy Tests: stress-ng
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: stress-ng"
echo "========================================"

test_stress_ng_basic () {
    local output
    output=$(run_mfe -r -s stress-ng "$SAMPLES_DIR/stress-ng/basic.txt")
    assert_contains "$output" "name cpu" "should extract stressor name"
    assert_contains "$output" "bogo_ops 567890" "should extract bogo ops"
    assert_contains "$output" "bogo_ops_per_sec_real 9464.83" "should extract bogo ops/sec real"
    assert_contains "$output" "run_duration 60.01s" "should extract run duration"
}

test_stress_ng_multi () {
    local output
    output=$(run_mfe -r -s stress-ng "$SAMPLES_DIR/stress-ng/multi.txt")
    assert_contains "$output" "name cpu" "should extract first stressor"
    assert_contains "$output" "stressor2.name vm" "should extract second stressor"
    assert_contains "$output" "stressor3.name io" "should extract third stressor"
    assert_contains "$output" "stressor3.bogo_ops 890123" "should extract io bogo ops"
}

test_stress_ng_not_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"name": "test", "value": 42}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s stress-ng "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "stress-ng should not apply to JSON"
}

run_test "stress-ng: basic single stressor" test_stress_ng_basic
run_test "stress-ng: multi stressor" test_stress_ng_multi
run_test "stress-ng: not detected for JSON" test_stress_ng_not_json

print_summary
