#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Tests for: provost-extract search subcommand (ENV-016)
################################################################################
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo "=== Search Subcommand Tests (ENV-016) ==="

test_search_finds_json () {
    local out
    out=$(run_extract search json 2>&1 || true)
    assert_contains "$out" "json" "should find json strategies"
    assert_contains "$out" "structured" "should show json's category"
}

test_search_case_insensitive_default () {
    local out
    out=$(run_extract search JSON 2>&1 || true)
    assert_contains "$out" "json" "uppercase JSON should still find json strategy (case-insensitive default)"
}

test_search_case_sensitive_flag_requires_exact_case () {
    # Without --case-sensitive, JSONL (uppercase) matches the jsonl strategy.
    # With --case-sensitive, JSONL should only match strategies whose metadata
    # literally contains the uppercase substring.
    local insensitive_has_jsonl sensitive_has_jsonl
    insensitive_has_jsonl=$(run_extract search JSONL 2>&1 || true)
    sensitive_has_jsonl=$(run_extract search --case-sensitive JSONL 2>&1 || true)
    # Sanity: case-insensitive run finds jsonl
    if ! echo "$insensitive_has_jsonl" | grep -q "^  structured     jsonl "; then
        echo "  ASSERT FAILED: case-insensitive JSONL search should find jsonl strategy"
        return 1
    fi
    # With --case-sensitive, jsonl (lowercase strategy name) should NOT match
    # because no metadata field literally contains uppercase "JSONL".
    if echo "$sensitive_has_jsonl" | grep -q "^  structured     jsonl "; then
        echo "  ASSERT FAILED: --case-sensitive JSONL should not match lowercase jsonl strategy"
        return 1
    fi
}

test_search_category_narrows_results () {
    local out
    # Search for csv, without category restriction vs with "structured" restriction
    local all_out struct_out
    all_out=$(run_extract search csv 2>&1 || true)
    struct_out=$(run_extract search --category structured csv 2>&1 || true)
    # Both should contain the structured/csv strategy
    assert_contains "$struct_out" "csv" "category-filtered search should include csv"
    # Filtered output should have <= lines as unfiltered (narrowed set)
    local all_lines struct_lines
    all_lines=$(echo "$all_out" | wc -l)
    struct_lines=$(echo "$struct_out" | wc -l)
    [[ "$struct_lines" -le "$all_lines" ]] || { echo "  ASSERT FAILED: --category should narrow results"; return 1; }
}

test_search_multiple_keywords_and_semantics () {
    local out
    # Find strategies with both "docker" and "ps" in metadata (AND). This used
    # to look for docker-stats, which no longer exists as a strategy; the
    # property under test is the AND, so a live pair stands in.
    out=$(run_extract search docker ps 2>&1 || true)
    assert_contains "$out" "docker-ps" "AND of docker+ps should find docker-ps"
    # The other half of AND: a second keyword docker-ps does NOT carry must
    # exclude it, or the search is really an OR.
    out=$(run_extract search docker toml 2>&1 || true)
    assert_not_contains "$out" "docker-ps" "AND of docker+toml should exclude docker-ps"
}

test_search_no_args_lists_all () {
    local out
    out=$(run_extract search 2>&1 || true)
    # Should have header + many rows (at least 50)
    local lines
    lines=$(echo "$out" | grep -c "^  ")
    [[ "$lines" -ge 50 ]] || { echo "  ASSERT FAILED: empty search should list all strategies (got $lines rows)"; return 1; }
}

test_search_no_match_exits_1 () {
    local rc=0
    run_extract search xyzzy-nonexistent-strategy >/dev/null 2>&1 || rc=$?
    [[ "$rc" -eq 1 ]] || { echo "  ASSERT FAILED: no-match should exit 1 (got $rc)"; return 1; }
}

test_search_match_exits_0 () {
    local rc=0
    run_extract search json >/dev/null 2>&1 || rc=$?
    [[ "$rc" -eq 0 ]] || { echo "  ASSERT FAILED: match should exit 0 (got $rc)"; return 1; }
}

run_test "search: finds json strategies" test_search_finds_json
run_test "search: case-insensitive by default" test_search_case_insensitive_default
run_test "search: --case-sensitive requires exact case" test_search_case_sensitive_flag_requires_exact_case
run_test "search: --category narrows results" test_search_category_narrows_results
run_test "search: multiple keywords use AND semantics" test_search_multiple_keywords_and_semantics
run_test "search: no args lists all strategies" test_search_no_args_lists_all
run_test "search: no match exits 1" test_search_no_match_exits_1
run_test "search: match exits 0" test_search_match_exits_0

print_summary
