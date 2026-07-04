#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: rocm-smi"
echo "========================================"

test_rocm_smi_detect () {
    local output
    output=$(run_mfe -d -s rocm-smi "$SAMPLES_DIR/rocm-smi/basic.txt" 2>&1)
    assert_contains "$output" "applicable" "should detect rocm-smi output"
}

test_rocm_smi_values () {
    local output
    output=$(run_mfe -r -s rocm-smi "$SAMPLES_DIR/rocm-smi/basic.txt")
    assert_contains "$output" "gpu_index 0" "should extract first GPU index"
    assert_contains "$output" "temp_edge_C 45.0" "should extract temperature"
    assert_contains "$output" "power_W 35.0" "should extract power"
    assert_contains "$output" "sclk_MHz 1500" "should extract SCLK"
    assert_contains "$output" "mclk_MHz 945" "should extract MCLK"
    assert_contains "$output" "fan_percent 0" "should extract fan"
    assert_contains "$output" "memory_use_percent 10" "should extract VRAM%"
    assert_contains "$output" "gpu_use_percent 25" "should extract GPU%"
}

test_rocm_smi_multi_gpu () {
    local output
    output=$(run_mfe -r -s rocm-smi "$SAMPLES_DIR/rocm-smi/basic.txt")
    assert_contains "$output" "gpu2.gpu_index 1" "should extract second GPU index"
    assert_contains "$output" "gpu2.temp_edge_C 42.0" "should extract second GPU temp"
    assert_contains "$output" "gpu2.power_W 30.0" "should extract second GPU power"
}

test_rocm_smi_not_json () {
    local tmpfile=$(mktemp)
    printf '{"name": "test"}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s rocm-smi "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "should not match JSON"
}

run_test "rocm-smi: detection" test_rocm_smi_detect
run_test "rocm-smi: specific values" test_rocm_smi_values
run_test "rocm-smi: multi-GPU" test_rocm_smi_multi_gpu
run_test "rocm-smi: not detected for JSON" test_rocm_smi_not_json

print_summary
