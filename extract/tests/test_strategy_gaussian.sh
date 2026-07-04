#!/bin/bash
################################################################################
## Strategy Tests: gaussian
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: gaussian"
echo "========================================"

test_gaussian_detect () {
    local output
    output=$(run_mfe -d -s gaussian "$SAMPLES_DIR/gaussian/basic.txt" 2>&1)
    assert_contains "$output" "applicable" "should detect Gaussian output"
}

test_gaussian_values () {
    local output
    output=$(run_mfe -r -s gaussian "$SAMPLES_DIR/gaussian/basic.txt")
    assert_contains "$output" "gaussian_version 16" "should extract Gaussian version"
    assert_contains "$output" "revision C.01" "should extract revision"
    assert_contains "$output" "method B3LYP" "should extract method"
    assert_contains "$output" "basis_set 6-31G(d)" "should extract basis set"
    assert_contains "$output" "num_atoms 3" "should extract atom count"
}

test_gaussian_energy () {
    local output
    output=$(run_mfe -r -s gaussian "$SAMPLES_DIR/gaussian/basic.txt")
    assert_contains "$output" "scf_energy -76.4089661230" "should extract SCF energy"
    assert_contains "$output" "zero_point_energy 0.021428" "should extract ZPE"
    assert_contains "$output" "thermal_energy 0.024103" "should extract thermal energy"
}

test_gaussian_molecular () {
    local output
    output=$(run_mfe -r -s gaussian "$SAMPLES_DIR/gaussian/basic.txt")
    assert_contains "$output" "charge 0" "should extract charge"
    assert_contains "$output" "multiplicity 1" "should extract multiplicity"
    assert_contains "$output" "num_basis_functions 25" "should extract basis function count"
    assert_contains "$output" "normal_termination yes" "should detect normal termination"
}

test_gaussian_not_json () {
    local tmpfile=$(mktemp)
    printf '{"name": "test"}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s gaussian "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "should not match JSON"
}

run_test "gaussian: detection" test_gaussian_detect
run_test "gaussian: extracted values" test_gaussian_values
run_test "gaussian: energy data" test_gaussian_energy
run_test "gaussian: molecular properties" test_gaussian_molecular
run_test "gaussian: not detected for JSON" test_gaussian_not_json

print_summary
