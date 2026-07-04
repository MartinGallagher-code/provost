#!/bin/bash
################################################################################
## Strategy Tests: dmidecode
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: dmidecode"
echo "========================================"

test_dmidecode_detect () {
    local output
    output=$(run_mfe -d -s dmidecode "$SAMPLES_DIR/dmidecode/basic.txt" 2>&1)
    assert_contains "$output" "applicable" "should detect dmidecode output"
}

test_dmidecode_bios () {
    local output
    output=$(run_mfe -r -s dmidecode "$SAMPLES_DIR/dmidecode/basic.txt")
    assert_contains "$output" "bios_vendor Dell Inc." "should extract BIOS vendor"
    assert_contains "$output" "bios_version 2.12.2" "should extract BIOS version"
    assert_contains "$output" "bios_release_date 01/15/2024" "should extract BIOS release date"
}

test_dmidecode_system () {
    local output
    output=$(run_mfe -r -s dmidecode "$SAMPLES_DIR/dmidecode/basic.txt")
    assert_contains "$output" "system_manufacturer Dell Inc." "should extract system manufacturer"
    assert_contains "$output" "system_product PowerEdge R750" "should extract system product"
    assert_contains "$output" "system_serial ABC1234XYZ" "should extract system serial"
}

test_dmidecode_processor () {
    local output
    output=$(run_mfe -r -s dmidecode "$SAMPLES_DIR/dmidecode/basic.txt")
    assert_contains "$output" "processor.type Central Processor" "should extract processor type"
    assert_contains "$output" "processor.version Intel(R) Xeon(R) Gold 6326 CPU @ 2.90GHz" "should extract processor version"
    assert_contains "$output" "processor.max_speed 4000 MHz" "should extract max speed"
    assert_contains "$output" "processor.current_speed 2900 MHz" "should extract current speed"
    assert_contains "$output" "processor.core_count 16" "should extract core count"
    assert_contains "$output" "processor.thread_count 32" "should extract thread count"
}

test_dmidecode_memory () {
    local output
    output=$(run_mfe -r -s dmidecode "$SAMPLES_DIR/dmidecode/basic.txt")
    assert_contains "$output" "memory1.size 32 GB" "should extract memory1 size"
    assert_contains "$output" "memory1.type DDR4" "should extract memory1 type"
    assert_contains "$output" "memory1.speed 3200 MT/s" "should extract memory1 speed"
    assert_contains "$output" "memory1.manufacturer Samsung" "should extract memory1 manufacturer"
    assert_contains "$output" "memory1.locator DIMM_A0" "should extract memory1 locator"
    assert_contains "$output" "memory2.locator DIMM_A1" "should extract memory2 locator"
    assert_contains "$output" "memory_device_count 2" "should count 2 memory devices"
    assert_contains "$output" "total_memory_MB 65536" "should calculate total memory"
    assert_contains "$output" "processor_count 1" "should count 1 processor"
}

test_dmidecode_not_json () {
    local tmpfile=$(mktemp)
    printf '{"name": "test"}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s dmidecode "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "should not match JSON"
}

run_test "dmidecode: detection" test_dmidecode_detect
run_test "dmidecode: BIOS values" test_dmidecode_bios
run_test "dmidecode: system values" test_dmidecode_system
run_test "dmidecode: processor values" test_dmidecode_processor
run_test "dmidecode: memory values" test_dmidecode_memory
run_test "dmidecode: not detected for JSON" test_dmidecode_not_json

print_summary
