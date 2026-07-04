#!/bin/bash
################################################################################
## Strategy Tests: ls-l
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: ls-l"
echo "========================================"

test_ls_l_basic () {
    local output
    output=$(run_mfe -r -s ls-l "$SAMPLES_DIR/ls-l/basic.txt")
    # Fields must NOT be shifted (the tar-listing mis-parse put the link count
    # under owner and the owner under size).
    assert_contains "$output" "entry1.permissions -rw-r--r--" "first entry permissions"
    assert_contains "$output" "entry1.links 1" "first entry link count"
    assert_contains "$output" "entry1.owner root" "first entry owner (not the link count)"
    assert_contains "$output" "entry1.group root" "first entry group"
    assert_contains "$output" "entry1.size 9337" "first entry size (not the owner)"
    assert_contains "$output" "entry1.name ASSESSMENT.md" "first entry name"
    assert_contains "$output" "total_entries 4" "should count entries and skip the 'total' line"
}

test_ls_l_handles_acl_marker_and_symlink () {
    local output
    output=$(run_mfe -r -s ls-l "$SAMPLES_DIR/ls-l/basic.txt")
    assert_contains "$output" "entry3.permissions drwxrwxrwx+" "keeps the ACL '+' marker on perms"
    assert_contains "$output" "entry4.name link_->_target" "captures a symlink's -> target in the name"
}

test_ls_l_not_detected_for_json () {
    local output
    output=$(run_mfe -d -s ls-l "$SAMPLES_DIR/json/basic.json" 2>&1)
    assert_contains "$output" "not applicable" "should not apply to JSON"
}

# Regression: tar-listing (whose second field is owner/group) must NOT grab
# ls -l output (whose second field is a numeric link count); ls-l handles it.
test_tar_listing_does_not_grab_ls_output () {
    local output
    output=$(run_mfe -d -s tar-listing "$SAMPLES_DIR/ls-l/basic.txt" 2>&1)
    assert_contains "$output" "not applicable" "tar-listing must not match ls -l output"
    output=$(run_mfe -d -s ls-l "$SAMPLES_DIR/ls-l/basic.txt" 2>&1)
    assert_not_contains "$output" "not applicable" "ls-l must match ls -l output"
}

run_test "ls-l: basic extraction (fields not shifted)" test_ls_l_basic
run_test "ls-l: ACL marker + symlink target" test_ls_l_handles_acl_marker_and_symlink
run_test "ls-l: not detected for JSON" test_ls_l_not_detected_for_json
run_test "ls-l: tar-listing does not grab ls output" test_tar_listing_does_not_grab_ls_output

print_summary
