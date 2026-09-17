#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Strategy Tests: git-log
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: git-log"
echo "========================================"

test_git_log_basic () {
    local output
    output=$(run_mfe -r -s git-log "$SAMPLES_DIR/git-log/basic.txt")
    # 2 commits x 4 fields = 8 fields
    assert_contains "$output" "commit1.hash abc1234567890abcdef1234567890abcdef12345" "should extract commit1 hash"
    assert_contains "$output" "commit1.author" "should extract commit1 author"
    assert_contains "$output" "John Doe" "should have author name"
    assert_contains "$output" "commit1.date" "should extract commit1 date"
    assert_contains "$output" "commit1.message Initial commit" "should extract commit1 message"
    assert_contains "$output" "commit2.hash def4567890abcdef1234567890abcdef12345678" "should extract commit2 hash"
    assert_contains "$output" "commit2.message Add README and documentation" "should extract commit2 message"
}

test_git_log_author () {
    local output
    output=$(run_mfe -r -s git-log "$SAMPLES_DIR/git-log/basic.txt")
    assert_contains "$output" "commit1.author John Doe <john@example.com>" "should extract full author"
    assert_contains "$output" "commit2.author Jane Smith <jane@example.com>" "should extract second author"
}

test_git_log_oneline () {
    local tmpfile
    tmpfile=$(mktemp)
    printf 'abc1234 Initial commit\ndef5678 Add README\n' > "$tmpfile"
    local output
    output=$(run_mfe -r -s git-log "$tmpfile")
    rm -f "$tmpfile"
    assert_contains "$output" "commit1.hash abc1234" "should extract oneline hash"
    assert_contains "$output" "commit1.message Initial commit" "should extract oneline message"
    assert_contains "$output" "commit2.hash def5678" "should extract second oneline hash"
}

test_git_log_not_detected_for_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"key": "value", "count": 42}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s git-log "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "git-log should not apply to JSON"
}

run_test "git-log: basic extraction" test_git_log_basic
run_test "git-log: author extraction" test_git_log_author
run_test "git-log: oneline format" test_git_log_oneline
run_test "git-log: not detected for JSON" test_git_log_not_detected_for_json

print_summary
