#!/bin/bash
################################################################################
## Strategy Tests: iostat
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: iostat"
echo "========================================"

test_iostat_basic () {
    local output
    output=$(run_mfe -r -s iostat "$SAMPLES_DIR/iostat/basic.txt")
    assert_contains "$output" "disk0.KB_per_t" "should extract disk0 KB/t"
    assert_contains "$output" "disk0.tps" "should extract disk0 tps"
    assert_contains "$output" "disk0.MB_per_s" "should extract disk0 MB/s"
    assert_contains "$output" "24.00" "should extract disk0 KB/t value"
    assert_contains "$output" "1.05" "should extract disk0 MB/s value"
}

test_iostat_multiple_devices () {
    local output
    output=$(run_mfe -r -s iostat "$SAMPLES_DIR/iostat/basic.txt")
    assert_contains "$output" "disk1.KB_per_t" "should extract disk1 KB/t"
    assert_contains "$output" "disk1.tps" "should extract disk1 tps"
    assert_contains "$output" "disk1.MB_per_s" "should extract disk1 MB/s"
    assert_contains "$output" "32.00" "should extract disk1 KB/t value"
    assert_contains "$output" "0.38" "should extract disk1 MB/s value"
}

test_iostat_not_applicable_for_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"key": "value", "count": 42}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s iostat "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "iostat should not apply to JSON"
}

run_test "iostat: basic extraction" test_iostat_basic
run_test "iostat: multiple devices" test_iostat_multiple_devices
run_test "iostat: not applicable for JSON" test_iostat_not_applicable_for_json

print_summary
