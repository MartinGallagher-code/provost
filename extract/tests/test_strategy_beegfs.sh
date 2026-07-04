#!/bin/bash
################################################################################
## Strategy Tests: beegfs
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: beegfs"
echo "========================================"

test_beegfs_detect () {
    local output
    output=$(run_mfe -d -s beegfs "$SAMPLES_DIR/beegfs/basic.txt" 2>&1)
    assert_contains "$output" "applicable" "should detect beegfs output"
}

test_beegfs_values () {
    local output
    output=$(run_mfe -r -s beegfs "$SAMPLES_DIR/beegfs/basic.txt")
    assert_contains "$output" "target1.target_id 1" "should extract target 1 ID"
    assert_contains "$output" "target1.state Online" "should extract target 1 state"
    assert_contains "$output" "target1.capacity 500G" "should extract target 1 capacity"
    assert_contains "$output" "target1.free_space 200G" "should extract target 1 free space"
    assert_contains "$output" "target2.target_id 2" "should extract target 2 ID"
    assert_contains "$output" "target2.free_space 150G" "should extract target 2 free space"
    assert_contains "$output" "target4.state Offline" "should extract target 4 offline state"
}

test_beegfs_not_json () {
    local tmpfile=$(mktemp)
    printf '{"name": "test"}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s beegfs "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "should not match JSON"
}

run_test "beegfs: detection" test_beegfs_detect
run_test "beegfs: specific values" test_beegfs_values
run_test "beegfs: not detected for JSON" test_beegfs_not_json

print_summary
