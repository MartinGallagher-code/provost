#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: cuda-bandwidthtest"
echo "========================================"

test_cuda_bw_basic () {
    local output
    output=$(run_mfe -r -s cuda-bandwidthtest "$SAMPLES_DIR/cuda-bandwidthtest/basic.txt")
    assert_contains "$output" "host_to_device_bandwidth_GB_per_s" "should extract H2D bandwidth"
    assert_contains "$output" "device_to_host_bandwidth_GB_per_s" "should extract D2H bandwidth"
    assert_contains "$output" "device_to_device_bandwidth_GB_per_s" "should extract D2D bandwidth"
}

test_cuda_bw_values () {
    local output
    output=$(run_mfe -r -s cuda-bandwidthtest "$SAMPLES_DIR/cuda-bandwidthtest/basic.txt")
    assert_contains "$output" "host_to_device_bandwidth_GB_per_s 12.4" "should extract correct H2D"
    assert_contains "$output" "device_to_device_bandwidth_GB_per_s 732.5" "should extract correct D2D"
    assert_contains "$output" "device_name Tesla_V100-SXM2-32GB" "should extract device name"
    assert_contains "$output" "result PASS" "should extract result"
}

test_cuda_bw_not_json () {
    local tmpfile=$(mktemp)
    printf '{"name": "test"}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s cuda-bandwidthtest "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "should not match JSON"
}

run_test "cuda-bandwidthtest: basic extraction" test_cuda_bw_basic
run_test "cuda-bandwidthtest: specific values" test_cuda_bw_values
run_test "cuda-bandwidthtest: not detected for JSON" test_cuda_bw_not_json

print_summary
