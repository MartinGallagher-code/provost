#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: nvidia-smi"
echo "========================================"

test_nvidia_smi_detect () {
    local output
    output=$(run_mfe -d -s nvidia-smi "$SAMPLES_DIR/nvidia-smi/basic.txt" 2>&1)
    assert_contains "$output" "applicable" "should detect nvidia-smi table output"
}

test_nvidia_smi_table_values () {
    local output
    output=$(run_mfe -r -s nvidia-smi "$SAMPLES_DIR/nvidia-smi/basic.txt")
    assert_contains "$output" "driver_version 535.129.03" "should extract driver version"
    assert_contains "$output" "cuda_version 12.2" "should extract CUDA version"
    assert_contains "$output" "gpu_index 0" "should extract first GPU index"
    assert_contains "$output" "name Tesla V100-SXM2" "should extract GPU name"
    assert_contains "$output" "temp_C 45" "should extract temperature"
    assert_contains "$output" "power_draw_W 35" "should extract power draw"
    assert_contains "$output" "power_cap_W 300" "should extract power cap"
    assert_contains "$output" "memory_used_MiB 0" "should extract memory used"
    assert_contains "$output" "memory_total_MiB 32768" "should extract memory total"
}

test_nvidia_smi_multi_gpu () {
    local output
    output=$(run_mfe -r -s nvidia-smi "$SAMPLES_DIR/nvidia-smi/basic.txt")
    assert_contains "$output" "gpu2.gpu_index 1" "should extract second GPU index"
    assert_contains "$output" "gpu2.temp_C 42" "should extract second GPU temp"
    assert_contains "$output" "gpu2.memory_used_MiB 1024" "should extract second GPU memory"
}

test_nvidia_smi_query_format () {
    local output
    output=$(run_mfe -r -s nvidia-smi "$SAMPLES_DIR/nvidia-smi/query.txt")
    assert_contains "$output" "name Tesla V100-SXM2-32GB" "should extract product name from -q"
    assert_contains "$output" "temp_C 45" "should extract temp from -q"
    assert_contains "$output" "power_draw_W 35.50" "should extract power draw from -q"
    assert_contains "$output" "power_cap_W 300.00" "should extract power cap from -q"
    assert_contains "$output" "memory_total_MiB 32768" "should extract memory total from -q"
    assert_contains "$output" "memory_used_MiB 512" "should extract memory used from -q"
    assert_contains "$output" "gpu_util_percent 10" "should extract GPU util from -q"
    assert_contains "$output" "mem_util_percent 5" "should extract mem util from -q"
}

test_nvidia_smi_not_json () {
    local tmpfile=$(mktemp)
    printf '{"name": "test"}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s nvidia-smi "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "should not match JSON"
}

run_test "nvidia-smi: detection" test_nvidia_smi_detect
run_test "nvidia-smi: table format values" test_nvidia_smi_table_values
run_test "nvidia-smi: multi-GPU" test_nvidia_smi_multi_gpu
run_test "nvidia-smi: query format" test_nvidia_smi_query_format
run_test "nvidia-smi: not detected for JSON" test_nvidia_smi_not_json

print_summary
