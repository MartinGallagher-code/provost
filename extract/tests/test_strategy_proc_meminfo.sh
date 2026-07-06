#!/bin/bash
################################################################################
## Strategy Tests: proc-meminfo
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Proc Meminfo Strategy Tests"
echo "========================================"

test_detect () {
    local output
    output=$(run_mfe -d -s proc-meminfo "$SAMPLES_DIR/proc-meminfo/basic.txt" 2>&1)
    assert_contains "$output" "detected as applicable" "proc-meminfo should detect basic sample"

    local tmpfile
    tmpfile=$(mktemp)
    printf '{"name": "test", "value": 42}\n' > "$tmpfile"
    local output2
    output2=$(run_mfe -d -s proc-meminfo "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output2" "not applicable" "proc-meminfo should not apply to JSON"
}

test_extract () {
    local output
    output=$(run_mfe -r -s proc-meminfo "$SAMPLES_DIR/proc-meminfo/basic.txt")
    assert_contains "$output" "mem_total 16384000" "should extract MemTotal"
    assert_contains "$output" "mem_free 2048000" "should extract MemFree"
    assert_contains "$output" "mem_available 8192000" "should extract MemAvailable"
    assert_contains "$output" "buffers 512000" "should extract Buffers"
    assert_contains "$output" "cached 4096000" "should extract Cached"
    assert_contains "$output" "swap_cached 128000" "should extract SwapCached"
    assert_contains "$output" "swap_total 4096000" "should extract SwapTotal"
    assert_contains "$output" "swap_free 3072000" "should extract SwapFree"
    assert_contains "$output" "dirty 1024" "should extract Dirty"
    assert_contains "$output" "writeback 0" "should extract Writeback"
}

test_field_selection () {
    local output
    output=$(run_mfe -r -s proc-meminfo "$SAMPLES_DIR/proc-meminfo/minimal.txt")
    assert_contains "$output" "mem_total 1024000" "should extract MemTotal from minimal"
    assert_contains "$output" "mem_free 256000" "should extract MemFree from minimal"
    assert_contains "$output" "swap_total 512000" "should extract SwapTotal from minimal"
    assert_not_contains "$output" "dirty" "should not have Dirty in minimal"
    assert_not_contains "$output" "writeback" "should not have Writeback in minimal"
}

run_test "proc-meminfo: detection" test_detect
run_test "proc-meminfo: extraction" test_extract
run_test "proc-meminfo: field selection" test_field_selection

print_summary
