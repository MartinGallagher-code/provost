#!/bin/bash
################################################################################
## Strategy Tests: sqlite-output
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: sqlite-output"
echo "========================================"

test_sqlite_output_pipe () {
    local output
    output=$(run_mfe -r -s sqlite-output "$SAMPLES_DIR/sqlite-output/basic.txt")
    assert_contains "$output" "row1.id 1" "should extract row1 id"
    assert_contains "$output" "row1.name Alice" "should extract row1 name"
    assert_contains "$output" "row1.email alice@example.com" "should extract row1 email"
    assert_contains "$output" "row1.age 30" "should extract row1 age"
    assert_contains "$output" "row2.name Bob" "should extract row2 name"
    assert_contains "$output" "row3.name Charlie" "should extract row3 name"
}

test_sqlite_output_column () {
    local output
    output=$(run_mfe -r -s sqlite-output "$SAMPLES_DIR/sqlite-output/column.txt")
    assert_contains "$output" "row1.id 1" "should extract row1 id from column mode"
    assert_contains "$output" "row1.name Alice" "should extract row1 name from column mode"
    assert_contains "$output" "row1.email alice@example.com" "should extract row1 email from column mode"
    assert_contains "$output" "row2.name Bob" "should extract row2 name from column mode"
    assert_contains "$output" "row3.age 35" "should extract row3 age from column mode"
}

test_sqlite_output_not_detected_for_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"key": "value", "count": 42}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s sqlite-output "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "should not apply to JSON"
}

test_sqlite_output_not_detected_for_csv () {
    local output
    output=$(run_mfe -d -s sqlite-output "$SAMPLES_DIR/csv/basic.csv" 2>&1)
    assert_contains "$output" "not applicable" "should not apply to CSV"
}

run_test "sqlite-output: pipe-delimited extraction" test_sqlite_output_pipe
run_test "sqlite-output: column mode extraction" test_sqlite_output_column
run_test "sqlite-output: not detected for JSON" test_sqlite_output_not_detected_for_json
run_test "sqlite-output: not detected for CSV" test_sqlite_output_not_detected_for_csv

print_summary
