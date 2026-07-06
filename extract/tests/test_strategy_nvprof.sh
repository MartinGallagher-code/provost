#!/bin/bash
################################################################################
## Strategy Tests: nvprof
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: nvprof"
echo "========================================"

test_nvprof_detect () {
    local output
    output=$(run_mfe -d -s nvprof "$SAMPLES_DIR/nvprof/basic.txt" 2>&1)
    assert_contains "$output" "applicable" "should detect nvprof output"
}

test_nvprof_values () {
    local output
    output=$(run_mfe -r -s nvprof "$SAMPLES_DIR/nvprof/basic.txt")
    assert_contains "$output" "kernel1_name matrix_multiply_kernel" "should extract first kernel name"
    assert_contains "$output" "kernel1_time_pct 52.34" "should extract first kernel time percent"
    assert_contains "$output" "kernel1_calls 100" "should extract first kernel calls"
    assert_contains "$output" "kernel2_name reduce_kernel" "should extract second kernel name"
    assert_contains "$output" "kernel2_time_pct 31.22" "should extract second kernel time percent"
    assert_contains "$output" "api1_name cudaMemcpy" "should extract first API call name"
    assert_contains "$output" "api1_time_pct 45.67" "should extract first API call time percent"
    assert_contains "$output" "api2_name cudaLaunchKernel" "should extract second API call name"
    assert_contains "$output" "api3_name cudaMalloc" "should extract third API call name"
    assert_contains "$output" "api_call_count 3" "should extract API call count"
}

test_nvprof_not_json () {
    local tmpfile=$(mktemp)
    printf '{"name": "test"}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s nvprof "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "should not match JSON"
}

run_test "nvprof: detection" test_nvprof_detect
run_test "nvprof: specific values" test_nvprof_values
run_test "nvprof: not detected for JSON" test_nvprof_not_json

print_summary
