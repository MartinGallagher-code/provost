#!/bin/bash
################################################################################
## Edge Case Tests for envoy-extract
##
## Tests for input size limits, boundary conditions, and error handling.
################################################################################

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

TMPDIR_E="${TMPDIR:-/tmp}/edge_cases_$$"
mkdir -p "$TMPDIR_E"

################################################################################
## Max input size guard
################################################################################

test_max_input_size_file_rejected () {
    # Create a file that exceeds a small max-input-size
    printf '%0.s.' {1..200} > "$TMPDIR_E/big.txt"
    local out rc=0
    out=$(run_mfe --max-input-size 100 "$TMPDIR_E/big.txt" 2>&1) || rc=$?
    assert_contains "$out" "too large" "should report file too large"
    [[ $rc -ne 0 ]] || { echo "expected non-zero exit"; return 1; }
}

test_max_input_size_file_accepted () {
    # Create a small file within limits
    echo '{"name": "test"}' > "$TMPDIR_E/small.json"
    local out rc=0
    out=$(run_mfe --max-input-size 1000 -s json "$TMPDIR_E/small.json" 2>&1) || rc=$?
    # Should succeed without error
    if [[ "$out" == *"too large"* ]]; then
        echo "  unexpected size rejection"
        return 1
    fi
    return 0
}

test_max_input_size_stdin_rejected () {
    # Pipe data that exceeds a small max-input-size
    local out rc=0
    out=$(printf '%0.s.' {1..200} | run_mfe --max-input-size 100 2>&1) || rc=$?
    assert_contains "$out" "too large" "should report stdin input too large"
    [[ $rc -ne 0 ]] || { echo "expected non-zero exit"; return 1; }
}

################################################################################
## Empty file (0 bytes)
################################################################################

test_empty_file () {
    local tmpfile
    tmpfile="$TMPDIR_E/empty.txt"
    : > "$tmpfile"
    local out rc=0
    out=$(run_mfe "$tmpfile" 2>&1) || rc=$?
    # Should not crash; exit 0 with a "No fields" message or exit 1 quietly
    if [[ $rc -le 1 ]]; then
        return 0
    else
        echo "  exit code was $rc (expected 0 or 1)"
        return 1
    fi
}

################################################################################
## Empty file: verify no spurious output on stdout
################################################################################

test_empty_file_no_spurious_output () {
    local tmpfile
    tmpfile="$TMPDIR_E/empty2.txt"
    : > "$tmpfile"
    local stdout_out
    stdout_out=$(run_mfe "$tmpfile" 2>/dev/null) || true
    # stdout should be empty (no extracted fields)
    assert_output_empty "$stdout_out" "empty file should produce no stdout output"
}

################################################################################
## Whitespace-only file
################################################################################

test_whitespace_only_file () {
    local tmpfile
    tmpfile="$TMPDIR_E/whitespace.txt"
    printf '   \n\t\t\n   \n\n' > "$tmpfile"
    local out rc=0
    out=$(run_mfe "$tmpfile" 2>&1) || rc=$?
    # Should not crash; whitespace-only input has no extractable fields
    if [[ $rc -le 1 ]]; then
        return 0
    else
        echo "  exit code was $rc (expected 0 or 1)"
        return 1
    fi
}

################################################################################
## Whitespace-only file: verify no spurious output on stdout
################################################################################

test_whitespace_only_no_spurious_output () {
    local tmpfile
    tmpfile="$TMPDIR_E/whitespace2.txt"
    printf '   \n\t\n  \n' > "$tmpfile"
    local stdout_out
    stdout_out=$(run_mfe "$tmpfile" 2>/dev/null) || true
    assert_output_empty "$stdout_out" "whitespace-only file should produce no stdout output"
}

################################################################################
## Very long single line (>64KB)
################################################################################

test_very_long_line () {
    local tmpfile
    tmpfile="$TMPDIR_E/longline.txt"
    # Create a line >64KB with key: value pattern
    printf 'Name: ' > "$tmpfile"
    # Append 70000 'A' characters as the value
    python3 -c "print('A' * 70000, end='')" >> "$tmpfile" 2>/dev/null || \
        perl -e "print 'A' x 70000" >> "$tmpfile" 2>/dev/null || \
        dd if=/dev/zero bs=1 count=70000 2>/dev/null | tr '\0' 'A' >> "$tmpfile"
    printf '\n' >> "$tmpfile"
    local out rc=0
    # Use specific strategy to avoid slow auto-discovery on huge input
    out=$(run_mfe -s colons "$tmpfile" 2>&1) || rc=$?
    # Should not crash or hang; exit code 0 or 1 is acceptable
    if [[ $rc -le 1 ]]; then
        return 0
    else
        echo "  exit code was $rc (expected 0 or 1)"
        return 1
    fi
}

################################################################################
## File with only one field
################################################################################

test_single_field_file () {
    local tmpfile
    tmpfile="$TMPDIR_E/single.txt"
    printf 'hostname: server01\n' > "$tmpfile"
    local out rc=0
    out=$(run_mfe -r -s colons "$tmpfile" 2>&1) || rc=$?
    assert_exit_zero "$rc" "single field file should succeed"
    assert_contains "$out" "hostname" "should extract the single field name"
    assert_contains "$out" "server01" "should extract the single field value"
}

################################################################################
## File with only one field: count should be 1
################################################################################

test_single_field_count () {
    local tmpfile
    tmpfile="$TMPDIR_E/single_count.txt"
    printf 'version: 2.0\n' > "$tmpfile"
    local out
    out=$(run_mfe --count -s colons "$tmpfile")
    assert_eq "$out" "1" "count for single-field file should be 1"
}

################################################################################
## Run all tests
################################################################################

echo "Edge Case Tests"
echo "================"

run_test "max-input-size: file rejected" test_max_input_size_file_rejected
run_test "max-input-size: file accepted" test_max_input_size_file_accepted
run_test "max-input-size: stdin rejected" test_max_input_size_stdin_rejected
run_test "edge: empty file (0 bytes) no crash" test_empty_file
run_test "edge: empty file no spurious stdout" test_empty_file_no_spurious_output
run_test "edge: whitespace-only file no crash" test_whitespace_only_file
run_test "edge: whitespace-only file no spurious stdout" test_whitespace_only_no_spurious_output
run_test "edge: very long single line >64KB" test_very_long_line
run_test "edge: single field extraction" test_single_field_file
run_test "edge: single field count" test_single_field_count

print_summary

# Cleanup
rm -rf "$TMPDIR_E"
