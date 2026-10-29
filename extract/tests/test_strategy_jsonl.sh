#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Strategy Tests: jsonl
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: jsonl"
echo "========================================"

################################################################################
## Basic JSONL extraction (per-line fields)
################################################################################

test_jsonl_basic () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"host": "web-01", "status": "up"}\n{"host": "web-02", "status": "down"}\n' > "$tmpfile"
    local output
    output=$(run_extract -r -s jsonl "$tmpfile")
    rm -f "$tmpfile"
    assert_contains "$output" "host" "should extract host field"
    assert_contains "$output" "web-01" "should extract value web-01"
    assert_contains "$output" "status" "should extract status field"
    assert_contains "$output" "up" "should extract value up"
    assert_contains "$output" "web-02" "should extract value web-02"
}

################################################################################
## Multiple fields per line
################################################################################

test_jsonl_multiple_fields () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"name": "Alice", "age": 30, "city": "Boston"}\n{"name": "Bob", "age": 25, "city": "NYC"}\n' > "$tmpfile"
    local output
    output=$(run_extract -r -s jsonl "$tmpfile")
    rm -f "$tmpfile"
    # JSONL strategy prefixes with lineN.fieldname
    assert_contains "$output" "line1.name" "should prefix line1 for first record"
    assert_contains "$output" "line2.name" "should prefix line2 for second record"
    assert_contains "$output" "Alice" "should extract Alice"
    assert_contains "$output" "Bob" "should extract Bob"
    assert_contains "$output" "city" "should extract city field"
}

################################################################################
## Not detected for regular JSON object (single multi-line JSON)
################################################################################

test_jsonl_not_for_json_object () {
    local output
    output=$(run_extract -d -s jsonl "$SAMPLES_DIR/json/basic.json" 2>&1)
    assert_contains "$output" "not applicable" "jsonl should not apply to regular JSON object"
}

################################################################################
## Not detected for plain text
################################################################################

test_jsonl_not_for_plain_text () {
    local tmpfile
    tmpfile=$(mktemp)
    printf 'This is just plain text.\nNothing JSON about it.\nNo really.\n' > "$tmpfile"
    local output
    output=$(run_extract -d -s jsonl "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "jsonl should not apply to plain text"
}

################################################################################
## Run all tests
################################################################################

# Comment lines a tool prints above its records are skipped and not counted;
# they used to push the records out of the detector's window, and the file
# was read as aligned columns.
JSONL_COMMENTED='# dcprobe scan 2026-10-29
# 2 hosts

{"host": "wr01", "load1": 0.5, "nic": {"mtu": 9000, "up": true}}
  # between records
{"host": "wr02", "load1": 0.7, "nic": {"mtu": 1500, "up": false}}'

test_jsonl_after_comments () {
    local tmp output
    tmp="$(mktemp)"
    printf '%s\n' "$JSONL_COMMENTED" > "$tmp"
    output=$(run_extract -s jsonl -d "$tmp" 2>&1)
    assert_not_contains "$output" "not applicable" "comment lines do not hide the records"
    output=$(run_extract -r -s jsonl -f plain "$tmp")
    rm -f "$tmp"
    assert_contains "$output" "line1.host wr01" "the first record is line 1"
    assert_contains "$output" "line2.load1 0.7" "the second is line 2"
    assert_not_contains "$output" "dcprobe" "the comments are not records"
}

test_jsonl_without_jq_matches_jq () {
    local tmp a b
    tmp="$(mktemp)"
    printf '%s\n' "$JSONL_COMMENTED" > "$tmp"
    b=$(run_extract_nojq -r -s jsonl -f plain "$tmp")
    assert_contains "$b" 'line1.nic {"mtu":9000,"up":true}' "a nested value is its compact JSON"
    assert_contains "$b" "line2.host wr02" "every record read"
    if command -v jq >/dev/null 2>&1; then
        a=$(run_extract -r -s jsonl -f plain "$tmp")
        assert_eq "$a" "$b" "without jq: the rows jq gives"
    fi
    rm -f "$tmp"
}

run_test "jsonl: records after # comment lines" test_jsonl_after_comments
run_test "jsonl: without jq, the rows jq gives" test_jsonl_without_jq_matches_jq
run_test "jsonl: basic per-line extraction" test_jsonl_basic
run_test "jsonl: multiple fields per line" test_jsonl_multiple_fields
run_test "jsonl: not detected for regular JSON object" test_jsonl_not_for_json_object
run_test "jsonl: not detected for plain text" test_jsonl_not_for_plain_text

print_summary
