#!/bin/bash
################################################################################
## Encoding Tests for Envoy:Explore (envoy-extract)
##
## Tests that multi-byte / non-ASCII characters are handled without crashing
## or data loss by the engine and relevant strategies.
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Encoding Tests"
echo "========================================"

################################################################################
## UTF-8 multi-byte characters in colons input
################################################################################

test_utf8_colons () {
    local tmpfile
    tmpfile=$(mktemp)
    printf 'Name: Ren\xc3\xa9\nCity: Z\xc3\xbcrich\nRole: d\xc3\xa9veloppeur\n' > "$tmpfile"
    local output rc=0
    output=$(run_mfe -r -s colons "$tmpfile" 2>&1) || rc=$?
    rm -f "$tmpfile"
    assert_exit_zero "$rc" "should not crash on UTF-8 colons input"
    assert_contains "$output" "Name" "should extract Name field"
    assert_contains "$output" "City" "should extract City field"
}

################################################################################
## CSV with UTF-8 BOM
################################################################################

test_csv_utf8_bom () {
    local tmpfile
    tmpfile=$(mktemp)
    # Write UTF-8 BOM (EF BB BF) followed by CSV content
    printf '\xef\xbb\xbfName,Age,City\nAlice,30,Boston\n' > "$tmpfile"
    local output rc=0
    output=$(run_mfe -r -s csv "$tmpfile" 2>&1) || rc=$?
    rm -f "$tmpfile"
    assert_exit_zero "$rc" "should not crash on BOM CSV"
    assert_contains "$output" "Name" "should strip BOM and extract Name header"
    assert_contains "$output" "Alice" "should extract value Alice"
    assert_contains "$output" "30" "should extract value 30"
}

################################################################################
## Mixed ASCII/UTF-8 values in equals format
################################################################################

test_utf8_equals () {
    local tmpfile
    tmpfile=$(mktemp)
    printf 'Greeting=Caf\xc3\xa9\nTemp=25\xc2\xb0C\nStatus=OK\n' > "$tmpfile"
    local output rc=0
    output=$(run_mfe -r -s equals "$tmpfile" 2>&1) || rc=$?
    rm -f "$tmpfile"
    assert_exit_zero "$rc" "should not crash on UTF-8 equals input"
    assert_contains "$output" "Greeting" "should extract Greeting field"
    assert_contains "$output" "Status" "should extract Status field"
    assert_contains "$output" "OK" "should extract ASCII value OK"
}

################################################################################
## UTF-8 values round-trip through JSON format
################################################################################

test_utf8_json_format () {
    local tmpfile
    tmpfile=$(mktemp)
    printf 'Server: M\xc3\xbcnchen\nPort: 8080\n' > "$tmpfile"
    local output rc=0
    output=$(run_mfe -s colons -f json "$tmpfile" 1,2 2>&1) || rc=$?
    rm -f "$tmpfile"
    assert_exit_zero "$rc" "should not crash when formatting UTF-8 as JSON"
    assert_contains "$output" '"Server":' "JSON output should contain Server key"
    assert_contains "$output" '"Port":' "JSON output should contain Port key"
}

################################################################################
## Run all tests
################################################################################

run_test "encoding: UTF-8 multi-byte in colons input" test_utf8_colons
run_test "encoding: CSV with UTF-8 BOM stripping" test_csv_utf8_bom
run_test "encoding: mixed ASCII/UTF-8 in equals" test_utf8_equals
run_test "encoding: UTF-8 values in JSON format output" test_utf8_json_format

print_summary
