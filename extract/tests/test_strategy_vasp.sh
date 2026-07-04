#!/bin/bash
################################################################################
## Strategy Tests: vasp
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: vasp"
echo "========================================"

test_vasp_detect () {
    local output
    output=$(run_mfe -d -s vasp "$SAMPLES_DIR/vasp/basic.txt" 2>&1)
    assert_contains "$output" "applicable" "should detect VASP output"
}

test_vasp_values () {
    local output
    output=$(run_mfe -r -s vasp "$SAMPLES_DIR/vasp/basic.txt")
    assert_contains "$output" "vasp_version 6.3.2" "should extract VASP version"
    assert_contains "$output" "encut 400.00" "should extract ENCUT"
    assert_contains "$output" "ediff 0.10E-05" "should extract EDIFF"
    assert_contains "$output" "num_ions 8" "should extract ion count"
    assert_contains "$output" "num_kpoints 10" "should extract k-point count"
    assert_contains "$output" "num_bands 24" "should extract band count"
}

test_vasp_energy () {
    local output
    output=$(run_mfe -r -s vasp "$SAMPLES_DIR/vasp/basic.txt")
    assert_contains "$output" "total_energy -43.39182456" "should extract final total energy"
    assert_contains "$output" "fermi_energy 5.8321" "should extract Fermi energy"
    assert_contains "$output" "num_scf_steps 3" "should count SCF steps"
    assert_contains "$output" "elapsed_time 234.567" "should extract elapsed time"
}

test_vasp_settings () {
    local output
    output=$(run_mfe -r -s vasp "$SAMPLES_DIR/vasp/basic.txt")
    assert_contains "$output" "ispin 1" "should extract ISPIN"
    assert_contains "$output" "ismear 0" "should extract ISMEAR"
    assert_contains "$output" "potcar PAW_PBE Si 05Jan2001" "should extract POTCAR"
}

test_vasp_not_json () {
    local tmpfile=$(mktemp)
    printf '{"name": "test"}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s vasp "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "should not match JSON"
}

run_test "vasp: detection" test_vasp_detect
run_test "vasp: extracted values" test_vasp_values
run_test "vasp: energy data" test_vasp_energy
run_test "vasp: settings" test_vasp_settings
run_test "vasp: not detected for JSON" test_vasp_not_json

print_summary
