#!/bin/bash
################################################################################
## Strategy Tests: vtk
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: vtk"
echo "========================================"

test_vtk_detect () {
    local output
    output=$(run_mfe -d -s vtk "$SAMPLES_DIR/vtk/basic.txt" 2>&1)
    assert_contains "$output" "applicable" "should detect VTK output"
}

test_vtk_values () {
    local output
    output=$(run_mfe -r -s vtk "$SAMPLES_DIR/vtk/basic.txt")
    assert_contains "$output" "version 3.0" "should extract version"
    assert_contains "$output" "title Thermal Simulation Output" "should extract title"
    assert_contains "$output" "format ASCII" "should extract format"
    assert_contains "$output" "dataset_type STRUCTURED_POINTS" "should extract dataset type"
}

test_vtk_geometry () {
    local output
    output=$(run_mfe -r -s vtk "$SAMPLES_DIR/vtk/basic.txt")
    assert_contains "$output" "dimensions 64x64x64" "should extract dimensions"
    assert_contains "$output" "origin 0.0,0.0,0.0" "should extract origin"
    assert_contains "$output" "spacing 0.5,0.5,0.5" "should extract spacing"
    assert_contains "$output" "num_point_data 262144" "should extract point data count"
}

test_vtk_data_arrays () {
    local output
    output=$(run_mfe -r -s vtk "$SAMPLES_DIR/vtk/basic.txt")
    assert_contains "$output" "data_array1.name temperature" "should extract scalar name"
    assert_contains "$output" "data_array1.type scalars" "should identify as scalars"
    assert_contains "$output" "data_array2.name velocity" "should extract vector name"
    assert_contains "$output" "data_array2.type vectors" "should identify as vectors"
    assert_contains "$output" "num_data_arrays 2" "should count 2 data arrays"
}

test_vtk_not_json () {
    local tmpfile=$(mktemp)
    printf '{"name": "test"}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s vtk "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "should not match JSON"
}

run_test "vtk: detection" test_vtk_detect
run_test "vtk: basic values" test_vtk_values
run_test "vtk: geometry" test_vtk_geometry
run_test "vtk: data arrays" test_vtk_data_arrays
run_test "vtk: not detected for JSON" test_vtk_not_json

print_summary
