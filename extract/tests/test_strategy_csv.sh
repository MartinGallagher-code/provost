#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Strategy Tests: csv
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: csv"
echo "========================================"

test_csv_basic () {
    local output
    output=$(run_mfe -r -s csv "$SAMPLES_DIR/csv/basic.csv")
    assert_contains "$output" "Name" "should extract Name header"
    assert_contains "$output" "John" "should extract value John"
    assert_contains "$output" "Age" "should extract Age header"
    assert_contains "$output" "30" "should extract value 30"
    assert_contains "$output" "City" "should extract City header"
}

test_csv_field_selection () {
    local output
    output=$(run_mfe -s csv "$SAMPLES_DIR/csv/basic.csv" 1,2)
    assert_contains "$output" "Name" "should contain field 1"
    assert_contains "$output" "Age" "should contain field 2"
}

test_csv_quoted_fields () {
    local tmpfile
    tmpfile=$(mktemp)
    printf 'Name,City\n"Smith, John","New York"\n' > "$tmpfile"
    local output
    output=$(run_mfe -r -s csv "$tmpfile")
    rm -f "$tmpfile"
    assert_contains "$output" "Name" "should extract Name"
    assert_contains "$output" "Smith, John" "should handle quoted commas"
}

test_csv_not_detected_for_non_csv () {
    local output
    output=$(run_mfe -d -s csv "$SAMPLES_DIR/json/basic.json" 2>&1)
    assert_contains "$output" "not applicable" "csv should not apply to JSON"
}

test_csv_trims_whitespace_after_comma () {
    # Values after a ", " delimiter must be trimmed like the header fields are —
    # the leading space must not become a leading underscore (`_b=6`).
    local tmpfile
    tmpfile=$(mktemp)
    printf 'a=1, b=2, c=3\na=5, b=6, c=7\n' > "$tmpfile"
    local output
    output=$(run_mfe -r -s csv "$tmpfile")
    rm -f "$tmpfile"
    assert_contains "$output" "a=1 a=5" "value should be clean"
    assert_contains "$output" "b=2 b=6" "value after ', ' must not gain a leading underscore"
    assert_not_contains "$output" "_b=6" "no leading underscore from the delimiter space"
}

# v2.0: each data row is an indexed record group (entry<N>.<col>) so the capture
# tidy melt renders one row per record — not one wide row with duplicate columns.
test_csv_rows_are_indexed_records () {
    local output
    output=$(run_mfe -r -s csv "$SAMPLES_DIR/csv/employees.csv")
    assert_contains "$output" "entry1.name Alice Johnson" "row 1 under entry1"
    assert_contains "$output" "entry3.department Engineering" "row 3 keeps its department (no dup-key drop)"
    assert_contains "$output" "entry5.title Junior Developer" "row 5 under entry5"
    assert_contains "$output" "total_entries 5" "five records"
}

run_test "csv: basic extraction" test_csv_basic
run_test "csv: rows are indexed records" test_csv_rows_are_indexed_records
run_test "csv: field selection" test_csv_field_selection
run_test "csv: quoted fields with commas" test_csv_quoted_fields
run_test "csv: not detected for non-CSV" test_csv_not_detected_for_non_csv
run_test "csv: trims whitespace after comma (no leading _)" test_csv_trims_whitespace_after_comma

print_summary
