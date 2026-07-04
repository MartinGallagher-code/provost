#!/bin/bash
################################################################################
## Strategy Tests: cp2k
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: cp2k"
echo "========================================"

test_cp2k_basic () {
    local output
    output=$(run_mfe -r -s cp2k "$SAMPLES_DIR/cp2k/basic.txt")
    assert_contains "$output" "total_energy -123.456789012345" "should extract total energy"
    assert_contains "$output" "num_atoms 96" "should extract number of atoms"
    assert_contains "$output" "num_electrons 256" "should extract number of electrons"
}

test_cp2k_scf () {
    local output
    output=$(run_mfe -r -s cp2k "$SAMPLES_DIR/cp2k/basic.txt")
    assert_contains "$output" "scf_cycles 7" "should extract SCF cycles"
    assert_contains "$output" "max_scf_gradient 0.00000012" "should extract max SCF gradient"
}

test_cp2k_timing () {
    local output
    output=$(run_mfe -r -s cp2k "$SAMPLES_DIR/cp2k/basic.txt")
    assert_contains "$output" "elapsed_time 330.000" "should extract elapsed time"
}

test_cp2k_method () {
    local output
    output=$(run_mfe -r -s cp2k "$SAMPLES_DIR/cp2k/basic.txt")
    assert_contains "$output" "method DFT" "should extract method"
    assert_contains "$output" "functional BLYP" "should extract functional"
}

test_cp2k_detect () {
    local output
    output=$(run_mfe -d -s cp2k "$SAMPLES_DIR/cp2k/basic.txt" 2>&1)
    assert_contains "$output" "c95" "should detect CP2K output with high confidence"
}

test_cp2k_not_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"name": "test", "value": 42}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s cp2k "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "cp2k should not apply to JSON"
}

run_test "cp2k: basic extraction" test_cp2k_basic
run_test "cp2k: SCF convergence" test_cp2k_scf
run_test "cp2k: timing" test_cp2k_timing
run_test "cp2k: method and functional" test_cp2k_method
run_test "cp2k: detection confidence" test_cp2k_detect
run_test "cp2k: not detected for JSON" test_cp2k_not_json

print_summary
