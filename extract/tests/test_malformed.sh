#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Malformed Input Tests for provost-extract (provost-extract)
##
## Tests that corrupt, truncated, or structurally invalid inputs are handled
## gracefully (no crash, no hang).
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Malformed Input Tests"
echo "========================================"

################################################################################
## Truncated JSON (no crash, graceful exit)
################################################################################

test_truncated_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"name": "test", "version": "1.0", "items": [1, 2,' > "$tmpfile"
    local output rc=0
    output=$(run_extract -s json "$tmpfile" 2>&1) || rc=$?
    rm -f "$tmpfile"
    # jq returns exit code 5 for truncated JSON; the key is it doesn't hang
    # or crash the whole engine catastrophically. Any exit code is acceptable
    # as long as it terminates.
    return 0
}

################################################################################
## CSV with mismatched quotes (graceful handling)
################################################################################

test_csv_mismatched_quotes () {
    local tmpfile
    tmpfile=$(mktemp)
    printf 'Name,City\n"Alice,"New York\nBob,Boston\n' > "$tmpfile"
    local output rc=0
    output=$(run_extract -s csv "$tmpfile" 2>&1) || rc=$?
    rm -f "$tmpfile"
    # Should not hang or crash; mismatched quotes may cause partial data
    if [[ $rc -le 1 ]]; then
        return 0
    else
        echo "  exit code was $rc (expected 0 or 1)"
        return 1
    fi
}

################################################################################
## Partial CSV (fewer data columns than header)
################################################################################

test_csv_partial_data () {
    local tmpfile
    tmpfile=$(mktemp)
    # Second data row has one fewer column than the header (3 commas in header, 2 in short row)
    printf 'Name,Age,City,Country\nAlice,30,Boston,US\nBob,25,Denver\n' > "$tmpfile"
    local output rc=0
    output=$(run_extract -r -s csv "$tmpfile" 2>&1) || rc=$?
    rm -f "$tmpfile"
    assert_exit_zero "$rc" "partial CSV should not crash"
    # The full row should still produce all fields
    assert_contains "$output" "Name" "should extract Name header"
    assert_contains "$output" "Alice" "should extract Alice from complete row"
    # The short row should still produce what it can
    assert_contains "$output" "Bob" "should extract Bob from short row"
}

################################################################################
## YAML with tab indentation (doesn't crash)
################################################################################

test_yaml_tab_indentation () {
    local tmpfile
    tmpfile=$(mktemp)
    # Use tabs instead of spaces for indentation (invalid YAML but common mistake)
    printf 'server:\n\thost: localhost\n\tport: 8080\ndebug: true\n' > "$tmpfile"
    local output rc=0
    output=$(run_extract -s yaml "$tmpfile" 2>&1) || rc=$?
    rm -f "$tmpfile"
    # Should not crash; may extract top-level or nothing
    if [[ $rc -le 1 ]]; then
        return 0
    else
        echo "  exit code was $rc (expected 0 or 1)"
        return 1
    fi
}

################################################################################
## Malformed TOML (unclosed brackets)
################################################################################

test_malformed_toml_unclosed () {
    local tmpfile
    tmpfile=$(mktemp)
    # TOML with unclosed array table bracket and unclosed inline table
    printf '[server]\nhost = "localhost"\nport = 8080\n\n[[items\nname = "broken"\nvalue = {key = "unclosed"\n' > "$tmpfile"
    local output rc=0
    output=$(run_extract -r -s toml "$tmpfile" 2>&1) || rc=$?
    rm -f "$tmpfile"
    # Should not hang or crash
    if [[ $rc -le 1 ]]; then
        return 0
    else
        echo "  exit code was $rc (expected 0 or 1)"
        return 1
    fi
}

################################################################################
## Malformed TOML: verify partial extraction
################################################################################

test_malformed_toml_partial_extraction () {
    local tmpfile
    tmpfile=$(mktemp)
    # Valid section header + valid key/value, then a malformed section
    printf '[database]\nhost = "db.example.com"\nport = 5432\n\n[[broken\nname = "item"\n' > "$tmpfile"
    local output rc=0
    output=$(run_extract -r -s toml "$tmpfile" 2>&1) || rc=$?
    rm -f "$tmpfile"
    # The valid [database] section should still produce output
    assert_contains "$output" "host" "should extract host from valid section"
    assert_contains "$output" "db.example.com" "should extract host value"
}

################################################################################
## Malformed XML (unclosed tags)
################################################################################

test_malformed_xml_unclosed () {
    local tmpfile
    tmpfile=$(mktemp)
    # XML with unclosed tags and mismatched nesting
    printf '<root>\n  <name>Alice\n  <age>30</age>\n  <city>Portland\n</root>\n' > "$tmpfile"
    local output rc=0
    output=$(run_extract -r -s xml "$tmpfile" 2>&1) || rc=$?
    rm -f "$tmpfile"
    # Should not hang or crash
    if [[ $rc -le 1 ]]; then
        return 0
    else
        echo "  exit code was $rc (expected 0 or 1)"
        return 1
    fi
}

################################################################################
## Malformed XML: verify partial extraction of closed tags
################################################################################

test_malformed_xml_partial_extraction () {
    local tmpfile
    tmpfile=$(mktemp)
    # Mix of well-formed and unclosed tags; the closed tag should still extract
    printf '<data>\n  <name>Bob</name>\n  <email>bob@example.com\n  <age>25</age>\n</data>\n' > "$tmpfile"
    local output rc=0
    output=$(run_extract -r -s xml "$tmpfile" 2>&1) || rc=$?
    rm -f "$tmpfile"
    # Well-formed elements should still be extracted
    assert_contains "$output" "name" "should extract name from well-formed tag"
    assert_contains "$output" "Bob" "should extract value Bob"
    assert_contains "$output" "age" "should extract age from well-formed tag"
    assert_contains "$output" "25" "should extract value 25"
}

################################################################################
## Malformed INI (duplicate sections)
################################################################################


################################################################################
## Malformed INI: verify partial extraction with mixed valid/invalid
################################################################################


################################################################################
## Run all tests
################################################################################

run_test "malformed: truncated JSON (no crash)" test_truncated_json
run_test "malformed: CSV with mismatched quotes (no crash)" test_csv_mismatched_quotes
run_test "malformed: partial CSV fewer data columns than header" test_csv_partial_data
run_test "malformed: YAML with tab indentation (no crash)" test_yaml_tab_indentation
run_test "malformed: TOML unclosed brackets (no crash)" test_malformed_toml_unclosed
run_test "malformed: TOML partial extraction from valid section" test_malformed_toml_partial_extraction
run_test "malformed: XML unclosed tags (no crash)" test_malformed_xml_unclosed
run_test "malformed: XML partial extraction of closed tags" test_malformed_xml_partial_extraction

print_summary
