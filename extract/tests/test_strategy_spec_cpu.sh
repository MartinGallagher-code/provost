#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: spec-cpu"
echo "========================================"

test_spec_cpu_basic () {
    local output
    output=$(run_mfe -r -s spec-cpu "$SAMPLES_DIR/spec-cpu/basic.txt")
    assert_contains "$output" "specrate_int_base" "should extract base rate"
    assert_contains "$output" "specrate_int_peak" "should extract peak rate"
    assert_contains "$output" "bench1.name" "should extract first benchmark"
}

test_spec_cpu_values () {
    local output
    output=$(run_mfe -r -s spec-cpu "$SAMPLES_DIR/spec-cpu/basic.txt")
    assert_contains "$output" "specrate_int_base 867" "should extract correct base rate"
    assert_contains "$output" "specrate_int_peak 923" "should extract correct peak rate"
    assert_contains "$output" "bench1.name 500.perlbench_r" "should extract first bench name"
    assert_contains "$output" "bench1.base_rate 678" "should extract first bench base rate"
    assert_contains "$output" "base_copies 128" "should extract base copies"
}

test_spec_cpu_not_json () {
    local tmpfile=$(mktemp)
    printf '{"name": "test"}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s spec-cpu "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "should not match JSON"
}

run_test "spec-cpu: basic extraction" test_spec_cpu_basic
run_test "spec-cpu: specific values" test_spec_cpu_values
run_test "spec-cpu: not detected for JSON" test_spec_cpu_not_json

print_summary
