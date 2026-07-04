#!/bin/bash
################################################################################
## Strategy Tests: pipe-table
## Consolidates tests from: sql-result, markdown-table
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: pipe-table"
echo "========================================"

# --- SQL style (+---+ borders) ---

test_pt_sql_basic () {
    local output
    output=$(run_mfe -r -s pipe-table "$SAMPLES_DIR/sql-result/basic.txt")
    assert_contains "$output" "row1.id 1" "should extract first row id"
    assert_contains "$output" "row1.username alice" "should extract first username"
    assert_contains "$output" "row2.score 87" "should extract second score"
}

test_pt_sql_values () {
    local output
    output=$(run_mfe -r -s pipe-table "$SAMPLES_DIR/sql-result/basic.txt")
    assert_contains "$output" "row2.username bob" "should extract bob"
    assert_contains "$output" "row3.username charlie" "should extract charlie"
    assert_contains "$output" "row3.score 92" "should extract third score"
}

# --- Markdown style (|---| separators) ---

test_pt_markdown_basic () {
    local output
    output=$(run_mfe -r -s pipe-table "$SAMPLES_DIR/markdown-table/basic.md")
    assert_contains "$output" "Name John" "should extract Name John"
    assert_contains "$output" "Age 30" "should extract Age 30"
    assert_contains "$output" "City Portland" "should extract City Portland"
}

test_pt_markdown_multiple_rows () {
    local output
    output=$(run_mfe -r -s pipe-table "$SAMPLES_DIR/markdown-table/basic.md")
    assert_contains "$output" "Name Jane" "should extract second row Name Jane"
    assert_contains "$output" "Age 25" "should extract second row Age 25"
    assert_contains "$output" "City Seattle" "should extract second row City Seattle"
}

test_pt_markdown_field_selection () {
    local output
    output=$(run_mfe -s pipe-table "$SAMPLES_DIR/markdown-table/basic.md" 1,2)
    assert_contains "$output" "Name" "should contain field 1"
    assert_contains "$output" "Age" "should contain field 2"
}

# v1.1: markdown rows are grouped (row<N>.<field>) like the SQL style, so the
# capture tidy melt renders one row per table row instead of welding them.
test_pt_markdown_row_groups () {
    local output
    output=$(run_mfe -r -s pipe-table "$SAMPLES_DIR/markdown-table/basic.md")
    assert_contains "$output" "row1.Name John" "row 1 grouped under row1"
    assert_contains "$output" "row2.Name Jane" "row 2 grouped under row2"
}

# --- Detection rejection ---

test_pt_not_detected_for_json () {
    local output
    output=$(run_mfe -d -s pipe-table "$SAMPLES_DIR/json/basic.json" 2>&1)
    assert_contains "$output" "not applicable" "pipe-table should not apply to JSON"
}

# --- Inline input tests ---

test_pt_sql_inline () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '+------+-------+\n| host | port  |\n+------+-------+\n| web1 | 80    |\n| db1  | 5432  |\n+------+-------+\n' > "$tmpfile"
    local output
    output=$(run_mfe -r -s pipe-table "$tmpfile")
    rm -f "$tmpfile"
    assert_contains "$output" "row1.host web1" "should extract SQL row1 host"
    assert_contains "$output" "row1.port 80" "should extract SQL row1 port"
    assert_contains "$output" "row2.host db1" "should extract SQL row2 host"
    assert_contains "$output" "row2.port 5432" "should extract SQL row2 port"
}

test_pt_markdown_inline () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '| Name | Age |\n|------|-----|\n| Alice | 30 |\n| Bob | 25 |\n' > "$tmpfile"
    local output
    output=$(run_mfe -r -s pipe-table "$tmpfile")
    rm -f "$tmpfile"
    assert_contains "$output" "Name Alice" "should extract markdown Name Alice"
    assert_contains "$output" "Age 30" "should extract markdown Age 30"
    assert_contains "$output" "Name Bob" "should extract markdown Name Bob"
    assert_contains "$output" "Age 25" "should extract markdown Age 25"
}

run_test "pipe-table: SQL basic extraction" test_pt_sql_basic
run_test "pipe-table: SQL specific values" test_pt_sql_values
run_test "pipe-table: Markdown basic extraction" test_pt_markdown_basic
run_test "pipe-table: Markdown multiple rows" test_pt_markdown_multiple_rows
run_test "pipe-table: Markdown field selection" test_pt_markdown_field_selection
run_test "pipe-table: Markdown row groups" test_pt_markdown_row_groups
run_test "pipe-table: not detected for JSON" test_pt_not_detected_for_json
run_test "pipe-table: SQL inline input" test_pt_sql_inline
run_test "pipe-table: Markdown inline input" test_pt_markdown_inline

print_summary
