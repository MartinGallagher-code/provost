#!/bin/bash
################################################################################
## Strategy Tests: qe
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: qe"
echo "========================================"

test_qe_basic () {
    local output
    output=$(run_mfe -r -s qe "$SAMPLES_DIR/qe/basic.txt")
    assert_contains "$output" "total_energy_Ry -31.80883014" "should extract total energy in Ry"
    assert_contains "$output" "num_atoms 2" "should extract number of atoms"
    assert_contains "$output" "num_electrons 8.00" "should extract number of electrons"
}

test_qe_cutoffs () {
    local output
    output=$(run_mfe -r -s qe "$SAMPLES_DIR/qe/basic.txt")
    assert_contains "$output" "ecutwfc 60.0000" "should extract wavefunction cutoff"
    assert_contains "$output" "ecutrho 480.0000" "should extract charge density cutoff"
}

test_qe_kpoints () {
    local output
    output=$(run_mfe -r -s qe "$SAMPLES_DIR/qe/basic.txt")
    assert_contains "$output" "k_points 10" "should extract number of k-points"
}

test_qe_forces_pressure () {
    local output
    output=$(run_mfe -r -s qe "$SAMPLES_DIR/qe/basic.txt")
    assert_contains "$output" "total_force 0.000000" "should extract total force"
    assert_contains "$output" "pressure_kbar -3.45" "should extract pressure in kbar"
}

test_qe_convergence () {
    local output
    output=$(run_mfe -r -s qe "$SAMPLES_DIR/qe/basic.txt")
    assert_contains "$output" "convergence_achieved yes" "should detect convergence"
}

test_qe_timing () {
    local output
    output=$(run_mfe -r -s qe "$SAMPLES_DIR/qe/basic.txt")
    assert_contains "$output" "elapsed_time 1.48" "should extract elapsed wall time"
}

test_qe_detect () {
    local output
    output=$(run_mfe -d -s qe "$SAMPLES_DIR/qe/basic.txt" 2>&1)
    assert_contains "$output" "c95" "should detect QE output with high confidence"
}

test_qe_not_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"name": "test", "value": 42}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s qe "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "qe should not apply to JSON"
}

run_test "qe: basic extraction" test_qe_basic
run_test "qe: energy cutoffs" test_qe_cutoffs
run_test "qe: k-points" test_qe_kpoints
run_test "qe: forces and pressure" test_qe_forces_pressure
run_test "qe: convergence detection" test_qe_convergence
run_test "qe: timing" test_qe_timing
run_test "qe: detection confidence" test_qe_detect
run_test "qe: not detected for JSON" test_qe_not_json

print_summary
