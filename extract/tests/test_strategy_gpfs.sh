#!/bin/bash
################################################################################
## Strategy Tests: gpfs
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: gpfs"
echo "========================================"

test_gpfs_detect () {
    local output
    output=$(run_mfe -d -s gpfs "$SAMPLES_DIR/gpfs/basic.txt" 2>&1)
    assert_contains "$output" "applicable" "should detect gpfs output"
}

test_gpfs_values () {
    local output
    output=$(run_mfe -r -s gpfs "$SAMPLES_DIR/gpfs/basic.txt")
    assert_contains "$output" "block_size 4194304" "should extract block size"
    assert_contains "$output" "inode_size 4096" "should extract inode size"
    assert_contains "$output" "mount_point /gpfs/fs01" "should extract mount point"
    assert_contains "$output" "inum_limit 1000000" "should extract inum limit"
    assert_contains "$output" "max_files 100000000" "should extract max files"
    assert_contains "$output" "replication 2" "should extract replication factor"
}

test_gpfs_not_json () {
    local tmpfile=$(mktemp)
    printf '{"name": "test"}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s gpfs "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "should not match JSON"
}

run_test "gpfs: detection" test_gpfs_detect
run_test "gpfs: specific values" test_gpfs_values
run_test "gpfs: not detected for JSON" test_gpfs_not_json

print_summary
