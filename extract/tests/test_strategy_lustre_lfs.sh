#!/bin/bash
################################################################################
## Strategy Tests: lustre-lfs
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: lustre-lfs"
echo "========================================"

test_lustre_lfs_detect () {
    local output
    output=$(run_mfe -d -s lustre-lfs "$SAMPLES_DIR/lustre-lfs/basic.txt" 2>&1)
    assert_contains "$output" "applicable" "should detect lustre-lfs output"
}

test_lustre_lfs_values () {
    local output
    output=$(run_mfe -r -s lustre-lfs "$SAMPLES_DIR/lustre-lfs/basic.txt")
    assert_contains "$output" "target1.filesystem scratch-MDT0000_UUID" "should extract MDT target"
    assert_contains "$output" "target2.filesystem scratch-OST0000_UUID" "should extract OST0000 target"
    assert_contains "$output" "target2.used_KB 734003200" "should extract OST0000 used KB"
    assert_contains "$output" "target2.available_KB 1363148800" "should extract OST0000 available KB"
    assert_contains "$output" "target2.use_percent 35" "should extract OST0000 use percent"
    assert_contains "$output" "target3.filesystem scratch-OST0001_UUID" "should extract OST0001 target"
    assert_contains "$output" "target5.use_percent 40" "should extract OST0003 use percent"
}

test_lustre_lfs_summary () {
    local output
    output=$(run_mfe -r -s lustre-lfs "$SAMPLES_DIR/lustre-lfs/basic.txt")
    assert_contains "$output" "summary.used_KB 3041070400" "should extract summary used KB"
    assert_contains "$output" "summary.available_KB 5347537600" "should extract summary available KB"
}

test_lustre_lfs_not_json () {
    local tmpfile=$(mktemp)
    printf '{"name": "test"}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s lustre-lfs "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "should not match JSON"
}

run_test "lustre-lfs: detection" test_lustre_lfs_detect
run_test "lustre-lfs: specific values" test_lustre_lfs_values
run_test "lustre-lfs: summary extraction" test_lustre_lfs_summary
run_test "lustre-lfs: not detected for JSON" test_lustre_lfs_not_json

print_summary
