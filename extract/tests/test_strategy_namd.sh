#!/bin/bash
################################################################################
## Strategy Tests: namd
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: namd"
echo "========================================"

test_namd_basic () {
    local output
    output=$(run_mfe -r -s namd "$SAMPLES_DIR/namd/basic.txt")
    assert_contains "$output" "num_atoms 24030" "should extract number of atoms"
    assert_contains "$output" "timestep 1" "should extract timestep"
    assert_contains "$output" "ts 5000" "should extract final timestep number"
    assert_contains "$output" "total -80237.0497" "should extract final total energy"
    assert_contains "$output" "temp 299.90" "should extract final temperature"
}

test_namd_energy_components () {
    local output
    output=$(run_mfe -r -s namd "$SAMPLES_DIR/namd/basic.txt")
    assert_contains "$output" "bond 241.0123" "should extract final bond energy"
    assert_contains "$output" "angle 573.2345" "should extract final angle energy"
    assert_contains "$output" "dihed 1241.1234" "should extract final dihedral energy"
    assert_contains "$output" "imprp 90.3456" "should extract final improper energy"
    assert_contains "$output" "elect -110005.3456" "should extract final electrostatic energy"
    assert_contains "$output" "vdw 10310.2345" "should extract final VDW energy"
}

test_namd_initial_values () {
    local output
    output=$(run_mfe -r -s namd "$SAMPLES_DIR/namd/basic.txt")
    assert_contains "$output" "initial_ts 0" "should extract initial timestep"
    assert_contains "$output" "initial_temp 298.56" "should extract initial temperature"
}

test_namd_pressure () {
    local output
    output=$(run_mfe -r -s namd "$SAMPLES_DIR/namd/basic.txt")
    assert_contains "$output" "pressure 0.8000" "should extract final pressure"
}

test_namd_wallclock () {
    local output
    output=$(run_mfe -r -s namd "$SAMPLES_DIR/namd/basic.txt")
    assert_contains "$output" "wallclock 52.340000" "should extract wall clock time"
}

test_namd_timing () {
    local output
    output=$(run_mfe -r -s namd "$SAMPLES_DIR/namd/basic.txt")
    assert_contains "$output" "timing_per_step 0.01002400" "should extract timing per step"
}

test_namd_energy_rows () {
    local output
    output=$(run_mfe -r -s namd "$SAMPLES_DIR/namd/basic.txt")
    assert_contains "$output" "num_energy_rows 6" "should count energy rows"
}

test_namd_detect () {
    local output
    output=$(run_mfe -d -s namd "$SAMPLES_DIR/namd/basic.txt" 2>&1)
    assert_contains "$output" "c95" "should detect NAMD output with high confidence"
}

test_namd_not_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"name": "test", "value": 42}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s namd "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "namd should not apply to JSON"
}

run_test "namd: basic extraction" test_namd_basic
run_test "namd: energy components" test_namd_energy_components
run_test "namd: initial values" test_namd_initial_values
run_test "namd: pressure" test_namd_pressure
run_test "namd: wallclock" test_namd_wallclock
run_test "namd: timing per step" test_namd_timing
run_test "namd: energy row count" test_namd_energy_rows
run_test "namd: detection confidence" test_namd_detect
run_test "namd: not detected for JSON" test_namd_not_json

print_summary
