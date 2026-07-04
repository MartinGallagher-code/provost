#!/bin/bash
################################################################################
## Strategy Tests: hdparm
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: hdparm"
echo "========================================"

test_hdparm_basic () {
    local output
    output=$(run_mfe -r -s hdparm "$SAMPLES_DIR/hdparm/basic.txt")
    assert_contains "$output" "device sda" "should extract device name"
    assert_contains "$output" "sda.cached_reads_MB_per_s 8234.56" "should extract cached reads speed"
    assert_contains "$output" "sda.buffered_reads_MB_per_s 151.50" "should extract buffered reads speed"
}

test_hdparm_multi_device () {
    local output
    output=$(run_mfe -r -s hdparm "$SAMPLES_DIR/hdparm/multi-device.txt")
    assert_contains "$output" "sda.cached_reads_MB_per_s 8234.56" "should extract sda cached reads"
    assert_contains "$output" "sdb.cached_reads_MB_per_s 7608.12" "should extract sdb cached reads"
    assert_contains "$output" "sda.buffered_reads_MB_per_s 151.50" "should extract sda buffered reads"
    assert_contains "$output" "sdb.buffered_reads_MB_per_s 103.31" "should extract sdb buffered reads"
}

test_hdparm_not_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"name": "test", "value": 42}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s hdparm "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "hdparm should not apply to JSON"
}

run_test "hdparm: basic extraction" test_hdparm_basic
run_test "hdparm: multi-device extraction" test_hdparm_multi_device
run_test "hdparm: not detected for JSON" test_hdparm_not_json

print_summary
