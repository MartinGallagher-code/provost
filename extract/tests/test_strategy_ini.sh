#!/bin/bash
################################################################################
## Strategy Tests: ini
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: ini"
echo "========================================"

test_ini_basic () {
    local output
    output=$(run_mfe -r -s ini "$SAMPLES_DIR/ini/basic.ini")
    assert_contains "$output" "database.host localhost" "should extract database.host"
    assert_contains "$output" "database.port 5432" "should extract database.port"
    assert_contains "$output" "database.name mydb" "should extract database.name"
    assert_contains "$output" "server.host 0.0.0.0" "should extract server.host"
    assert_contains "$output" "server.port 8080" "should extract server.port"
    assert_contains "$output" "server.debug true" "should extract server.debug"
}

test_ini_colon_delimiter () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '[section]\nkey: value\nother: data\n' > "$tmpfile"
    local output
    output=$(run_mfe -r -s ini "$tmpfile")
    rm -f "$tmpfile"
    assert_contains "$output" "section.key value" "should handle colon delimiter"
    assert_contains "$output" "section.other data" "should handle second colon pair"
}

test_ini_skips_comments () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '[main]\n# this is a comment\nkey=value\n; another comment\nfoo=bar\n' > "$tmpfile"
    local output
    output=$(run_mfe -r -s ini "$tmpfile")
    rm -f "$tmpfile"
    assert_contains "$output" "main.key value" "should extract key"
    assert_contains "$output" "main.foo bar" "should extract foo"
    assert_not_contains "$output" "comment" "should skip comment lines"
}

test_ini_not_detected_for_json () {
    local output
    output=$(run_mfe -d -s ini "$SAMPLES_DIR/json/basic.json" 2>&1)
    assert_contains "$output" "not applicable" "ini should not apply to JSON"
}

run_test "ini: basic extraction" test_ini_basic
run_test "ini: colon delimiter" test_ini_colon_delimiter
run_test "ini: skips comments" test_ini_skips_comments
run_test "ini: not detected for JSON" test_ini_not_detected_for_json

print_summary
