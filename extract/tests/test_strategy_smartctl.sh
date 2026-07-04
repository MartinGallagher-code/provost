#!/bin/bash
################################################################################
## Strategy Tests: smartctl
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: smartctl"
echo "========================================"

test_detect () {
    local output
    output=$(run_mfe -d -s smartctl "$SAMPLES_DIR/smartctl/basic.txt" 2>&1)
    assert_contains "$output" "applicable" "should detect smartctl output"

    # Should not detect JSON
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"name": "test", "value": 42}\n' > "$tmpfile"
    output=$(run_mfe -d -s smartctl "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "should not detect JSON"
}

test_extract () {
    local output
    output=$(run_mfe -r -s smartctl "$SAMPLES_DIR/smartctl/basic.txt")
    assert_contains "$output" "Device_Model WDC WD10EZEX-08WN4A0" "should extract device model"
    assert_contains "$output" "Serial_Number WD-WMC3T0123456" "should extract serial number"
    assert_contains "$output" "Firmware_Version 01.01A01" "should extract firmware version"
    assert_contains "$output" "User_Capacity 1.00 TB" "should extract user capacity"
    assert_contains "$output" "SMART_health PASSED" "should extract SMART health"
    assert_contains "$output" "Power_On_Hours 4234" "should extract power on hours"
    assert_contains "$output" "Temperature_Celsius 39" "should extract temperature"
    assert_contains "$output" "Reallocated_Sector_Ct 0" "should extract reallocated sectors"
}

test_field_selection () {
    local output
    output=$(run_mfe -s smartctl "$SAMPLES_DIR/smartctl/basic.txt" SMART_health,Power_On_Hours,Temperature_Celsius)
    assert_contains "$output" "PASSED" "should include health status"
    assert_contains "$output" "4234" "should include power on hours"
    assert_contains "$output" "39" "should include temperature"
    assert_not_contains "$output" "Serial_Number" "should exclude non-selected fields"
}

run_test "smartctl: detection" test_detect
run_test "smartctl: extraction" test_extract
run_test "smartctl: field selection" test_field_selection

print_summary
