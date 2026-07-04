#!/bin/bash
################################################################################
## Strategy Tests: h5dump
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: h5dump"
echo "========================================"

test_h5dump_detect () {
    local output
    output=$(run_mfe -d -s h5dump "$SAMPLES_DIR/h5dump/basic.txt" 2>&1)
    assert_contains "$output" "applicable" "should detect h5dump output"
}

test_h5dump_values () {
    local output
    output=$(run_mfe -r -s h5dump "$SAMPLES_DIR/h5dump/basic.txt")
    assert_contains "$output" "filename simulation_output.h5" "should extract filename"
    assert_contains "$output" "num_datasets 3" "should count 3 datasets"
    assert_contains "$output" "num_groups 3" "should count 3 groups"
    assert_contains "$output" "num_attributes 2" "should count 2 attributes"
}

test_h5dump_datasets () {
    local output
    output=$(run_mfe -r -s h5dump "$SAMPLES_DIR/h5dump/basic.txt")
    assert_contains "$output" "dataset1.datatype" "should extract dataset1 datatype"
    assert_contains "$output" "dataset1.dimensions 100,50,50" "should extract dataset1 dimensions"
    assert_contains "$output" "dataset2.dimensions 100,50" "should extract dataset2 dimensions"
    assert_contains "$output" "attribute1.name file_version" "should extract attribute name"
    assert_contains "$output" "attribute1.value" "should extract attribute value"
}

test_h5dump_not_json () {
    local tmpfile=$(mktemp)
    printf '{"name": "test"}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s h5dump "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "should not match JSON"
}

run_test "h5dump: detection" test_h5dump_detect
run_test "h5dump: extracted values" test_h5dump_values
run_test "h5dump: dataset details" test_h5dump_datasets
run_test "h5dump: not detected for JSON" test_h5dump_not_json

print_summary
