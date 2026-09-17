#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Batch Mode Tests
##
## Tests for --batch flag: process multiple files in one envoy-extract invocation,
## outputting one JSON Lines record per file.
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

MFE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo ""
echo "========================================"
echo "Batch Mode Tests"
echo "========================================"

# ---------------------------------------------------------------------------
# Basic: single file produces a JSON Lines record with correct structure
# ---------------------------------------------------------------------------

test_batch_single_file () {
    local tmpfile output
    tmpfile=$(mktemp --suffix=.json)
    printf '{"name": "project", "version": "1.0"}\n' > "$tmpfile"
    output=$(echo "$tmpfile" | run_mfe --batch)
    rm -f "$tmpfile"
    assert_contains "$output" '"file"' "batch: output should contain file key"
    assert_contains "$output" '"fields"' "batch: output should contain fields key"
    assert_contains "$output" '"name"' "batch: output should contain extracted field name"
}

# ---------------------------------------------------------------------------
# Two files: produces two JSON Lines records
# ---------------------------------------------------------------------------

test_batch_two_files () {
    local tmp1 tmp2 output line_count
    tmp1=$(mktemp --suffix=.json)
    tmp2=$(mktemp --suffix=.json)
    printf '{"host": "server1"}\n' > "$tmp1"
    printf '{"host": "server2"}\n' > "$tmp2"
    output=$(printf '%s\n%s\n' "$tmp1" "$tmp2" | run_mfe --batch)
    rm -f "$tmp1" "$tmp2"
    assert_line_count "$output" 2 "batch: two input files should produce two output records"
}

# ---------------------------------------------------------------------------
# File path is echoed correctly in the output record
# ---------------------------------------------------------------------------

test_batch_file_path_in_output () {
    local tmpfile output
    tmpfile=$(mktemp --suffix=.json)
    printf '{"key": "val"}\n' > "$tmpfile"
    output=$(echo "$tmpfile" | run_mfe --batch)
    rm -f "$tmpfile"
    assert_contains "$output" "$tmpfile" "batch: output should include the input file path"
}

# ---------------------------------------------------------------------------
# Empty fields: file with no extractable content yields {"file":..., "fields":{}}
# ---------------------------------------------------------------------------

test_batch_empty_fields () {
    local tmpfile output
    tmpfile=$(mktemp)
    printf 'no extractable content here\n' > "$tmpfile"
    output=$(echo "$tmpfile" | run_mfe --batch 2>/dev/null)
    rm -f "$tmpfile"
    # Record should still be emitted (with empty fields)
    assert_contains "$output" '"file"' "batch: record emitted even for no-field input"
    assert_contains "$output" '"fields": {}' "batch: empty fields yields {}"
}

# ---------------------------------------------------------------------------
# Missing file: warning to stderr, no output record for that file
# ---------------------------------------------------------------------------

test_batch_missing_file () {
    local output stderr_out
    output=$(echo "/nonexistent/path/file.json" | run_mfe --batch 2>${TMPDIR:-/tmp}/batch_stderr_test)
    stderr_out=$(cat ${TMPDIR:-/tmp}/batch_stderr_test)
    rm -f ${TMPDIR:-/tmp}/batch_stderr_test
    assert_not_contains "$output" '"file"' "batch: missing file should not produce output record"
    assert_contains "$stderr_out" "not found" "batch: missing file should warn on stderr"
}

# ---------------------------------------------------------------------------
# Empty stdin: warning, no output
# ---------------------------------------------------------------------------

test_batch_empty_stdin () {
    local output stderr_out
    output=$(echo "" | run_mfe --batch 2>${TMPDIR:-/tmp}/batch_empty_stderr)
    stderr_out=$(cat ${TMPDIR:-/tmp}/batch_empty_stderr)
    rm -f ${TMPDIR:-/tmp}/batch_empty_stderr
    assert_contains "$stderr_out" "no files processed" "batch: empty stdin should warn"
}

# ---------------------------------------------------------------------------
# Works with --strategy to limit extraction
# ---------------------------------------------------------------------------

test_batch_with_strategy () {
    local tmpfile output
    tmpfile=$(mktemp --suffix=.json)
    printf '{"name": "alpha", "count": 5}\n' > "$tmpfile"
    output=$(echo "$tmpfile" | run_mfe --batch --strategy json)
    rm -f "$tmpfile"
    assert_contains "$output" '"name"' "batch --strategy: should extract name field"
    assert_contains "$output" '"count"' "batch --strategy: should extract count field"
}

# ---------------------------------------------------------------------------
# Works with --rename to rename fields in output
# ---------------------------------------------------------------------------

test_batch_with_rename () {
    local tmpfile output
    tmpfile=$(mktemp --suffix=.json)
    printf '{"name": "alpha"}\n' > "$tmpfile"
    output=$(echo "$tmpfile" | run_mfe --batch --rename "name=project_name")
    rm -f "$tmpfile"
    assert_contains "$output" "project_name" "batch --rename: field should be renamed"
    assert_not_contains "$output" '"name"' "batch --rename: original name should not appear"
}

# ---------------------------------------------------------------------------
# Works with --no-dedup
# ---------------------------------------------------------------------------

test_batch_with_no_dedup () {
    local tmpfile output
    tmpfile=$(mktemp --suffix=.json)
    printf '{"key": "val1"}\n' > "$tmpfile"
    output=$(echo "$tmpfile" | run_mfe --batch --no-dedup)
    rm -f "$tmpfile"
    assert_contains "$output" '"file"' "batch --no-dedup: should still produce output"
}

