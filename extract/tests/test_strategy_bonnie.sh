#!/bin/bash
################################################################################
## Strategy Tests: bonnie++
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: bonnie"
echo "========================================"

test_bonnie_text () {
    local output
    output=$(run_mfe -r -s bonnie "$SAMPLES_DIR/bonnie/basic.txt")
    assert_contains "$output" "version 2.00a" "should extract version"
    assert_contains "$output" "random_seeks_per_sec 8765" "should extract random seeks"
}

test_bonnie_csv () {
    local output
    output=$(run_mfe -r -s bonnie "$SAMPLES_DIR/bonnie/csv.txt")
    assert_contains "$output" "hostname myhost" "should extract hostname"
    assert_contains "$output" "seq_output_block_kps 234567" "should extract seq output block"
    assert_contains "$output" "seq_input_block_kps 345678" "should extract seq input block"
    assert_contains "$output" "random_seeks_per_sec 8765" "should extract random seeks"
}

test_bonnie_not_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"name": "test", "value": 42}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s bonnie "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "bonnie should not apply to JSON"
}

run_test "bonnie: text format extraction" test_bonnie_text
run_test "bonnie: CSV format extraction" test_bonnie_csv
run_test "bonnie: not detected for JSON" test_bonnie_not_json

print_summary
