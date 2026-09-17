#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Strategy Tests: equals
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: equals"
echo "========================================"

test_equals_basic () {
    local output
    output=$(run_mfe -r -s equals "$SAMPLES_DIR/equals/basic.txt")
    assert_contains "$output" "USER" "should extract USER"
    assert_contains "$output" "jdoe" "should extract value jdoe"
    assert_contains "$output" "HOME" "should extract HOME"
    assert_contains "$output" "SHELL" "should extract SHELL"
}

test_equals_field_selection () {
    local output
    output=$(run_mfe -s equals "$SAMPLES_DIR/equals/basic.txt" 1,2)
    assert_contains "$output" "USER" "should contain USER"
    assert_contains "$output" "HOME" "should contain HOME"
}

test_equals_skips_comparisons () {
    local tmpfile
    tmpfile=$(mktemp)
    printf "NAME=test\nif x == y then\na += b\nx != y\n" > "$tmpfile"
    local output
    output=$(run_mfe -r -s equals "$tmpfile")
    rm -f "$tmpfile"
    assert_contains "$output" "NAME" "should extract NAME"
    assert_not_contains "$output" "==" "should skip comparisons"
    assert_not_contains "$output" "+=" "should skip augmented assignments"
}

test_equals_json_format () {
    local output
    output=$(run_mfe -s equals -f json "$SAMPLES_DIR/equals/basic.txt" 1,2)
    assert_contains "$output" '"USER":' "JSON should have USER key"
    assert_contains "$output" '"HOME":' "JSON should have HOME key"
}

run_test "equals: basic extraction" test_equals_basic
run_test "equals: field selection" test_equals_field_selection
run_test "equals: skips comparisons" test_equals_skips_comparisons
run_test "equals: JSON format output" test_equals_json_format

print_summary
