#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: cuda-devicequery"
echo "========================================"

test_cuda_devicequery_detect () {
    local output
    output=$(run_mfe -d -s cuda-devicequery "$SAMPLES_DIR/cuda-devicequery/basic.txt" 2>&1)
    assert_contains "$output" "applicable" "should detect deviceQuery output"
}

test_cuda_devicequery_values () {
    local output
    output=$(run_mfe -r -s cuda-devicequery "$SAMPLES_DIR/cuda-devicequery/basic.txt")
    assert_contains "$output" "device_name Tesla V100-SXM2-32GB" "should extract device name"
    assert_contains "$output" "compute_capability 7.0" "should extract compute capability"
    assert_contains "$output" "total_global_memory 32510 MBytes" "should extract global memory"
    assert_contains "$output" "multiprocessors 80" "should extract multiprocessors"
    assert_contains "$output" "cuda_cores 5120" "should extract CUDA cores"
    assert_contains "$output" "gpu_clock_MHz 1530" "should extract GPU clock"
    assert_contains "$output" "memory_clock_MHz 877" "should extract memory clock"
    assert_contains "$output" "memory_bus_width 4096-bit" "should extract bus width"
    assert_contains "$output" "l2_cache_size 6291456 bytes" "should extract L2 cache"
    assert_contains "$output" "cuda_driver_version 12.2" "should extract driver version"
    assert_contains "$output" "cuda_runtime_version 12.1" "should extract runtime version"
}

test_cuda_devicequery_not_json () {
    local tmpfile=$(mktemp)
    printf '{"name": "test"}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s cuda-devicequery "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "should not match JSON"
}

run_test "cuda-devicequery: detection" test_cuda_devicequery_detect
run_test "cuda-devicequery: specific values" test_cuda_devicequery_values
run_test "cuda-devicequery: not detected for JSON" test_cuda_devicequery_not_json

print_summary
