#!/bin/bash
################################################################################
## Strategy Tests: lammps
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: lammps"
echo "========================================"

test_lammps_detect () {
    local output
    output=$(run_mfe -d -s lammps "$SAMPLES_DIR/lammps/basic.txt" 2>&1)
    assert_contains "$output" "applicable" "should detect LAMMPS output"
}

test_lammps_values () {
    local output
    output=$(run_mfe -r -s lammps "$SAMPLES_DIR/lammps/basic.txt")
    assert_contains "$output" "lammps_version 2 Aug 2023 - Update 2" "should extract LAMMPS version"
    assert_contains "$output" "initial_step 0" "should extract initial step"
    assert_contains "$output" "final_step 1000" "should extract final step"
}

test_lammps_thermo () {
    local output
    output=$(run_mfe -r -s lammps "$SAMPLES_DIR/lammps/basic.txt")
    assert_contains "$output" "initial_step 0" "should extract initial step"
    assert_contains "$output" "initial_temp 1.44" "should extract initial temperature"
    assert_contains "$output" "final_step 1000" "should extract final step"
    assert_contains "$output" "final_temp 0.7312" "should extract final temperature"
    assert_contains "$output" "num_thermo_rows 5" "should count thermo rows"
    assert_contains "$output" "total_energy -6.7674" "should extract total energy"
    assert_contains "$output" "potential_energy -7.8642" "should extract potential energy"
}

test_lammps_performance () {
    local output
    output=$(run_mfe -r -s lammps "$SAMPLES_DIR/lammps/basic.txt")
    assert_contains "$output" "tau_per_day 121.025" "should extract tau/day"
    assert_contains "$output" "timesteps_per_s 280.315" "should extract timesteps/s"
    assert_contains "$output" "total_wall_time 0:00:04" "should extract wall time"
}

test_lammps_not_json () {
    local tmpfile=$(mktemp)
    printf '{"name": "test"}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s lammps "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "should not match JSON"
}

run_test "lammps: detection" test_lammps_detect
run_test "lammps: extracted values" test_lammps_values
run_test "lammps: thermo data" test_lammps_thermo
run_test "lammps: performance" test_lammps_performance
run_test "lammps: not detected for JSON" test_lammps_not_json

print_summary
