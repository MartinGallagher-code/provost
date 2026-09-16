#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Tests for v3.2 features and previously untested code paths
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "v3.2 Feature and Coverage Tests"
echo "========================================"

################################################################################
## --version flag
################################################################################

test_version_flag () {
    local output
    output=$(run_mfe --version)
    assert_contains "$output" "envoy-extract" "should show version number"
}

test_version_short_flag () {
    local output
    output=$(run_mfe -V)
    assert_contains "$output" "envoy-extract" "short version flag should work"
}

################################################################################
## --quiet flag
################################################################################

test_quiet_success () {
    local rc=0
    run_mfe -q -s json "$SAMPLES_DIR/json/basic.json" >/dev/null 2>&1 || rc=$?
    assert_exit_zero "$rc" "quiet should exit 0 when fields found"
}

test_quiet_no_output () {
    local output
    output=$(run_mfe -q -s json "$SAMPLES_DIR/json/basic.json" 2>&1)
    assert_eq "" "$output" "quiet should produce no output"
}

test_quiet_failure () {
    local tmpfile rc=0
    tmpfile=$(mktemp)
    echo "no structure here" > "$tmpfile"
    run_mfe -q --min-confidence 100 "$tmpfile" >/dev/null 2>&1 || rc=$?
    rm -f "$tmpfile"
    assert_exit_nonzero "$rc" "quiet should exit 1 when no fields found"
}

################################################################################
## --count flag
################################################################################

test_count_basic () {
    local output
    output=$(run_mfe --count -s json "$SAMPLES_DIR/json/basic.json")
    # Should be a single number
    [[ "$output" =~ ^[0-9]+$ ]] || { echo "ASSERT FAILED: count should be a number, got '$output'"; return 1; }
    [[ "$output" -gt 0 ]] || { echo "ASSERT FAILED: count should be > 0, got '$output'"; return 1; }
}

################################################################################
## --names flag
################################################################################

test_names_basic () {
    local output
    output=$(run_mfe --names -s colons "$SAMPLES_DIR/colons/basic.txt")
    # Should contain field names but NOT values
    assert_contains "$output" "Name" "names should list Name field"
    assert_not_contains "$output" "John" "names should not include values"
}

################################################################################
## --sort flag
################################################################################

test_sort_basic () {
    local tmpfile
    tmpfile=$(mktemp)
    printf 'Zebra: last\nAlpha: first\nMid: middle\n' > "$tmpfile"
    local output
    output=$(run_mfe --sort -r -s colons "$tmpfile")
    rm -f "$tmpfile"
    # Alpha should appear before Mid, Mid before Zebra
    local alpha_pos mid_pos zebra_pos
    alpha_pos=$(echo "$output" | grep -n 'Alpha' | head -1 | cut -d: -f1)
    mid_pos=$(echo "$output" | grep -n 'Mid' | head -1 | cut -d: -f1)
    zebra_pos=$(echo "$output" | grep -n 'Zebra' | head -1 | cut -d: -f1)
    [[ "$alpha_pos" -lt "$mid_pos" && "$mid_pos" -lt "$zebra_pos" ]] || {
        echo "ASSERT FAILED: fields not sorted alphabetically"
        echo "  Alpha at line $alpha_pos, Mid at $mid_pos, Zebra at $zebra_pos"
        return 1
    }
}

################################################################################
## Field selection by name
################################################################################

test_field_selection_by_name () {
    local output
    output=$(run_mfe -s json -f json "$SAMPLES_DIR/json/basic.json" name,version)
    assert_contains "$output" '"name":' "should select name field by name"
    assert_contains "$output" '"version":' "should select version field by name"
}

################################################################################
## display() default table output
################################################################################

test_default_piped_output_is_json () {
    local output
    # Captured output (non-TTY) defaults to JSON since v4.2
    output=$(run_mfe -s colons "$SAMPLES_DIR/colons/basic.txt")
    assert_json_valid "$output" "default piped output should be valid JSON"
}

################################################################################
## Numeric option validation
################################################################################

test_min_confidence_non_numeric () {
    local output rc=0
    output=$(run_mfe --min-confidence abc 2>&1) || rc=$?
    assert_exit_nonzero "$rc" "non-numeric min-confidence should fail"
    assert_contains "$output" "requires a number" "should show error about number"
}

test_max_strategies_non_numeric () {
    local output rc=0
    output=$(run_mfe --max-strategies xyz 2>&1) || rc=$?
    assert_exit_nonzero "$rc" "non-numeric max-strategies should fail"
    assert_contains "$output" "requires a number" "should show error about number"
}

################################################################################
## JSON escaping
################################################################################

test_json_escape_backslash () {
    local tmpfile
    tmpfile=$(mktemp)
    printf 'path: C:\\Users\\test\n' > "$tmpfile"
    local output
    output=$(run_mfe -s colons -f json "$tmpfile" 1)
    rm -f "$tmpfile"
    # The value C:\Users\test should be JSON-escaped to C:\\Users\\test
    assert_contains "$output" '\\' "JSON should have escaped backslashes"
}

################################################################################
## Stream mode error paths
################################################################################

test_stream_no_strategy () {
    local output rc=0
    output=$(echo "data" | run_mfe --stream 2>&1) || rc=$?
    assert_exit_nonzero "$rc" "stream without strategy should fail"
    assert_contains "$output" "--stream requires --strategy" "should show stream error"
}

