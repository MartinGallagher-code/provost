#!/bin/bash
################################################################################
## Strategy Tests: ncdump
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: ncdump"
echo "========================================"

test_ncdump_detect () {
    local output
    output=$(run_mfe -d -s ncdump "$SAMPLES_DIR/ncdump/basic.txt" 2>&1)
    assert_contains "$output" "applicable" "should detect ncdump output"
}

test_ncdump_values () {
    local output
    output=$(run_mfe -r -s ncdump "$SAMPLES_DIR/ncdump/basic.txt")
    assert_contains "$output" "filename climate_data" "should extract filename"
    assert_contains "$output" "num_dimensions 3" "should count 3 dimensions"
    assert_contains "$output" "num_variables 5" "should count 5 variables"
    assert_contains "$output" "num_global_attributes 4" "should count 4 global attributes"
}

test_ncdump_dimensions () {
    local output
    output=$(run_mfe -r -s ncdump "$SAMPLES_DIR/ncdump/basic.txt")
    assert_contains "$output" "dimension.time UNLIMITED" "should extract time dimension"
    assert_contains "$output" "dimension.lat 180" "should extract lat dimension"
    assert_contains "$output" "dimension.lon 360" "should extract lon dimension"
    assert_contains "$output" "dimension_names time,lat,lon" "should list dimension names"
}

test_ncdump_variables () {
    local output
    output=$(run_mfe -r -s ncdump "$SAMPLES_DIR/ncdump/basic.txt")
    assert_contains "$output" "variable.temperature.type float" "should extract variable type"
    assert_contains "$output" "variable.temperature.dimensions time,lat,lon" "should extract variable dims"
    assert_contains "$output" "variable.temperature.units K" "should extract variable attribute"
    assert_contains "$output" "variable_names temperature,precipitation,time,lat,lon" "should list variable names"
}

test_ncdump_globals () {
    local output
    output=$(run_mfe -r -s ncdump "$SAMPLES_DIR/ncdump/basic.txt")
    assert_contains "$output" "global.title Global Climate Dataset 2024" "should extract global title"
    assert_contains "$output" "global.Conventions CF-1.6" "should extract conventions"
}

test_ncdump_not_json () {
    local tmpfile=$(mktemp)
    printf '{"name": "test"}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s ncdump "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "should not match JSON"
}

run_test "ncdump: detection" test_ncdump_detect
run_test "ncdump: extracted values" test_ncdump_values
run_test "ncdump: dimensions" test_ncdump_dimensions
run_test "ncdump: variables" test_ncdump_variables
run_test "ncdump: global attributes" test_ncdump_globals
run_test "ncdump: not detected for JSON" test_ncdump_not_json

print_summary
