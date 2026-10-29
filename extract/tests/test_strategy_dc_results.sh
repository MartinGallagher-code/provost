#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Strategy Tests: dc-results (the floor-plan viewer's results format)
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: dc-results"
echo "========================================"

_dcr () {   # extract TEXT with dc-results, plain
    local tmp out
    tmp="$(mktemp)"
    printf '%s\n' "$1" > "$tmp"
    out=$(run_extract -r -s dc-results -f plain "$tmp" 2>&1)
    rm -f "$tmp"
    printf '%s\n' "$out"
}

test_dcr_samples_are_rows () {
    local output
    output=$(run_extract -r -s dc-results -f plain "$SAMPLES_DIR/dc-results/basic.txt")
    assert_contains "$output" "entry1.test rtt_p99" "a sample's test"
    assert_contains "$output" "entry1.target wr01r01u01" "its target"
    assert_contains "$output" "entry1.value 182" "its value"
    assert_contains "$output" "entry1.peer wr01r02u01" "its own key=value"
    assert_contains "$output" "total_entries 6" "one row per sample, none for !test or #"
}

test_dcr_test_metadata_on_every_row () {
    local output
    output=$(run_extract -r -s dc-results -f plain "$SAMPLES_DIR/dc-results/basic.txt")
    assert_contains "$output" "entry2.unit us" "the test's unit on each of its samples"
    assert_contains "$output" "entry2.label RTT p99" "a quoted metadata value, quotes gone"
    assert_contains "$output" "entry4.unit pct" "a sample's own key wins over its test's"
    assert_not_contains "$output" "entry4.unit %" "…and the test's is not added beside it"
}

test_dcr_field_rule () {
    local output
    output=$(_dcr '!test,mbps,unit=Mbit/s
mbps,wr01,940,note="slow, then fast"
mbps  wr02   610   value=x test=y')
    assert_contains "$output" "entry1.target wr01" "commas separate"
    assert_contains "$output" "entry1.note slow, then fast" "a quoted value keeps its comma"
    assert_contains "$output" "entry2.value 610" "runs of spaces separate"
    assert_contains "$output" "entry2.meta_value x" "a key named value is meta_value"
    assert_contains "$output" "entry2.meta_test y" "a key named test is meta_test"
}

test_dcr_needs_test_lines () {
    local tmp output
    tmp="$(mktemp)"
    # what a results file written --no-meta looks like -- and `cpu0 user
    # 123` too: three words and a number, left to the generic parsers
    printf 'mbps\twr01\t940\nmbps\twr02\t610\n' > "$tmp"
    output=$(run_extract -d -s dc-results "$tmp" 2>&1)
    rm -f "$tmp"
    assert_contains "$output" "not applicable" "no !test line: not claimed"
}

test_dcr_needs_a_sample () {
    local tmp output
    tmp="$(mktemp)"
    printf '!test\tmbps\tunit=Mbit/s\n# nothing measured\n' > "$tmp"
    output=$(run_extract -d -s dc-results "$tmp" 2>&1)
    rm -f "$tmp"
    assert_contains "$output" "not applicable" "metadata alone is not a results file"
}

run_test "dc-results: a row per sample" test_dcr_samples_are_rows
run_test "dc-results: a test's metadata on its rows" test_dcr_test_metadata_on_every_row
run_test "dc-results: the format's field rule" test_dcr_field_rule
run_test "dc-results: needs !test lines" test_dcr_needs_test_lines
run_test "dc-results: needs a sample" test_dcr_needs_a_sample

print_summary
