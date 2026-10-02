#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Strategy Tests: tsv
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: tsv"
echo "========================================"

test_tsv_basic () {
    local output
    output=$(run_extract -r -s tsv "$SAMPLES_DIR/tsv/basic.tsv")
    assert_contains "$output" "Name" "should extract Name header"
    assert_contains "$output" "John" "should extract value John"
    assert_contains "$output" "Age" "should extract Age header"
    assert_contains "$output" "30" "should extract value 30"
    assert_contains "$output" "City" "should extract City header"
    assert_contains "$output" "Portland" "should extract value Portland"
}

test_tsv_field_selection () {
    local output
    output=$(run_extract -s tsv "$SAMPLES_DIR/tsv/basic.tsv" 1,2)
    assert_contains "$output" "Name" "should contain field 1"
    assert_contains "$output" "Age" "should contain field 2"
}

test_tsv_multiple_rows () {
    local output
    output=$(run_extract -r -s tsv "$SAMPLES_DIR/tsv/basic.tsv")
    assert_contains "$output" "Jane" "should extract second row value Jane"
    assert_contains "$output" "Seattle" "should extract second row value Seattle"
}

test_tsv_not_detected_for_json () {
    local output
    output=$(run_extract -d -s tsv "$SAMPLES_DIR/json/basic.json" 2>&1)
    assert_contains "$output" "not applicable" "tsv should not apply to JSON"
}

# An empty cell in genuine TSV must stay in its column — it used to be dropped,
# shifting every later value one column left (b=6, c lost).
test_tsv_empty_cell_keeps_columns () {
    local tmp output
    tmp="$(mktemp)"
    printf 'a\tb\tc\n1\t2\t3\n4\t\t6\n' > "$tmp"
    output=$(run_extract -r -s tsv -f plain "$tmp")
    rm -f "$tmp"
    assert_contains "$output" "entry2.a 4" "row 2 keeps a=4"
    assert_contains "$output" "entry2.c 6" "row 2 keeps c=6 in column c"
    assert_not_contains "$output" "entry2.b 6" "6 must not shift left into column b"
}

test_tsv_empty_cells_sample () {
    local output
    output=$(run_extract -r -s tsv -f plain "$SAMPLES_DIR/tsv/empty-cells.tsv")
    assert_contains "$output" "entry2.owner bob" "db01 owner stays under owner"
    assert_not_contains "$output" "entry2.role bob" "bob must not shift into role"
    assert_contains "$output" "entry3.role cache" "cache01 role stays under role"
    assert_not_contains "$output" "entry3.ip cache" "cache must not shift into ip"
}

# Tab-PADDED display output still collapses tab runs (proc-cpuinfo's
# `flags<TAB><TAB>: …`): the column count only agrees after collapsing.
test_tsv_tab_padding_collapses () {
    local tmp output
    tmp="$(mktemp)"
    printf 'processor\t: 0\nvendor_id\t: GenuineIntel\nflags\t\t: fpu vme\nbogomips\t: 4800\n' > "$tmp"
    output=$(run_extract -r -s tsv -f plain "$tmp")
    rm -f "$tmp"
    assert_contains "$output" "entry3.A flags" "flags row keeps its label in A"
    assert_contains "$output" "entry3.B : fpu vme" "flags value lands in B, not a phantom column"
}

# A value keeps its inner spaces exactly (the field stream splits name/value
# at the FIRST space only).
test_tsv_value_spaces_kept () {
    local tmp output
    tmp="$(mktemp)"
    printf 'name\tcity\tnote\nJohn Smith\tNew York\tlikes a_b\nJane Doe\tLos Angeles\tx\n' > "$tmp"
    output=$(run_extract -r -s tsv -f plain "$tmp")
    rm -f "$tmp"
    assert_contains "$output" "entry1.name John Smith" "space kept in name value"
    assert_contains "$output" "entry1.city New York" "space kept in city value"
    assert_contains "$output" "entry1.note likes a_b" "a real underscore stays distinguishable"
    assert_not_contains "$output" "John_Smith" "no underscore invented for a space"
}

run_test "tsv: empty cell keeps its column" test_tsv_empty_cell_keeps_columns
run_test "tsv: empty-cells sample" test_tsv_empty_cells_sample
run_test "tsv: tab-padded display output still collapses" test_tsv_tab_padding_collapses
run_test "tsv: values keep spaces" test_tsv_value_spaces_kept
run_test "tsv: basic extraction" test_tsv_basic
run_test "tsv: field selection" test_tsv_field_selection
run_test "tsv: multiple rows" test_tsv_multiple_rows
run_test "tsv: not detected for JSON" test_tsv_not_detected_for_json

print_summary
