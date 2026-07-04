#!/bin/bash
################################################################################
## Strategy Tests: lshw
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: lshw"
echo "========================================"

test_detect () {
    local output
    output=$(run_mfe -d -s lshw "$SAMPLES_DIR/lshw/basic.txt" 2>&1)
    assert_contains "$output" "detected as applicable" "lshw should detect lshw output"
}

test_extract_cpu () {
    local output
    output=$(run_mfe -r -s lshw "$SAMPLES_DIR/lshw/basic.txt")
    assert_contains "$output" "cpu1_description CPU" "should extract CPU description"
    assert_contains "$output" "cpu1_product Intel(R) Xeon(R) Gold 6248 CPU @ 2.50GHz" "should extract CPU product"
    assert_contains "$output" "cpu1_vendor Intel Corp." "should extract CPU vendor"
}

test_extract_memory () {
    local output
    output=$(run_mfe -r -s lshw "$SAMPLES_DIR/lshw/basic.txt")
    assert_contains "$output" "memory1_description System Memory" "should extract memory description"
    assert_contains "$output" "memory1_size 192GiB" "should extract memory size"
}

test_extract_network () {
    local output
    output=$(run_mfe -r -s lshw "$SAMPLES_DIR/lshw/basic.txt")
    assert_contains "$output" "network1_description Ethernet interface" "should extract network description"
    assert_contains "$output" "network1_product Ethernet Controller 10G X550T" "should extract network product"
    assert_contains "$output" "network1_vendor Intel Corporation" "should extract network vendor"
}

test_extract_disk () {
    local output
    output=$(run_mfe -r -s lshw "$SAMPLES_DIR/lshw/basic.txt")
    assert_contains "$output" "disk1_description ATA Disk" "should extract disk description"
    assert_contains "$output" "disk1_product SAMSUNG MZ7LH1T9" "should extract disk product"
    assert_contains "$output" "disk1_size 1788GiB" "should extract disk size"
}

test_extract_display () {
    local output
    output=$(run_mfe -r -s lshw "$SAMPLES_DIR/lshw/basic.txt")
    assert_contains "$output" "display1_description VGA compatible controller" "should extract display description"
    assert_contains "$output" "display1_vendor Matrox Electronics Systems Ltd." "should extract display vendor"
}

run_test "lshw: detection" test_detect
run_test "lshw: cpu extraction" test_extract_cpu
run_test "lshw: memory extraction" test_extract_memory
run_test "lshw: network extraction" test_extract_network
run_test "lshw: disk extraction" test_extract_disk
run_test "lshw: display extraction" test_extract_display

print_summary
