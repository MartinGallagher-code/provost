#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Strategy Tests: tar-listing
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: tar-listing"
echo "========================================"

test_tar_listing_basic () {
    local output
    output=$(run_mfe -r -s columnar-specs "$SAMPLES_DIR/tar-listing/basic.txt")
    assert_contains "$output" "entry1.permissions drwxr-xr-x" "should extract first entry permissions"
    assert_contains "$output" "entry1.owner user/group" "should extract first entry owner"
    assert_contains "$output" "entry2.size 1234" "should extract second entry size"
    assert_contains "$output" "entry1.time " "should keep the timestamp's time component"
    assert_contains "$output" "entry2.path myproject/README.md" "should extract second entry path"
    assert_contains "$output" "total_entries 7" "should count total entries"
}

test_tar_listing_not_detected_for_json () {
    local output
    output=$(run_mfe -d -s columnar-specs "$SAMPLES_DIR/json/basic.json" 2>&1)
    assert_contains "$output" "not applicable" "should not apply to JSON"
}

test_tar_listing_not_detected_for_aligned_columns () {
    local output
    output=$(run_mfe -d -s columnar-specs "$SAMPLES_DIR/aligned-columns/basic.txt" 2>&1)
    assert_contains "$output" "not applicable" "should not apply to aligned columns"
}

run_test "tar-listing: basic extraction" test_tar_listing_basic
run_test "tar-listing: not detected for JSON" test_tar_listing_not_detected_for_json
run_test "tar-listing: not detected for aligned columns" test_tar_listing_not_detected_for_aligned_columns

print_summary
