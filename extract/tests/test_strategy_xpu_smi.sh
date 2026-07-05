#!/bin/bash
################################################################################
## Strategy Tests: xpu-smi
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: xpu-smi"
echo "========================================"

test_detect () {
    local output
    output=$(run_mfe -d -s xpu-smi "$SAMPLES_DIR/xpu-smi/basic.txt" 2>&1)
    assert_contains "$output" "detected as applicable" "xpu-smi should detect xpu-smi output"
}

test_extract_device_info () {
    local output
    output=$(run_mfe -r -s xpu-smi "$SAMPLES_DIR/xpu-smi/basic.txt")
    assert_contains "$output" "dev1_device_name Intel Data Center GPU Max 1550" "should extract device 1 name"
    assert_contains "$output" "dev1_vendor Intel Corporation" "should extract device 1 vendor"
    assert_contains "$output" "dev1_driver_version 1.3.27642" "should extract device 1 driver version"
    assert_contains "$output" "dev1_pci_bdf 0000:4d:00.0" "should extract device 1 PCI BDF"
}

test_extract_device2_info () {
    local output
    output=$(run_mfe -r -s xpu-smi "$SAMPLES_DIR/xpu-smi/basic.txt")
    assert_contains "$output" "dev2_device_name Intel Data Center GPU Max 1550" "should extract device 2 name"
    assert_contains "$output" "dev2_pci_bdf 0000:9a:00.0" "should extract device 2 PCI BDF"
}

test_extract_stats () {
    local output
    output=$(run_mfe -r -s xpu-smi "$SAMPLES_DIR/xpu-smi/basic.txt")
    assert_contains "$output" "dev1_gpu_util_percent 85" "should extract device 1 GPU utilization"
    assert_contains "$output" "dev1_power_W 350" "should extract device 1 power"
    assert_contains "$output" "dev1_temp_C 62" "should extract device 1 temperature"
    assert_contains "$output" "dev1_memory_used_MiB 32768" "should extract device 1 memory used"
    assert_contains "$output" "dev1_memory_total_MiB 65536" "should extract device 1 memory total"
}

test_extract_device2_stats () {
    local output
    output=$(run_mfe -r -s xpu-smi "$SAMPLES_DIR/xpu-smi/basic.txt")
    assert_contains "$output" "dev2_gpu_util_percent 72" "should extract device 2 GPU utilization"
    assert_contains "$output" "dev2_power_W 310" "should extract device 2 power"
    assert_contains "$output" "dev2_temp_C 58" "should extract device 2 temperature"
}

test_device_count () {
    local output
    output=$(run_mfe -r -s xpu-smi "$SAMPLES_DIR/xpu-smi/basic.txt")
    assert_contains "$output" "device_count 2" "should report correct device count"
}

run_test "xpu-smi: detection" test_detect
run_test "xpu-smi: device 1 info" test_extract_device_info
run_test "xpu-smi: device 2 info" test_extract_device2_info
run_test "xpu-smi: device 1 stats" test_extract_stats
run_test "xpu-smi: device 2 stats" test_extract_device2_stats
run_test "xpu-smi: device count" test_device_count

print_summary
