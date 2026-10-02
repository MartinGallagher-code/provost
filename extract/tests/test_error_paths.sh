#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Error Path Tests for provost-extract
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Error Path Tests"
echo "========================================"

################################################################################
## 1. Missing file argument (no stdin, no file)
################################################################################

test_missing_file_argument () {
    local rc=0
    local output
    # When stdin is a tty, provost-extract reports "No input file provided"
    # Redirect /dev/null to stdin so -t 0 fails, triggering the stdin path
    # which then gets empty data — but to test the actual "no file" path,
    # we need stdin to be a tty. Use the /dev/null redirect to at least
    # confirm provost-extract exits non-zero and shows an error.
    output=$(run_extract 2>&1 </dev/null) || rc=$?
    assert_exit_nonzero "$rc" "should exit non-zero with no input"
    assert_contains "$output" "provost-extract: error:" "should show error message"
    assert_contains "$output" "No data received" "should mention no data received"
}

################################################################################
## 2. Non-existent file
################################################################################

test_nonexistent_file () {
    local rc=0
    local output
    output=$(run_extract /tmp/this_file_does_not_exist_mfe_test.txt 2>&1) || rc=$?
    assert_exit_nonzero "$rc" "should exit non-zero for missing file"
    assert_contains "$output" "provost-extract: error:" "should show error message"
    assert_contains "$output" "File not found" "should mention file not found"
}

################################################################################
## 3. Empty stdin
################################################################################

test_empty_stdin () {
    local rc=0
    local output
    output=$(echo "" | run_extract 2>&1) || rc=$?
    assert_exit_nonzero "$rc" "should exit non-zero for empty stdin"
    assert_contains "$output" "provost-extract: error:" "should show error message"
    assert_contains "$output" "No data received" "should mention no data"
}

################################################################################
## 4. Invalid --format value
################################################################################

test_invalid_format () {
    local rc=0
    local output
    output=$(run_extract --format bogusformat "$SAMPLES_DIR/colons/basic.txt" 2>&1) || rc=$?
    assert_exit_nonzero "$rc" "should exit non-zero for invalid format"
    assert_contains "$output" "provost-extract: error:" "should show error message"
    assert_contains "$output" "Unknown format" "should mention unknown format"
}

################################################################################
## 5. Invalid --min-confidence (non-numeric)
################################################################################

test_invalid_min_confidence () {
    local rc=0
    local output
    output=$(run_extract --min-confidence abc "$SAMPLES_DIR/colons/basic.txt" 2>&1) || rc=$?
    assert_exit_nonzero "$rc" "should exit non-zero for non-numeric min-confidence"
    assert_contains "$output" "provost-extract: error:" "should show error message"
    assert_contains "$output" "--min-confidence" "should mention the flag"
}

################################################################################
## 6. Invalid --max-strategies (non-numeric)
################################################################################

test_invalid_max_strategies () {
    local rc=0
    local output
    output=$(run_extract --max-strategies xyz "$SAMPLES_DIR/colons/basic.txt" 2>&1) || rc=$?
    assert_exit_nonzero "$rc" "should exit non-zero for non-numeric max-strategies"
    assert_contains "$output" "provost-extract: error:" "should show error message"
    assert_contains "$output" "--max-strategies" "should mention the flag"
}

################################################################################
## 7. --stream without --strategy
################################################################################

test_stream_without_strategy () {
    local rc=0
    local output
    output=$(echo "test" | run_extract --stream 2>&1) || rc=$?
    assert_exit_nonzero "$rc" "should exit non-zero for --stream without --strategy"
    assert_contains "$output" "provost-extract: error:" "should show error message"
    assert_contains "$output" "--stream requires --strategy" "should mention stream requires strategy"
}

################################################################################
## 8. --stream with file argument
################################################################################

test_stream_with_file () {
    local rc=0
    local output
    output=$(run_extract --stream --strategy colons "$SAMPLES_DIR/colons/basic.txt" 2>&1) || rc=$?
    assert_exit_nonzero "$rc" "should exit non-zero for --stream with file"
    assert_contains "$output" "provost-extract: error:" "should show error message"
    assert_contains "$output" "--stream reads from stdin" "should mention stream stdin only"
}

################################################################################
## 9. --chain with non-existent strategy
################################################################################

test_chain_nonexistent_strategy () {
    local rc=0
    local output
    output=$(run_extract --chain 'nonexistent_xyz_strategy' "$SAMPLES_DIR/colons/basic.txt" 2>&1) || rc=$?
    assert_exit_nonzero "$rc" "should exit non-zero for chain with missing strategy"
    assert_contains "$output" "provost-extract: error:" "should show error message"
    assert_contains "$output" "Strategy not found" "should mention strategy not found"
}

################################################################################
## 10. Unknown option
################################################################################

test_unknown_option () {
    local rc=0
    local output
    output=$(run_extract --bogus "$SAMPLES_DIR/colons/basic.txt" 2>&1) || rc=$?
    assert_exit_nonzero "$rc" "should exit non-zero for unknown option"
    assert_contains "$output" "provost-extract: error:" "should show error message"
    assert_contains "$output" "Unknown option" "should mention unknown option"
}

################################################################################
## 11. --strategy with non-existent name
################################################################################

test_strategy_nonexistent () {
    local rc=0
    local output
    output=$(run_extract --strategy nonexistent_xyz_strategy "$SAMPLES_DIR/colons/basic.txt" 2>&1) || rc=$?
    assert_exit_nonzero "$rc" "should exit non-zero for missing strategy"
    assert_contains "$output" "provost-extract: error:" "should show error message"
    assert_contains "$output" "Strategy not found" "should mention strategy not found"
}

