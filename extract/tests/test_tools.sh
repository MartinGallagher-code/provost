#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Tests for EnvoyExtract tools (new_strategy.sh, review_strategy.sh)
################################################################################

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../tools" && pwd)"
TMPDIR_TEST="${TMPDIR:-/tmp}/envoy_tools_test_$$"
mkdir -p "$TMPDIR_TEST"

cleanup () {
    rm -rf "$TMPDIR_TEST"
    # Clean up any scaffolded test strategies
    rm -rf "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/strategies/misc/test-tool-scaffold.sh"
    rm -rf "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/samples/test-tool-scaffold"
}
trap cleanup EXIT

################################################################################
## new_strategy.sh tests
################################################################################

test_new_strategy_help () {
    local out
    out=$(bash "$TOOLS_DIR/new_strategy.sh" --help 2>&1)
    assert_contains "$out" "Strategy Scaffolding Tool" "help should show title"
    assert_contains "$out" "--name" "help should mention --name"
    assert_contains "$out" "--category" "help should mention --category"
    assert_contains "$out" "--sample" "help should mention --sample"
}

test_new_strategy_missing_args () {
    local rc=0
    bash "$TOOLS_DIR/new_strategy.sh" 2>/dev/null || rc=$?
    assert_exit_nonzero "$rc" "should fail without args"
}

test_new_strategy_missing_sample () {
    local rc=0
    bash "$TOOLS_DIR/new_strategy.sh" --name foo --category misc --sample /nonexistent/file 2>/dev/null || rc=$?
    assert_exit_nonzero "$rc" "should fail with missing sample file"
}

test_new_strategy_invalid_name () {
    printf "data\n" > "$TMPDIR_TEST/sample.txt"
    local rc=0
    bash "$TOOLS_DIR/new_strategy.sh" --name "Bad Name" --category misc --sample "$TMPDIR_TEST/sample.txt" 2>/dev/null || rc=$?
    assert_exit_nonzero "$rc" "should fail with invalid name"
}

test_new_strategy_creates_files () {
    printf "key1: value1\nkey2: value2\n" > "$TMPDIR_TEST/sample.txt"
    local out
    out=$(bash "$TOOLS_DIR/new_strategy.sh" --name test-tool-scaffold --category misc --sample "$TMPDIR_TEST/sample.txt" 2>&1)
    local extract_dir
    extract_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

    # Check strategy file was created
    local strat_file="$extract_dir/strategies/misc/test-tool-scaffold.sh"
    [[ -f "$strat_file" ]]
    assert_exit_zero $? "strategy file should exist"

    # Check sample directory was created
    local sample_dir="$extract_dir/samples/test-tool-scaffold"
    [[ -d "$sample_dir" ]]
    assert_exit_zero $? "sample directory should exist"

    [[ -f "$sample_dir/sample1.txt" ]]
    assert_exit_zero $? "sample file should be copied"

    # Check strategy file has proper headers
    local content
    content=$(cat "$strat_file")
    assert_contains "$content" "## Name: test-tool-scaffold" "should have Name header"
    assert_contains "$content" "## Version: 1.0" "should have Version header"
    assert_contains "$content" "## Priority: 50" "should have Priority header"
    assert_contains "$content" "## Sample:" "should have Sample header"
    assert_contains "$content" "strategy_detect" "should have strategy_detect stub"
    assert_contains "$content" "strategy_extract" "should have strategy_extract stub"
}

test_new_strategy_force_overwrite () {
    printf "data\n" > "$TMPDIR_TEST/sample2.txt"
    # Should fail without --force
    local rc=0
    bash "$TOOLS_DIR/new_strategy.sh" --name test-tool-scaffold --category misc --sample "$TMPDIR_TEST/sample2.txt" 2>/dev/null || rc=$?
    assert_exit_nonzero "$rc" "should fail without --force on existing"

    # Should succeed with --force
    rc=0
    bash "$TOOLS_DIR/new_strategy.sh" --name test-tool-scaffold --category misc --sample "$TMPDIR_TEST/sample2.txt" --force 2>/dev/null || rc=$?
    assert_exit_zero "$rc" "should succeed with --force"
}

test_new_strategy_custom_priority () {
    printf "data\n" > "$TMPDIR_TEST/sample3.txt"
    bash "$TOOLS_DIR/new_strategy.sh" --name test-tool-scaffold --category misc --sample "$TMPDIR_TEST/sample3.txt" --priority 15 --force 2>/dev/null
    local extract_dir
    extract_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    local content
    content=$(cat "$extract_dir/strategies/misc/test-tool-scaffold.sh")
    assert_contains "$content" "## Priority: 15" "should have custom priority"
}

################################################################################
## review_strategy.sh tests
################################################################################

test_review_strategy_help () {
    local out
    out=$(bash "$TOOLS_DIR/review_strategy.sh" --help 2>&1)
    assert_contains "$out" "Strategy Review Tool" "help should show title"
    assert_contains "$out" "STRATEGY_NAME" "help should mention strategy name"
}

test_review_strategy_missing_args () {
    local rc=0
    bash "$TOOLS_DIR/review_strategy.sh" 2>/dev/null || rc=$?
    assert_exit_nonzero "$rc" "should fail without strategy name"
}

test_review_strategy_unknown_strategy () {
    local rc=0
    bash "$TOOLS_DIR/review_strategy.sh" nonexistent-strategy-xyz 2>/dev/null || rc=$?
    assert_exit_nonzero "$rc" "should fail with unknown strategy"
}

test_review_strategy_auto_mode () {
    local out
    out=$(bash "$TOOLS_DIR/review_strategy.sh" colons --auto 2>&1)
    assert_contains "$out" "Review Report" "should show review report"
    assert_contains "$out" "Strategy:  colons" "should show strategy name"
    assert_contains "$out" "Total:" "should show total fields"
}

test_review_strategy_csv_format () {
    local out
    out=$(bash "$TOOLS_DIR/review_strategy.sh" colons --auto --format csv 2>&1)
    assert_contains "$out" "strategy,sample,total_fields" "should show CSV header"
    assert_contains "$out" "colons," "should show strategy in CSV row"
}

test_review_strategy_custom_sample () {
    printf "Host: example.com\nContent-Type: text/html\n" > "$TMPDIR_TEST/custom_sample.txt"
    local out
    out=$(bash "$TOOLS_DIR/review_strategy.sh" colons --auto --sample "$TMPDIR_TEST/custom_sample.txt" 2>&1)
    assert_contains "$out" "Review Report" "should show review report with custom sample"
}

################################################################################
## Run tests
################################################################################

echo "=== EnvoyExtract Tools Tests ==="

run_test "new_strategy.sh --help" test_new_strategy_help
run_test "new_strategy.sh missing args" test_new_strategy_missing_args
run_test "new_strategy.sh missing sample file" test_new_strategy_missing_sample
run_test "new_strategy.sh invalid name" test_new_strategy_invalid_name
run_test "new_strategy.sh creates files" test_new_strategy_creates_files
run_test "new_strategy.sh --force overwrite" test_new_strategy_force_overwrite
run_test "new_strategy.sh custom priority" test_new_strategy_custom_priority
run_test "review_strategy.sh --help" test_review_strategy_help
run_test "review_strategy.sh missing args" test_review_strategy_missing_args
run_test "review_strategy.sh unknown strategy" test_review_strategy_unknown_strategy
run_test "review_strategy.sh auto mode" test_review_strategy_auto_mode
run_test "review_strategy.sh CSV format" test_review_strategy_csv_format
run_test "review_strategy.sh custom sample" test_review_strategy_custom_sample

print_summary
