#!/bin/bash
################################################################################
## Tests for: streaming multi-line records (ENV-019)
##
## Exercises stream mode against inputs where records span multiple lines:
## multi-line JSON objects, stack traces, multi-line SQL. Uses --record-boundary
## to opt into multi-line record assembly.
################################################################################
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo "=== Streaming Multi-Line Record Tests (ENV-019) ==="

# Multi-line JSON objects, 2 records.
test_multiline_json_via_record_boundary () {
    local input='{
  "user": "alice",
  "action": "login"
}
{
  "user": "bob",
  "action": "logout"
}'
    local out
    # Use opening brace at column 0 as the record boundary.
    out=$(printf '%s\n' "$input" | run_mfe stream --strategy json --record-boundary '^\{$')
    # Expect 2 JSON-Lines output records
    local count
    count=$(echo "$out" | grep -c '"user"' || echo 0)
    [[ "$count" -eq 2 ]] || { echo "  ASSERT FAILED: expected 2 records, got $count (out=$out)"; return 1; }
    # Both users present
    assert_contains "$out" "alice" "alice should appear in streamed output"
    assert_contains "$out" "bob" "bob should appear in streamed output"
}

# Without --record-boundary, multi-line JSON degrades to line-per-record.
# Each line is passed to strategy_extract separately, so the output is
# garbled for multi-line objects — that's the motivation for ENV-019. This
# test just pins that the invocation still produces *some* valid JSON Lines
# output and does not crash, so callers don't rely on accidental behavior.
test_multiline_json_without_boundary_emits_something () {
    local input='{
  "user": "alice"
}'
    local out rc=0
    out=$(printf '%s\n' "$input" | run_mfe stream --strategy json 2>&1) || rc=$?
    [[ "$rc" -eq 0 ]] || { echo "  ASSERT FAILED: stream mode should exit 0"; return 1; }
    # Output should contain at least one JSON Lines record (one `{`)
    local lines
    lines=$(echo "$out" | grep -c '^{' || echo 0)
    [[ "$lines" -ge 1 ]] || { echo "  ASSERT FAILED: expected at least one JSON-Lines row, got $lines"; return 1; }
}

# Single-record pipeline should still work cleanly when --record-boundary does not match.
test_single_record_with_unused_boundary () {
    local input='{"user":"carol","action":"login"}'
    local out
    out=$(printf '%s\n' "$input" | run_mfe stream --strategy json --record-boundary '^NOT_PRESENT$')
    assert_contains "$out" "carol" "single-line record should still be processed"
}

# Flush-on-EOF: a record without a trailing boundary should still be emitted.
test_record_flushed_on_eof () {
    local input='{
  "user": "dave"
}'
    local out
    out=$(printf '%s\n' "$input" | run_mfe stream --strategy json --record-boundary '^\{$')
    assert_contains "$out" "dave" "EOF should flush the buffered record"
}

run_test "multi-line JSON via --record-boundary emits 2 records" test_multiline_json_via_record_boundary
run_test "default stream mode emits valid output (no crash regression)" test_multiline_json_without_boundary_emits_something
run_test "single-record input with unused boundary still works" test_single_record_with_unused_boundary
run_test "buffered record at EOF is flushed" test_record_flushed_on_eof

print_summary
