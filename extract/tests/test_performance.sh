#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Performance Tests for provost-extract (provost-extract)
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Performance Tests"
echo "========================================"

################################################################################
## Large input (10K+ lines)
################################################################################

test_large_colons_input () {
    local tmpfile
    tmpfile=$(mktemp)
    # Generate 10,000 key: value lines
    local i=0
    while [[ $i -lt 10000 ]]; do
        echo "Field_${i}: Value_${i}" >> "$tmpfile"
        i=$((i + 1))
    done
    local start_time=$SECONDS
    local rc=0
    run_extract -s colons "$tmpfile" >/dev/null 2>&1 || rc=$?
    local elapsed=$((SECONDS - start_time))
    rm -f "$tmpfile"
    assert_exit_zero "$rc" "10K lines should complete successfully"
    if [[ $elapsed -gt 60 ]]; then
        echo "  SLOW: took ${elapsed}s (limit 60s)"
        return 1
    fi
}

test_large_json_input () {
    local tmpfile
    tmpfile=$(mktemp)
    # Generate a JSON object with 1000 keys
    echo "{" > "$tmpfile"
    local i=0
    while [[ $i -lt 1000 ]]; do
        if [[ $i -gt 0 ]]; then
            echo "," >> "$tmpfile"
        fi
        printf '  "field_%d": "value_%d"' "$i" "$i" >> "$tmpfile"
        i=$((i + 1))
    done
    echo "" >> "$tmpfile"
    echo "}" >> "$tmpfile"
    local start_time=$SECONDS
    local rc=0
    run_extract -s json "$tmpfile" >/dev/null 2>&1 || rc=$?
    local elapsed=$((SECONDS - start_time))
    rm -f "$tmpfile"
    assert_exit_zero "$rc" "1K JSON keys should complete successfully"
    if [[ $elapsed -gt 30 ]]; then
        echo "  SLOW: took ${elapsed}s (limit 30s)"
        return 1
    fi
}

################################################################################
## Strategy scan benchmark
################################################################################

test_list_strategies_performance () {
    local start_time=$SECONDS
    local rc=0
    run_extract --list-strategies >/dev/null 2>&1 || rc=$?
    local elapsed=$((SECONDS - start_time))
    assert_exit_zero "$rc" "list-strategies should complete successfully"
    if [[ $elapsed -gt 10 ]]; then
        echo "  SLOW: took ${elapsed}s (limit 10s)"
        return 1
    fi
}

################################################################################
## Single-strategy fast path benchmark
################################################################################

test_single_strategy_fast_path () {
    local start_time=$SECONDS
    local rc=0
    run_extract -s colons "$SAMPLES_DIR/colons/basic.txt" >/dev/null 2>&1 || rc=$?
    local elapsed=$((SECONDS - start_time))
    assert_exit_zero "$rc" "single strategy should complete successfully"
    if [[ $elapsed -gt 5 ]]; then
        echo "  SLOW: took ${elapsed}s (limit 5s)"
        return 1
    fi
}

################################################################################
## Run all tests
################################################################################

run_test "large colons input (10K lines)" test_large_colons_input
run_test "large JSON input (1K keys)" test_large_json_input
run_test "list-strategies scan benchmark" test_list_strategies_performance
run_test "single-strategy fast path" test_single_strategy_fast_path

print_summary
