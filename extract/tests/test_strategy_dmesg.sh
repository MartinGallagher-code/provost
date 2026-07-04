#!/bin/bash
################################################################################
## Strategy Tests: dmesg
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: dmesg"
echo "========================================"

test_detect () {
    local output
    output=$(run_mfe -d -s dmesg "$SAMPLES_DIR/dmesg/basic.txt" 2>&1)
    assert_contains "$output" "applicable" "should detect dmesg output"

    # Should not detect JSON
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"name": "test", "value": 42}\n' > "$tmpfile"
    output=$(run_mfe -d -s dmesg "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "should not detect JSON"
}

test_extract () {
    local output
    output=$(run_mfe -r -s dmesg "$SAMPLES_DIR/dmesg/basic.txt")
    assert_contains "$output" "dmesg1_timestamp 0.000000" "should extract first timestamp"
    assert_contains "$output" "dmesg1_message Linux" "should extract first message word"
    assert_contains "$output" "dmesg5_timestamp 1.234567" "should extract ACPI timestamp"
    assert_contains "$output" "dmesg5_message ACPI:" "should extract ACPI message"
    assert_contains "$output" "dmesg8_message EXT4-fs" "should extract EXT4 message"
    assert_contains "$output" "dmesg10_message systemd[1]:" "should extract systemd message"
}

test_field_selection () {
    local output
    output=$(run_mfe -s dmesg "$SAMPLES_DIR/dmesg/basic.txt" dmesg1_timestamp,dmesg8_message)
    assert_contains "$output" "0.000000" "should include selected timestamp"
    assert_contains "$output" "EXT4-fs" "should include selected message"
    assert_not_contains "$output" "dmesg5_" "should exclude non-selected fields"
}

run_test "dmesg: detection" test_detect
run_test "dmesg: extraction" test_extract
run_test "dmesg: field selection" test_field_selection

print_summary
