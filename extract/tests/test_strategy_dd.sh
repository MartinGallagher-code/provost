#!/bin/bash
################################################################################
## Strategy Tests: dd
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: dd"
echo "========================================"

test_dd_basic_linux () {
    local output
    output=$(run_mfe -r -s dd "$SAMPLES_DIR/dd/basic.txt")
    assert_contains "$output" "bytes_copied 1073741824" "should extract bytes copied"
    assert_contains "$output" "time_seconds 2.34567" "should extract time"
    assert_contains "$output" "throughput 458_MB/s" "should extract throughput"
    assert_contains "$output" "records_in 2097152" "should extract records in"
    assert_contains "$output" "records_out 2097152" "should extract records out"
}

test_dd_macos_format () {
    local output
    output=$(run_mfe -r -s dd "$SAMPLES_DIR/dd/macos.txt")
    assert_contains "$output" "bytes_transferred 1073741824" "should extract bytes transferred"
    assert_contains "$output" "time_seconds 2.345678" "should extract time"
    assert_contains "$output" "throughput" "should extract throughput"
}

test_dd_not_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"name": "test", "value": 42}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s dd "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "dd should not apply to JSON"
}

run_test "dd: basic Linux format extraction" test_dd_basic_linux
run_test "dd: macOS format extraction" test_dd_macos_format
run_test "dd: not detected for JSON" test_dd_not_json

print_summary
