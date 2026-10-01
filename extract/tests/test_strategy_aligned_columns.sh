#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Strategy Tests: aligned-columns
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: aligned-columns"
echo "========================================"

################################################################################
## Basic ps-style aligned column extraction
################################################################################

test_aligned_columns_ps () {
    local output
    output=$(run_mfe -r -s aligned-columns "$SAMPLES_DIR/aligned-columns/basic.txt")
    assert_contains "$output" "PID" "should extract PID column"
    assert_contains "$output" "USER" "should extract USER column"
    assert_contains "$output" "CPU" "should extract CPU column"
    assert_contains "$output" "MEM" "should extract MEM column"
    assert_contains "$output" "COMMAND" "should extract COMMAND column"
    assert_contains "$output" "123" "should extract PID value 123"
    assert_contains "$output" "root" "should extract USER value root"
}

# v2.0: each data line is an indexed row group (entry<N>.<field>) so the
# capture tidy melt turns it into one row per line, not a single wide record.
test_aligned_columns_row_groups () {
    local output
    output=$(run_mfe -r -s aligned-columns "$SAMPLES_DIR/aligned-columns/basic.txt")
    assert_contains "$output" "entry1.PID 123" "row 1 grouped under entry1"
    assert_contains "$output" "entry2.USER www" "row 2 grouped under entry2"
    assert_contains "$output" "entry3.COMMAND postgres" "row 3 grouped under entry3"
    assert_contains "$output" "total_entries 3" "three rows"
}

################################################################################
## df-style output extraction
################################################################################

test_aligned_columns_df () {
    local tmpfile
    tmpfile=$(mktemp)
    printf 'Filesystem  Size  Used  Avail  Use%%  Mounted\n/dev/sda1   50G   30G   20G    60%%  /\ntmpfs       4G    0G    4G     0%%   /tmp\n' > "$tmpfile"
    local output
    output=$(run_mfe -r -s aligned-columns "$tmpfile")
    rm -f "$tmpfile"
    assert_contains "$output" "Filesystem" "should extract Filesystem column"
    assert_contains "$output" "Size" "should extract Size column"
    assert_contains "$output" "/dev/sda1" "should extract filesystem value"
    assert_contains "$output" "50G" "should extract size value"
}

################################################################################
## Not detected for JSON
################################################################################

test_aligned_columns_not_json () {
    local output
    output=$(run_mfe -d -s aligned-columns "$SAMPLES_DIR/json/basic.json" 2>&1)
    assert_contains "$output" "not applicable" "aligned-columns should not apply to JSON"
}

################################################################################
## Run all tests
################################################################################

# Surplus trailing tokens fold into the last column JOINED WITH SPACES — an
# ls -l symlink is `sh -> busybox`, not `sh_->_busybox`.
test_aligned_columns_trailing_tokens_keep_spaces () {
    local tmp output
    tmp="$(mktemp)"
    printf 'drwxr-xr-x 2 root root 4096 Jul  6 09:12 bin\n-rw-r--r-- 1 alice users 1024 Jul  5 18:03 notes.txt\nlrwxrwxrwx 1 root root    7 Jul  1 00:00 sh -> busybox\n' > "$tmp"
    output=$(run_mfe -s aligned-columns -f plain "$tmp")
    rm -f "$tmp"
    assert_contains "$output" " sh -> busybox" "symlink target keeps its spaces"
    assert_not_contains "$output" "sh_->_busybox" "no underscores invented"
}

run_test "aligned-columns: ps-style extraction" test_aligned_columns_ps
run_test "aligned-columns: indexed row groups" test_aligned_columns_row_groups
run_test "aligned-columns: df-style extraction" test_aligned_columns_df
run_test "aligned-columns: not detected for JSON" test_aligned_columns_not_json

run_test "aligned-columns: trailing tokens joined with spaces" test_aligned_columns_trailing_tokens_keep_spaces
print_summary
