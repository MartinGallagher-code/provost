#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Strategy Tests: colons
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: colons"
echo "========================================"

test_colons_basic () {
    local output
    output=$(run_mfe -r -s colons "$SAMPLES_DIR/colons/basic.txt")
    assert_contains "$output" "Name" "should extract Name field"
    assert_contains "$output" "Age" "should extract Age field"
    assert_contains "$output" "City" "should extract City field"
    assert_contains "$output" "42" "should extract value 42"
}


test_colons_field_selection () {
    local output
    output=$(run_mfe -s colons "$SAMPLES_DIR/colons/basic.txt" 1)
    assert_contains "$output" "Name" "should contain selected field"
    assert_contains "$output" "John Doe" "should contain field value"
}

test_colons_json_format () {
    local output
    output=$(run_mfe -s colons -f json "$SAMPLES_DIR/colons/basic.txt" 1,2)
    assert_contains "$output" '"Name":' "JSON should have Name key"
    assert_contains "$output" '"Age":' "JSON should have Age key"
}

test_colons_skips_non_fields () {
    # Input with URLs (colons in value) and numeric-starting lines
    local tmpfile
    tmpfile=$(mktemp)
    # TWO real pairs: `colons` needs more than one to claim an input, so a
    # fixture with a single pair proves nothing about skipping the rest.
    printf "Server: Apache\nPort: 8080\n123: bad key\nhttp://example.com\n" > "$tmpfile"
    local output
    output=$(run_mfe -r -s colons "$tmpfile")
    rm -f "$tmpfile"
    assert_contains "$output" "Server" "should extract Server"
    assert_not_contains "$output" "123" "should skip numeric-key lines"
}

run_test "colons: basic extraction" test_colons_basic
run_test "colons: field selection" test_colons_field_selection
run_test "colons: JSON format output" test_colons_json_format
run_test "colons: skips non-field lines" test_colons_skips_non_fields

print_summary
