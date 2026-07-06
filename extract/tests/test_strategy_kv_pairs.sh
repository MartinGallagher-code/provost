#!/bin/bash
################################################################################
## Strategy Tests: kv-pairs
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: kv-pairs"
echo "========================================"

test_kv_pairs_comma_separated () {
    local output
    output=$(run_mfe -r -s kv-pairs "$SAMPLES_DIR/kv-pairs/basic.txt")
    # Each line is a record -> entry<N>.<key> groups (which the capture-side
    # tidy melt later turns into one row per line).
    assert_contains "$output" "entry1.a 1" "record 1, key a"
    assert_contains "$output" "entry1.b 2" "record 1, key b"
    assert_contains "$output" "entry2.a 5" "record 2, key a"
    assert_contains "$output" "entry2.c 7" "record 2, key c"
    assert_contains "$output" "total_entries 2" "two records"
    assert_not_contains "$output" "_b" "no leading underscore from the ', ' delimiter"
}

test_kv_pairs_space_separated () {
    local tmp
    tmp=$(mktemp)
    printf 'x=10 y=20 z=30\nx=40 y=50 z=60\n' > "$tmp"
    local output
    output=$(run_mfe -r -s kv-pairs "$tmp")
    rm -f "$tmp"
    assert_contains "$output" "entry1.x 10" "space-separated pairs parse"
    assert_contains "$output" "entry2.z 60" "second record"
}

test_kv_pairs_not_single_pair_lines () {
    # One pair per line is a different shape (config/.env) — must not match.
    local tmp
    tmp=$(mktemp)
    printf 'a=1\nb=2\nc=3\n' > "$tmp"
    local output
    output=$(run_mfe -d -s kv-pairs "$tmp" 2>&1)
    rm -f "$tmp"
    assert_contains "$output" "not applicable" "single pair per line should not match kv-pairs"
}

test_kv_pairs_not_plain_csv () {
    # Bare CSV (no '=') is not kv-pairs.
    local output
    output=$(run_mfe -d -s kv-pairs "$SAMPLES_DIR/csv/basic.csv" 2>&1)
    assert_contains "$output" "not applicable" "plain CSV should not match kv-pairs"
}

run_test "kv-pairs: comma-separated records" test_kv_pairs_comma_separated
run_test "kv-pairs: space-separated records" test_kv_pairs_space_separated
run_test "kv-pairs: single-pair lines not matched" test_kv_pairs_not_single_pair_lines
run_test "kv-pairs: plain CSV not matched" test_kv_pairs_not_plain_csv

print_summary
