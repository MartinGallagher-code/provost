#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
source "$SCRIPT_DIR/helpers.sh"

CSV_LIB="$(cd "$SCRIPT_DIR/.." && pwd)/lib/_csv.sh"
cleanup_files=()  # required by _csv.sh

source "$CSV_LIB"

################################################################################
## CSV preprocessing tests
################################################################################

test_bom_stripping () {
    local tmp
    tmp=$(mktemp -t test-bom.XXXXXX)
    cleanup_files+=("$tmp")
    # Write a file with BOM followed by "hello"
    printf '\xEF\xBB\xBFname,value\na,1\n' > "$tmp"
    strip_bom "$tmp"
    local result_file="$_STRIP_BOM_RESULT"
    local first3
    first3=$(head -c 3 "$result_file" | od -An -tx1 | tr -d ' \n')
    if [[ "$first3" == "efbbbf" ]]; then
        echo "  ASSERT FAILED: BOM should have been stripped"
        rm -f "$tmp"
        return 1
    fi
    # Original file should NOT be modified
    local orig_first3
    orig_first3=$(head -c 3 "$tmp" | od -An -tx1 | tr -d ' \n')
    if [[ "$orig_first3" != "efbbbf" ]]; then
        echo "  ASSERT FAILED: original file should not be modified"
        rm -f "$tmp"
        return 1
    fi
    assert_contains "$(cat "$result_file")" "name,value" "content should be intact after BOM strip"
    rm -f "$tmp"
}

test_no_bom_passthrough () {
    local tmp
    tmp=$(mktemp -t test-nobom.XXXXXX)
    cleanup_files+=("$tmp")
    printf 'name,value\na,1\n' > "$tmp"
    strip_bom "$tmp"
    # When no BOM, _STRIP_BOM_RESULT should point back to the original file
    if [[ "$_STRIP_BOM_RESULT" != "$tmp" ]]; then
        echo "  ASSERT FAILED: no-BOM file should return original path, got $_STRIP_BOM_RESULT"
        rm -f "$tmp"
        return 1
    fi
    assert_contains "$(cat "$_STRIP_BOM_RESULT")" "name,value" "file without BOM should be unchanged"
    rm -f "$tmp"
}

test_needs_csv_preprocess_yes () {
    local tmp
    tmp=$(mktemp -t test-csv.XXXXXX)
    printf '"Smith, John",100\n' > "$tmp"
    if ! needs_csv_preprocess "$tmp"; then
        echo "  ASSERT FAILED: file with quotes should need preprocessing"
        rm -f "$tmp"
        return 1
    fi
    rm -f "$tmp"
}

test_needs_csv_preprocess_no () {
    local tmp
    tmp=$(mktemp -t test-csv.XXXXXX)
    printf 'Smith,100\nJohn,200\n' > "$tmp"
    if needs_csv_preprocess "$tmp"; then
        echo "  ASSERT FAILED: file without quotes should not need preprocessing"
        rm -f "$tmp"
        return 1
    fi
    rm -f "$tmp"
}

test_csv_quoted_comma () {
    local tmp
    tmp=$(mktemp -t test-csv.XXXXXX)
    printf 'name,value\n"Smith, John",100\n' > "$tmp"
    local result
    result=$(csv_to_tsv "$tmp" ",")
    assert_contains "$result" "Smith, John" "comma inside quotes should be preserved"
    assert_not_contains "$result" '"' "quotes should be stripped"
    rm -f "$tmp"
}

test_csv_escaped_quotes () {
    local tmp
    tmp=$(mktemp -t test-csv.XXXXXX)
    printf 'name,note\nAlice,"has ""quotes"""\n' > "$tmp"
    local result
    result=$(csv_to_tsv "$tmp" ",")
    assert_contains "$result" 'has "quotes"' "escaped quotes should become single quotes"
    rm -f "$tmp"
}

test_csv_embedded_newline () {
    local tmp
    tmp=$(mktemp -t test-csv.XXXXXX)
    printf 'name,note\nAlice,"line one\nline two"\n' > "$tmp"
    local result
    result=$(csv_to_tsv "$tmp" ",")
    # Embedded newline replaced with literal \n, so it fits in one TSV row
    local line_count
    line_count=$(echo "$result" | wc -l)
    if [[ "$line_count" -ne 2 ]]; then
        echo "  ASSERT FAILED: embedded newline should produce 2 output lines (header + data), got $line_count"
        return 1
    fi
    rm -f "$tmp"
}

test_csv_empty_quoted_field () {
    local tmp
    tmp=$(mktemp -t test-csv.XXXXXX)
    printf 'a,b\n"",value\n' > "$tmp"
    local result
    result=$(csv_to_tsv "$tmp" ",")
    # First field should be empty (just a tab before "value")
    local data_line
    data_line=$(echo "$result" | tail -1)
    if [[ "$data_line" != $'\t'"value" ]]; then
        echo "  ASSERT FAILED: empty quoted field should produce empty string, got: '$data_line'"
        return 1
    fi
    rm -f "$tmp"
}

test_csv_mixed_quoting () {
    local tmp
    tmp=$(mktemp -t test-csv.XXXXXX)
    printf 'a,b,c\nunquoted,"quoted, with comma",123\n' > "$tmp"
    local result
    result=$(csv_to_tsv "$tmp" ",")
    local data_line
    data_line=$(echo "$result" | tail -1)
    # Should have 3 tab-separated fields
    local field_count
    field_count=$(echo "$data_line" | awk -F'\t' '{print NF}')
    if [[ "$field_count" -ne 3 ]]; then
        echo "  ASSERT FAILED: mixed quoting should produce 3 fields, got $field_count"
        return 1
    fi
    assert_contains "$data_line" "quoted, with comma" "quoted field with comma should be intact"
    rm -f "$tmp"
}

test_quoted_csv_full_pipeline () {
    # Run envoy-analyze on our quoted.csv sample and verify it parses correctly
    local output
    output=$(run_mda "$SAMPLES_DIR/quoted.csv")
    assert_contains "$output" "Rows: 6" "quoted.csv should have 6 data rows"
    assert_contains "$output" "Columns: 4" "quoted.csv should have 4 columns"
    assert_contains "$output" "Delimiter: tab" "preprocessed CSV should use tab delimiter"
}

test_missing_expanded_forms () {
    # Run envoy-analyze on missing.csv and verify expanded missing detection
    local output
    output=$(run_mda "$SAMPLES_DIR/missing.csv")
    assert_contains "$output" "value: 5 missing" "value column should have 5 missing (empty, NaN, null, NULL, .)"
    assert_contains "$output" "score: 5 missing" "score column should have 5 missing (empty, N/A, nan, none, -)"
}

########################################
## Run all CSV parsing tests
##

run_test "BOM stripping" test_bom_stripping
run_test "no-BOM passthrough" test_no_bom_passthrough
run_test "needs_csv_preprocess detects quotes" test_needs_csv_preprocess_yes
run_test "needs_csv_preprocess skips clean files" test_needs_csv_preprocess_no
run_test "CSV quoted comma preserved" test_csv_quoted_comma
run_test "CSV escaped quotes (\"\")" test_csv_escaped_quotes
run_test "CSV embedded newline" test_csv_embedded_newline
run_test "CSV empty quoted field" test_csv_empty_quoted_field
run_test "CSV mixed quoting" test_csv_mixed_quoting
run_test "quoted CSV full pipeline" test_quoted_csv_full_pipeline
run_test "expanded missing value forms" test_missing_expanded_forms

print_summary
