#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## --emit-meta tests (ENV-200)
##
## Verify that a single extract run can surface the winning strategy + its
## confidence on stderr (so callers like `provost` avoid a second
## `explain` pass), while stdout still carries the normal extracted data.
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "--emit-meta Tests"
echo "========================================"

test_emit_meta_line_on_stderr () {
    local tmpfile meta
    tmpfile=$(mktemp)
    printf '{"a":1,"b":2}\n' > "$tmpfile"
    # stdout = data, stderr = meta line.
    meta=$(run_extract --emit-meta -f tsv --max-strategies 1 "$tmpfile" 2>&1 >/dev/null)
    rm -f "$tmpfile"
    assert_contains "$meta" "__EXTRACT_META__" "meta line is emitted to stderr"
    assert_contains "$meta" "json" "meta names the winning strategy"
}

test_emit_meta_keeps_stdout_data () {
    local tmpfile out
    tmpfile=$(mktemp)
    printf '{"a":1,"b":2}\n' > "$tmpfile"
    out=$(run_extract --emit-meta -f tsv --max-strategies 1 "$tmpfile" 2>/dev/null)
    rm -f "$tmpfile"
    assert_contains "$out" "a" "stdout still carries the extracted data"
    assert_not_contains "$out" "__EXTRACT_META__" "meta does not leak onto stdout"
}

test_emit_meta_absent_without_flag () {
    local tmpfile both
    tmpfile=$(mktemp)
    printf '{"a":1}\n' > "$tmpfile"
    both=$(run_extract -f tsv --max-strategies 1 "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_not_contains "$both" "__EXTRACT_META__" "no meta line without --emit-meta"
}

run_test "emit-meta line on stderr"        test_emit_meta_line_on_stderr
run_test "emit-meta keeps stdout data"     test_emit_meta_keeps_stdout_data
run_test "no meta without the flag"        test_emit_meta_absent_without_flag

print_summary
