#!/bin/bash
################################################################################
## Strategy Tests: amber
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: amber"
echo "========================================"

test_amber_basic () {
    local output
    output=$(run_mfe -r -s amber "$SAMPLES_DIR/amber/basic.txt")
    assert_contains "$output" "num_atoms 24030" "should extract number of atoms"
    assert_contains "$output" "nstep 3000" "should extract final NSTEP"
    assert_contains "$output" "temp 299.87" "should extract final temperature"
    assert_contains "$output" "press 3.4" "should extract final pressure"
    assert_contains "$output" "etot -75410.2345" "should extract final total energy"
    assert_contains "$output" "ektot 17310.6543" "should extract final kinetic energy"
    assert_contains "$output" "eptot -92720.8888" "should extract final potential energy"
}

test_amber_initial_values () {
    local output
    output=$(run_mfe -r -s amber "$SAMPLES_DIR/amber/basic.txt")
    assert_contains "$output" "initial_nstep 1000" "should extract initial NSTEP"
    assert_contains "$output" "initial_temp 298.56" "should extract initial temperature"
}

test_amber_density_volume () {
    local output
    output=$(run_mfe -r -s amber "$SAMPLES_DIR/amber/basic.txt")
    assert_contains "$output" "density 1.0134" "should extract density"
    assert_contains "$output" "volume 234345.6789" "should extract volume"
}

test_amber_wallclock () {
    local output
    output=$(run_mfe -r -s amber "$SAMPLES_DIR/amber/basic.txt")
    assert_contains "$output" "wallclock 125.00" "should extract wall clock time"
}

test_amber_thermo_blocks () {
    local output
    output=$(run_mfe -r -s amber "$SAMPLES_DIR/amber/basic.txt")
    assert_contains "$output" "num_thermo_blocks 3" "should count thermo blocks"
}

test_amber_detect () {
    local output
    output=$(run_mfe -d -s amber "$SAMPLES_DIR/amber/basic.txt" 2>&1)
    assert_contains "$output" "c95" "should detect AMBER output with high confidence"
}

test_amber_not_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"name": "test", "value": 42}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s amber "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "amber should not apply to JSON"
}

run_test "amber: basic extraction" test_amber_basic
run_test "amber: initial values" test_amber_initial_values
run_test "amber: density and volume" test_amber_density_volume
run_test "amber: wallclock" test_amber_wallclock
run_test "amber: thermo block count" test_amber_thermo_blocks
run_test "amber: detection confidence" test_amber_detect
run_test "amber: not detected for JSON" test_amber_not_json

print_summary
