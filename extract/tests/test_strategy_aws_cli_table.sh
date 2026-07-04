#!/bin/bash
################################################################################
## Strategy Tests: aws-cli-table
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: aws-cli-table"
echo "========================================"

test_aws_cli_table_basic () {
    local output
    output=$(run_mfe -r -s aws-cli-table "$SAMPLES_DIR/aws-cli-table/basic.txt")
    assert_contains "$output" "line1.Instance i-abc123" "should extract first instance ID"
    assert_contains "$output" "line1.Type t2.micro" "should extract first instance type"
    assert_contains "$output" "line2.State stopped" "should extract second state"
}

test_aws_cli_table_values () {
    local output
    output=$(run_mfe -r -s aws-cli-table "$SAMPLES_DIR/aws-cli-table/basic.txt")
    assert_contains "$output" "line1.State running" "should extract running state"
    assert_contains "$output" "line2.Instance i-def456" "should extract second instance"
    assert_contains "$output" "line2.Zone us-west-2" "should extract zone"
}

test_aws_cli_table_not_for_csv () {
    local tmpfile
    tmpfile=$(mktemp)
    printf 'name,age,city\nAlice,30,Boston\nBob,25,NYC\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s aws-cli-table "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "should not detect CSV"
}

run_test "aws-cli-table: basic extraction" test_aws_cli_table_basic
run_test "aws-cli-table: specific values" test_aws_cli_table_values
run_test "aws-cli-table: not detected for CSV" test_aws_cli_table_not_for_csv

print_summary