################################################################################
## 12. --stream + --chain conflict
################################################################################

test_stream_chain_conflict () {
    local rc=0
    local output
    output=$(echo "test" | run_extract --stream --strategy colons --chain 'colons' 2>&1) || rc=$?
    assert_exit_nonzero "$rc" "should exit non-zero for --stream + --chain"
    assert_contains "$output" "provost-extract: error:" "should show error message"
    assert_contains "$output" "--stream and --chain cannot be used together" "should mention conflict"
}

################################################################################
## 13. --count + --names conflict
################################################################################

test_count_names_conflict () {
    local rc=0
    local output
    output=$(run_extract --count --names "$SAMPLES_DIR/colons/basic.txt" 2>&1) || rc=$?
    assert_exit_nonzero "$rc" "should exit non-zero for --count + --names"
    assert_contains "$output" "provost-extract: error:" "should show error message"
    assert_contains "$output" "--count and --names cannot be used together" "should mention conflict"
}

################################################################################
## 14. --quiet + --verbose conflict
################################################################################

test_quiet_verbose_conflict () {
    local rc=0
    local output
    output=$(run_extract --quiet --verbose "$SAMPLES_DIR/colons/basic.txt" 2>&1) || rc=$?
    assert_exit_nonzero "$rc" "should exit non-zero for --quiet + --verbose"
    assert_contains "$output" "provost-extract: error:" "should show error message"
    assert_contains "$output" "--quiet and --verbose cannot be used together" "should mention conflict"
}

################################################################################
## 15. --no-dedup produces duplicates
################################################################################

test_no_dedup () {
    local tmpfile
    tmpfile=$(mktemp)
    # Write data that both colons and equals strategies can match
    printf "hostname: server01\nhostname=server01\n" > "$tmpfile"

    # With --no-dedup -r, both strategies should produce duplicate hostname fields
    local output_dup
    output_dup=$(run_extract --no-dedup -r "$tmpfile")
    local dup_count
    dup_count=$(echo "$output_dup" | grep -c "hostname" || true)

    # Without --no-dedup, deduplication should collapse duplicates
    local output_dedup
    output_dedup=$(run_extract -r "$tmpfile")
    local dedup_count
    dedup_count=$(echo "$output_dedup" | grep -c "hostname" || true)

    rm -f "$tmpfile"

    # With no-dedup, there should be more hostname occurrences than with dedup
    assert_contains "$output_dup" "hostname" "no-dedup output should contain hostname"
    assert_contains "$output_dedup" "hostname" "dedup output should contain hostname"
    if [[ "$dup_count" -gt "$dedup_count" ]]; then
        return 0
    else
        echo "  ASSERT FAILED: --no-dedup should produce more duplicates"
        echo "    no-dedup count: $dup_count"
        echo "    dedup count:    $dedup_count"
        return 1
    fi
}

################################################################################
## 16. --output FILE writes to file
################################################################################

test_output_file () {
    local tmpdir
    tmpdir=$(mktemp -d)
    local outfile="$tmpdir/provost_output.txt"

    local rc=0
    run_extract --output "$outfile" -s colons "$SAMPLES_DIR/colons/basic.txt" >/dev/null 2>&1 || rc=$?

    assert_exit_zero "$rc" "should succeed writing to output file"

    if [[ ! -f "$outfile" ]]; then
        echo "  ASSERT FAILED: output file should exist"
        echo "    file: $outfile"
        rm -rf "$tmpdir"
        return 1
    fi

    local content
    content=$(<"$outfile")
    assert_contains "$content" "Name" "output file should contain extracted field"

    rm -rf "$tmpdir"
}

################################################################################
## 17. --profile shows timing on stderr
################################################################################

test_profile_stderr () {
    local output
    output=$(run_extract --profile -s colons "$SAMPLES_DIR/colons/basic.txt" 2>&1)
    assert_contains "$output" "[profile]" "should show profile timing on stderr"
}

################################################################################
## 18. Binary file detection
################################################################################

test_binary_file_detection () {
    local tmpfile
    tmpfile=$(mktemp)
    printf 'aaa\x00\x00\x00bbb\n' > "$tmpfile"

    local output
    output=$(run_extract "$tmpfile" 2>&1)
    rm -f "$tmpfile"

    assert_contains "$output" "binary" "should warn about binary file"
}

################################################################################
## Run all tests
################################################################################

run_test "error: missing file argument" test_missing_file_argument
run_test "error: non-existent file" test_nonexistent_file
run_test "error: empty stdin" test_empty_stdin
run_test "error: invalid --format value" test_invalid_format
run_test "error: invalid --min-confidence (non-numeric)" test_invalid_min_confidence
run_test "error: invalid --max-strategies (non-numeric)" test_invalid_max_strategies
run_test "error: --stream without --strategy" test_stream_without_strategy
run_test "error: --stream with file argument" test_stream_with_file
run_test "error: --chain with non-existent strategy" test_chain_nonexistent_strategy
run_test "error: unknown option" test_unknown_option
run_test "error: --strategy with non-existent name" test_strategy_nonexistent
run_test "error: --stream + --chain conflict" test_stream_chain_conflict
run_test "error: --count + --names conflict" test_count_names_conflict
run_test "error: --quiet + --verbose conflict" test_quiet_verbose_conflict
run_test "feature: --no-dedup produces duplicates" test_no_dedup
run_test "feature: --output writes to file" test_output_file
run_test "feature: --profile shows timing on stderr" test_profile_stderr
run_test "error: binary file detection" test_binary_file_detection

print_summary
