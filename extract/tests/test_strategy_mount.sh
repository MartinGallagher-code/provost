#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Strategy Tests: mount
################################################################################
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"
echo ""
echo "Strategy Tests: mount"

test_mount_basic () {
    local output
    output=$(run_mfe -r -s columnar-specs "$SAMPLES_DIR/mount/basic.txt")
    assert_contains "$output" "entry1.device /dev/sda1" "first device"
    assert_contains "$output" "entry1.mount_point /" "first mount point"
    assert_contains "$output" "entry1.fstype ext4" "first fstype"
    assert_contains "$output" "entry1.options rw,relatime" "first options"
    # tmpfs is the THIRD row of the sample (sda1, proc, tmpfs, sdb1); this
    # asserted entry2 and never failed, because the harness swallowed it.
    assert_contains "$output" "entry3.fstype tmpfs" "third fstype"
    assert_contains "$output" "total_entries 4" "counts all mounts"
}
test_mount_detects () {
    local output
    output=$(run_mfe -d -s columnar-specs "$SAMPLES_DIR/mount/basic.txt" 2>&1)
    assert_not_contains "$output" "not applicable" "mount must match mount output"
}
run_test "mount: basic extraction" test_mount_basic
run_test "mount: detected" test_mount_detects
print_summary
