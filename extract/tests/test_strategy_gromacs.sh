#!/bin/bash
################################################################################
## Strategy Tests: gromacs
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: gromacs"
echo "========================================"

test_gromacs_detect () {
    local output
    output=$(run_mfe -d -s gromacs "$SAMPLES_DIR/gromacs/basic.txt" 2>&1)
    assert_contains "$output" "applicable" "should detect GROMACS output"
}

test_gromacs_values () {
    local output
    output=$(run_mfe -r -s gromacs "$SAMPLES_DIR/gromacs/basic.txt")
    assert_contains "$output" "format log" "should identify as log format"
    assert_contains "$output" "gromacs_version 2023.3" "should extract GROMACS version"
    assert_contains "$output" "performance_ns_per_day 163.280" "should extract performance"
}

test_gromacs_timing () {
    local output
    output=$(run_mfe -r -s gromacs "$SAMPLES_DIR/gromacs/basic.txt")
    assert_contains "$output" "core_time 8467.230" "should extract core time"
    assert_contains "$output" "wall_time 1058.404" "should extract wall time"
    assert_contains "$output" "num_atoms 24576" "should extract atom count"
}

test_gromacs_not_json () {
    local tmpfile=$(mktemp)
    printf '{"name": "test"}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s gromacs "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "should not match JSON"
}

run_test "gromacs: detection" test_gromacs_detect
run_test "gromacs: extracted values" test_gromacs_values
run_test "gromacs: timing data" test_gromacs_timing
run_test "gromacs: not detected for JSON" test_gromacs_not_json

print_summary
