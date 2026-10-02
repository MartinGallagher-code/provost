#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Strategy Tests: free
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: free"
echo "========================================"

test_detect () {
    local output
    output=$(run_extract -d -s free "$SAMPLES_DIR/free/basic.txt" 2>&1)
    assert_contains "$output" "detected as applicable" "free should detect free -h output"
}

test_extract () {
    # v2.0: `free` is emitted as indexed row groups (entry<N>.<field>) so the
    # capture-side tidy melt turns it into one row per region with shared
    # columns, rather than one wide Mem_*/Swap_* record.
    local output
    output=$(run_extract -r -s free "$SAMPLES_DIR/free/basic.txt")
    assert_contains "$output" "entry1.name Mem" "row 1 is the Mem region"
    assert_contains "$output" "entry1.total 15Gi" "Mem total"
    assert_contains "$output" "entry1.used 8.2Gi" "Mem used"
    assert_contains "$output" "entry1.free 1.5Gi" "Mem free"
    assert_contains "$output" "entry1.shared 512Mi" "Mem shared"
    assert_contains "$output" "entry1.buff_cache 5.8Gi" "Mem buff/cache -> buff_cache field"
    assert_contains "$output" "entry1.available 6.5Gi" "Mem available"
    assert_contains "$output" "entry2.name Swap" "row 2 is the Swap region"
    assert_contains "$output" "entry2.total 4.0Gi" "Swap total"
    assert_contains "$output" "entry2.used 1.2Gi" "Swap used"
    assert_contains "$output" "entry2.free 2.8Gi" "Swap free"
    assert_contains "$output" "total_entries 2" "two regions"
}

test_field_selection () {
    local output
    output=$(run_extract -r -s free "$SAMPLES_DIR/free/basic.txt")
    assert_contains "$output" "entry1.total" "should have a total field"
    assert_contains "$output" "entry2.free" "should have a Swap free field"
    assert_not_contains "$output" "buffers" "should not have raw buffers field"
}

# Swap has no shared/buff_cache/available columns; those must not be
# fabricated for the Swap region.
test_swap_has_no_trailing_columns () {
    local output
    output=$(run_extract -r -s free "$SAMPLES_DIR/free/basic.txt")
    assert_not_contains "$output" "entry2.shared" "Swap row must not invent a shared value"
    assert_not_contains "$output" "entry2.available" "Swap row must not invent an available value"
}

run_test "free: detection" test_detect
run_test "free: extraction" test_extract
run_test "free: field selection" test_field_selection
run_test "free: swap has no trailing columns" test_swap_has_no_trailing_columns

print_summary