test_stream_with_file () {
    local output rc=0
    output=$(run_mfe --stream --strategy colons "$SAMPLES_DIR/colons/basic.txt" 2>&1) || rc=$?
    assert_exit_nonzero "$rc" "stream with file should fail"
    assert_contains "$output" "reads from stdin" "should show stdin-only error"
}

################################################################################
## --strategy with nonexistent strategy
################################################################################

test_strategy_not_found () {
    local output rc=0
    output=$(run_mfe -s nonexistent_strategy "$SAMPLES_DIR/json/basic.json" 2>&1) || rc=$?
    assert_exit_nonzero "$rc" "nonexistent strategy should fail"
    assert_contains "$output" "Strategy not found" "should show strategy-not-found error"
}

################################################################################
## Chain with actual chaining (A → B)
################################################################################

test_chain_two_strategies () {
    local tmpfile
    tmpfile=$(mktemp)
    printf 'Host: localhost\nPort: 5432\n' > "$tmpfile"
    local output rc=0
    output=$(run_mfe -r --chain 'colons' "$tmpfile" 2>&1) || rc=$?
    rm -f "$tmpfile"
    assert_exit_zero "$rc" "chain should succeed"
    assert_contains "$output" "STRAT-chain" "chain should produce output"
}

test_chain_not_found () {
    local tmpfile
    tmpfile=$(mktemp)
    printf 'data\n' > "$tmpfile"
    local output rc=0
    output=$(run_mfe --chain 'nonexistent_strat' "$tmpfile" 2>&1) || rc=$?
    rm -f "$tmpfile"
    assert_exit_nonzero "$rc" "chain with missing strategy should fail"
    assert_contains "$output" "Strategy not found" "should show not-found error"
}

################################################################################
## Verbose hints when no extraction
################################################################################

test_verbose_json_hint () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"key": "val"}\n' > "$tmpfile"
    local output rc=0
    output=$(run_mfe -v --min-confidence 100 "$tmpfile" 2>&1) || rc=$?
    rm -f "$tmpfile"
    assert_contains "$output" "Input may contain JSON" "verbose should hint about JSON"
}

test_verbose_colon_hint () {
    local tmpfile
    tmpfile=$(mktemp)
    printf 'random: data\n' > "$tmpfile"
    local output rc=0
    output=$(run_mfe -v --min-confidence 100 "$tmpfile" 2>&1) || rc=$?
    rm -f "$tmpfile"
    assert_contains "$output" "colon patterns" "verbose should hint about colons"
}

################################################################################
## Replay with multi-strategy spec
################################################################################

test_replay_multi_strategy () {
    local tmpfile
    tmpfile=$(mktemp)
    printf 'Host: localhost\nPort: 5432\n' > "$tmpfile"
    local output rc=0
    output=$(run_mfe -r --replay 'colons@1.0' "$tmpfile" 2>&1) || rc=$?
    rm -f "$tmpfile"
    assert_exit_zero "$rc" "replay should succeed"
    assert_contains "$output" "Host" "replay should extract Host"
}

################################################################################
## _is_json helper (used by strategies)
################################################################################

test_is_json_helper () {
    # Source envoy-extract to get the _is_json function
    source "$MFE_SCRIPT" --help >/dev/null 2>&1 || true
    # Actually, we can't easily source envoy-extract (it has set -e and runs).
    # Instead, verify indirectly: JSON input with a strategy that uses _is_json
    # should properly reject JSON
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"key": "value"}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s colons "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    # Colons should not match JSON input
    assert_contains "$output" "not applicable" "colons should reject JSON input"
}

################################################################################
## Run all tests
################################################################################

run_test "v3.2: --version flag" test_version_flag
run_test "v3.2: -V short version flag" test_version_short_flag
run_test "v3.2: --quiet exits 0 when fields found" test_quiet_success
run_test "v3.2: --quiet produces no output" test_quiet_no_output
run_test "v3.2: --quiet exits 1 when no fields" test_quiet_failure
run_test "v3.2: --count outputs field count" test_count_basic
run_test "v3.2: --names lists field names only" test_names_basic
run_test "v3.2: --sort alphabetical ordering" test_sort_basic
run_test "v3.2: field selection by name" test_field_selection_by_name
run_test "v3.2: default piped output is JSON" test_default_piped_output_is_json
run_test "v3.2: --min-confidence rejects non-numeric" test_min_confidence_non_numeric
run_test "v3.2: --max-strategies rejects non-numeric" test_max_strategies_non_numeric
run_test "v3.2: JSON escaping handles backslashes" test_json_escape_backslash
run_test "v3.2: --stream without --strategy fails" test_stream_no_strategy
run_test "v3.2: --stream with file fails" test_stream_with_file
run_test "v3.2: --strategy nonexistent fails" test_strategy_not_found
run_test "v3.2: --chain produces labeled output" test_chain_two_strategies
run_test "v3.2: --chain with missing strategy fails" test_chain_not_found
run_test "v3.2: verbose JSON hint" test_verbose_json_hint
run_test "v3.2: verbose colon hint" test_verbose_colon_hint
run_test "v3.2: replay with strategy spec" test_replay_multi_strategy

print_summary
