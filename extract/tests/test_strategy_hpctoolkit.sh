#!/bin/bash
################################################################################
## Strategy Tests: hpctoolkit
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: hpctoolkit"
echo "========================================"

test_hpctoolkit_detect () {
    local output
    output=$(run_mfe -d -s hpctoolkit "$SAMPLES_DIR/hpctoolkit/basic.txt" 2>&1)
    assert_contains "$output" "applicable" "should detect hpctoolkit output"
}

test_hpctoolkit_values () {
    local output
    output=$(run_mfe -r -s hpctoolkit "$SAMPLES_DIR/hpctoolkit/basic.txt")
    assert_contains "$output" "application matrix_solver" "should extract application name"
    assert_contains "$output" "total_time 28.450" "should extract total time"
    assert_contains "$output" "func1_name compute_kernel" "should extract first function name"
    assert_contains "$output" "func1_inclusive_percent 45.2" "should extract first inclusive percent"
    assert_contains "$output" "func1_exclusive_percent 38.7" "should extract first exclusive percent"
    assert_contains "$output" "func2_name memory_alloc" "should extract second function name"
    assert_contains "$output" "func3_name io_operations" "should extract third function name"
    assert_contains "$output" "func4_name init_system" "should extract fourth function name"
}

test_hpctoolkit_not_json () {
    local tmpfile=$(mktemp)
    printf '{"name": "test"}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s hpctoolkit "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "should not match JSON"
}

run_test "hpctoolkit: detection" test_hpctoolkit_detect
run_test "hpctoolkit: specific values" test_hpctoolkit_values
run_test "hpctoolkit: not detected for JSON" test_hpctoolkit_not_json

print_summary
