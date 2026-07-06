#!/bin/bash
################################################################################
## Strategy Tests: ior
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: ior"
echo "========================================"

test_ior_detect () {
    local output
    output=$(run_mfe -d -s ior "$SAMPLES_DIR/ior/basic.txt" 2>&1)
    assert_contains "$output" "applicable" "should detect ior output"
}

test_ior_values () {
    local output
    output=$(run_mfe -r -s ior "$SAMPLES_DIR/ior/basic.txt")
    assert_contains "$output" "ior_version 3.3.0" "should extract IOR version"
    assert_contains "$output" "num_tasks 16" "should extract task count"
    assert_contains "$output" "xfer_size 1_MiB" "should extract transfer size"
    assert_contains "$output" "block_size 16_MiB" "should extract block size"
    assert_contains "$output" "aggregate_size 4_GiB" "should extract aggregate size"
    assert_contains "$output" "max_write_MiB 1234.56" "should extract max write"
    assert_contains "$output" "max_read_MiB 2345.67" "should extract max read"
    assert_contains "$output" "mean_write_MiB 1218.34" "should extract mean write"
    assert_contains "$output" "mean_read_MiB 2320.56" "should extract mean read"
    assert_contains "$output" "write.max_MiB 1234.56" "should extract write table row"
    assert_contains "$output" "read.max_MiB 2345.67" "should extract read table row"
}

test_ior_not_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"name": "test"}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s ior "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "should not match JSON"
}

run_test "ior: detection" test_ior_detect
run_test "ior: specific values" test_ior_values
run_test "ior: not detected for JSON" test_ior_not_json

print_summary
