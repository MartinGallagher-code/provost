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
## ASCII-art gutter (multi-byte art characters)
##
## `cilium status` draws a hexagon down the left margin out of `/`, `\`, `_`
## and `¯` (U+00AF, two bytes in UTF-8) with its real output to the right, on
## the same lines. The art is not a column.
################################################################################

test_art_gutter_stripped () {
    local tmpfile output
    tmpfile=$(mktemp)
    printf '    /\xc2\xaf\xc2\xaf\\\n /\xc2\xaf\xc2\xaf\\__/\xc2\xaf\xc2\xaf\\    Cilium:      OK\n \\__/\xc2\xaf\xc2\xaf\\__/    Operator:    OK\n    \\__/       ClusterMesh: disabled\n' > "$tmpfile"
    output=$(run_mfe -f plain --max-strategies 1 "$tmpfile" 2>/dev/null)
    rm -f "$tmpfile"
    assert_contains "$output" "Cilium" "the content beside the art survives"
    assert_not_contains "$output" "__/" "the art itself is gone from the keys"
}

# ...but an ordinary indented left margin is NOT art and must be left alone.
test_indent_is_not_art_gutter () {
    local tmpfile output
    tmpfile=$(mktemp)
    printf 'Conditions:\n  Type      Status\n  Available True\n  Ready     True\n' > "$tmpfile"
    output=$(run_mfe -f plain --max-strategies 1 "$tmpfile" 2>/dev/null)
    rm -f "$tmpfile"
    assert_contains "$output" "Available" "an indented block parses as before"
}

################################################################################
## Run all tests
################################################################################

run_test "encoding: ASCII-art gutter stripped" test_art_gutter_stripped
run_test "encoding: plain indent is not art" test_indent_is_not_art_gutter
run_test "encoding: UTF-8 multi-byte in colons input" test_utf8_colons
run_test "encoding: CSV with UTF-8 BOM stripping" test_csv_utf8_bom
run_test "encoding: mixed ASCII/UTF-8 in equals" test_utf8_equals
run_test "encoding: UTF-8 values in JSON format output" test_utf8_json_format

print_summary
