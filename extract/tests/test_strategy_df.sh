#!/bin/bash
################################################################################
## Strategy Tests: df
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: df"
echo "========================================"

test_df_basic () {
    local output
    output=$(run_mfe -r -s df "$SAMPLES_DIR/df/basic.txt")
    assert_contains "$output" "entry1.filesystem /dev/sda1" "first filesystem"
    assert_contains "$output" "entry1.size 100G" "first size"
    assert_contains "$output" "entry1.use_percent 43" "use% stripped to a number"
    assert_contains "$output" "entry1.mounted_on /" "first mount point"
    assert_contains "$output" "entry2.filesystem tmpfs" "second filesystem"
    assert_contains "$output" "total_entries 3" "counts all rows, skips the header"
}

test_df_detects () {
    local output
    output=$(run_mfe -d -s df "$SAMPLES_DIR/df/basic.txt" 2>&1)
    assert_not_contains "$output" "not applicable" "df must match df output"
}

test_df_not_detected_for_json () {
    local output
    output=$(run_mfe -d -s df "$SAMPLES_DIR/json/basic.json" 2>&1)
    assert_contains "$output" "not applicable" "should not apply to JSON"
}

run_test "df: basic extraction (one row per mount)" test_df_basic
run_test "df: detected on df output" test_df_detects
run_test "df: not detected for JSON" test_df_not_detected_for_json

print_summary
