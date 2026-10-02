#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Strategy Tests: indented-hierarchy
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: indented-hierarchy"
echo "========================================"

test_ih_basic () {
    local output
    output=$(run_extract -r -s indented-hierarchy "$SAMPLES_DIR/indented-hierarchy/basic.txt")
    assert_contains "$output" "System_Information.Manufacturer Dell Inc." "should extract Manufacturer under System Information"
    assert_contains "$output" "System_Information.Product_Name PowerEdge R740" "should extract Product Name"
    assert_contains "$output" "System_Information.Serial_Number ABC123" "should extract Serial Number"
}

test_ih_deep_nesting () {
    local output
    output=$(run_extract -r -s indented-hierarchy "$SAMPLES_DIR/indented-hierarchy/basic.txt")
    assert_contains "$output" "System_Information.BIOS_Information.Vendor Dell Inc." "should extract nested BIOS Vendor"
    assert_contains "$output" "System_Information.BIOS_Information.Version 2.12.2" "should extract nested BIOS Version"
    assert_contains "$output" "System_Information.Memory.Total 64 GB" "should extract Memory Total"
    assert_contains "$output" "System_Information.Memory.Type DDR4" "should extract Memory Type"
    assert_contains "$output" "System_Information.Memory.Speed 2933 MHz" "should extract Memory Speed"
}

test_ih_not_detected_for_json () {
    local output
    output=$(run_extract -d -s indented-hierarchy "$SAMPLES_DIR/json/basic.json" 2>&1)
    assert_contains "$output" "not applicable" "indented-hierarchy should not apply to JSON"
}

run_test "indented-hierarchy: basic extraction with nested keys" test_ih_basic
run_test "indented-hierarchy: deep nesting" test_ih_deep_nesting
run_test "indented-hierarchy: not detected for JSON" test_ih_not_detected_for_json

print_summary
