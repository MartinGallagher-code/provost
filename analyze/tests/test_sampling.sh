#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

# ENV-063: --head N / --sample N / --seed flags
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

SAMPLE="$SAMPLES_DIR/trees.csv"  # 31 rows

test_head_n_rows () {
    local out
    out=$(run_mda --head 10 "$SAMPLE")
    assert_contains "$out" "Rows: 10" "--head 10 should analyse 10 rows"
    assert_contains "$out" "Sampling: (first 10 of 31 rows)" "banner should note sampling"
}

test_sample_deterministic () {
    local a b
    a=$(run_mda --sample 10 --seed 42 "$SAMPLE" | grep -E '^[[:space:]]*[0-9]+\.')
    b=$(run_mda --sample 10 --seed 42 "$SAMPLE" | grep -E '^[[:space:]]*[0-9]+\.')
    if [[ "$a" != "$b" ]]; then
        echo "  ASSERT FAILED: --sample with the same seed must be deterministic"
        return 1
    fi
}

test_sample_banner () {
    local out
    out=$(run_mda --sample 10 --seed 42 "$SAMPLE")
    assert_contains "$out" "Sampling: (random sample 10 of 31 rows, seed=42)" "banner must note sample + seed"
}

test_head_and_sample_mutually_exclusive () {
    local out code=0
    out=$(run_mda --head 5 --sample 5 "$SAMPLE" 2>&1) || code=$?
    [[ $code -ne 0 ]] || { echo "  ASSERT FAILED: --head + --sample should error"; return 1; }
    assert_contains "$out" "mutually exclusive" "error message should be explicit"
}

test_invalid_n_rejected () {
    local out code=0
    out=$(run_mda --head abc "$SAMPLE" 2>&1) || code=$?
    [[ $code -ne 0 ]] || { echo "  ASSERT FAILED: --head abc should error"; return 1; }
    out=$(run_mda --head 0 "$SAMPLE" 2>&1) || code=$?
    [[ $code -ne 0 ]] || { echo "  ASSERT FAILED: --head 0 should error"; return 1; }
    out=$(run_mda --sample -1 "$SAMPLE" 2>&1) || code=$?
    [[ $code -ne 0 ]] || { echo "  ASSERT FAILED: --sample -1 should error"; return 1; }
}

test_stdin_head () {
    local out
    out=$(cat "$SAMPLE" | run_mda --head 5)
    assert_contains "$out" "Rows: 5" "--head works over stdin"
}

test_head_json_has_banner () {
    local out
    out=$(run_mda --head 10 --format json "$SAMPLE")
    assert_contains "$out" "first 10 of 31 rows" "JSON overview item should note sampling"
}

run_test "ENV-063 --head N limits to N data rows" test_head_n_rows
run_test "ENV-063 --sample N with --seed is deterministic" test_sample_deterministic
run_test "ENV-063 --sample banner includes seed" test_sample_banner
run_test "ENV-063 --head and --sample are mutually exclusive" test_head_and_sample_mutually_exclusive
run_test "ENV-063 invalid N values rejected" test_invalid_n_rejected
run_test "ENV-063 --head works via stdin" test_stdin_head
run_test "ENV-063 --head banner appears in JSON output" test_head_json_has_banner

print_summary
