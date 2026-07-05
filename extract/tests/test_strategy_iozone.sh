#!/bin/bash
################################################################################
## Strategy Tests: iozone
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: iozone"
echo "========================================"

test_iozone_throughput () {
    local output
    output=$(run_mfe -r -s iozone "$SAMPLES_DIR/iozone/basic.txt")
    assert_contains "$output" "write 98765" "should extract write throughput"
    assert_contains "$output" "read 234567" "should extract read throughput"
    assert_contains "$output" "random_read 189012" "should extract random read"
}

test_iozone_metadata () {
    local output
    output=$(run_mfe -r -s iozone "$SAMPLES_DIR/iozone/basic.txt")
    assert_contains "$output" "version" "should extract version"
    assert_contains "$output" "file_size_kB 1024" "should extract file size"
}

test_iozone_not_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"name": "test", "value": 42}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s iozone "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "iozone should not apply to JSON"
}

run_test "iozone: throughput extraction" test_iozone_throughput
run_test "iozone: metadata extraction" test_iozone_metadata
run_test "iozone: not detected for JSON" test_iozone_not_json

print_summary