# ---------------------------------------------------------------------------
# Blank lines in stdin are ignored
# ---------------------------------------------------------------------------

test_batch_blank_lines_ignored () {
    local tmpfile output
    tmpfile=$(mktemp --suffix=.json)
    printf '{"host": "server"}\n' > "$tmpfile"
    output=$(printf '\n%s\n\n' "$tmpfile" | run_mfe --batch)
    rm -f "$tmpfile"
    # Should produce exactly one record
    assert_line_count "$output" 1 "batch: blank lines in stdin should be skipped"
}

# ---------------------------------------------------------------------------
# Conflict: --batch and --stream cannot be used together
# ---------------------------------------------------------------------------

test_batch_conflict_stream () {
    local exit_code stderr_out
    stderr_out=$(echo "" | run_mfe --batch --stream --strategy colons 2>&1 >/dev/null || true)
    assert_contains "$stderr_out" "cannot be used together" "batch+stream: should error with conflict message"
}

# ---------------------------------------------------------------------------
# Conflict: --batch and --chain cannot be used together
# ---------------------------------------------------------------------------

test_batch_conflict_chain () {
    local stderr_out
    stderr_out=$(echo "" | run_mfe --batch --chain 'colons|json' 2>&1 >/dev/null || true)
    assert_contains "$stderr_out" "cannot be used together" "batch+chain: should error with conflict message"
}

# ---------------------------------------------------------------------------
# Conflict: --batch and --replay cannot be used together
# ---------------------------------------------------------------------------

test_batch_conflict_replay () {
    local stderr_out
    stderr_out=$(echo "" | run_mfe --batch --replay 'json@1.0' 2>&1 >/dev/null || true)
    assert_contains "$stderr_out" "cannot be used together" "batch+replay: should error with conflict message"
}

# ---------------------------------------------------------------------------
# Conflict: --batch and --interactive cannot be used together
# ---------------------------------------------------------------------------

test_batch_conflict_interactive () {
    local stderr_out
    stderr_out=$(echo "" | run_mfe --batch --interactive 2>&1 >/dev/null || true)
    assert_contains "$stderr_out" "cannot be used together" "batch+interactive: should error with conflict message"
}

# ---------------------------------------------------------------------------
# Conflict: --batch with a FILE argument should error
# ---------------------------------------------------------------------------

test_batch_conflict_file_argument () {
    local tmpfile stderr_out
    tmpfile=$(mktemp --suffix=.json)
    printf '{"key": "val"}\n' > "$tmpfile"
    stderr_out=$(echo "" | run_mfe --batch "$tmpfile" 2>&1 >/dev/null || true)
    rm -f "$tmpfile"
    assert_contains "$stderr_out" "do not specify a FILE" "batch+file: should error when FILE arg given"
}

# ---------------------------------------------------------------------------
# Output goes to --output file
# ---------------------------------------------------------------------------

test_batch_output_to_file () {
    local tmpfile outfile output
    tmpfile=$(mktemp --suffix=.json)
    outfile=$(mktemp)
    printf '{"name": "test"}\n' > "$tmpfile"
    echo "$tmpfile" | run_mfe --batch --output "$outfile" >/dev/null
    output=$(cat "$outfile")
    rm -f "$tmpfile" "$outfile"
    assert_contains "$output" '"file"' "batch --output: output file should contain JSON Lines"
    assert_contains "$output" '"name"' "batch --output: output file should contain extracted fields"
}

# ---------------------------------------------------------------------------
# Multiple files with mixed hit/miss: each gets its own record
# ---------------------------------------------------------------------------

test_batch_mixed_content () {
    local tmp1 tmp2 output line_count
    tmp1=$(mktemp --suffix=.json)
    tmp2=$(mktemp)
    printf '{"host": "server1", "port": "80"}\n' > "$tmp1"
    printf 'no fields here\n' > "$tmp2"
    output=$(printf '%s\n%s\n' "$tmp1" "$tmp2" | run_mfe --batch 2>/dev/null)
    rm -f "$tmp1" "$tmp2"
    # Both files should produce records (one with fields, one empty)
    assert_line_count "$output" 2 "batch: both files should produce records regardless of field count"
}

# ---------------------------------------------------------------------------
# Run all tests
# ---------------------------------------------------------------------------

run_test "batch: single file produces JSON Lines record"          test_batch_single_file
run_test "batch: two files produce two records"                   test_batch_two_files
run_test "batch: file path appears in output record"              test_batch_file_path_in_output
run_test "batch: no-field file yields empty fields object"        test_batch_empty_fields
run_test "batch: missing file warns and skips"                    test_batch_missing_file
run_test "batch: empty stdin produces warning"                    test_batch_empty_stdin
run_test "batch: works with --strategy"                          test_batch_with_strategy
run_test "batch: works with --rename"                            test_batch_with_rename
run_test "batch: works with --no-dedup"                          test_batch_with_no_dedup
run_test "batch: blank lines in stdin ignored"                    test_batch_blank_lines_ignored
run_test "batch: conflicts with --stream"                        test_batch_conflict_stream
run_test "batch: conflicts with --chain"                         test_batch_conflict_chain
run_test "batch: conflicts with --replay"                        test_batch_conflict_replay
run_test "batch: conflicts with --interactive"                   test_batch_conflict_interactive
run_test "batch: conflicts with FILE argument"                   test_batch_conflict_file_argument
run_test "batch: --output redirects to file"                     test_batch_output_to_file
run_test "batch: mixed content files all get records"            test_batch_mixed_content

print_summary
