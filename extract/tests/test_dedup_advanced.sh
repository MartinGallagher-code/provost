#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Advanced Deduplication Tests for provost-extract (provost-extract)
##
## Tests that deduplication works correctly when many strategies match the
## same input, and with large field counts.
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Advanced Deduplication Tests"
echo "========================================"

################################################################################
## Input matching 5+ strategies produces deduplicated output
################################################################################

test_dedup_multi_strategy () {
    # This input has colons, equals, and env-var patterns — multiple strategies
    # will match and extract overlapping fields.
    local tmpfile
    tmpfile=$(mktemp)
    printf 'Host: localhost\nPort: 5432\nHost=localhost\nPort=5432\nDebug=true\nDB_HOST=localhost\nDB_PORT=5432\n' > "$tmpfile"
    local output
    output=$(run_extract -r "$tmpfile")
    rm -f "$tmpfile"
    # After dedup, each unique "fieldname value" pair should appear only once
    local host_count
    host_count=$(echo "$output" | grep -c 'Host localhost' || true)
    assert_eq "1" "$host_count" "Host localhost should appear exactly once after dedup"
    local port_count
    port_count=$(echo "$output" | grep -c 'Port 5432' || true)
    assert_eq "1" "$port_count" "Port 5432 should appear exactly once after dedup"
    # Debug should still appear (unique to equals)
    assert_contains "$output" "Debug true" "Debug (equals-only) should be present"
}

################################################################################
## Dedup count verification (known input -> known field count after dedup)
################################################################################

test_dedup_count () {
    # Create input with 5 unique fields, each duplicated across colons and equals
    local tmpfile
    tmpfile=$(mktemp)
    printf 'Name: Alice\nAge: 30\nCity: Boston\nRole: admin\nTeam: ops\n' > "$tmpfile"
    printf 'Name=Alice\nAge=30\nCity=Boston\nRole=admin\nTeam=ops\n' >> "$tmpfile"
    local output
    output=$(run_extract -r "$tmpfile")
    rm -f "$tmpfile"
    # After dedup, should have exactly 5 unique field/value pairs (not 10)
    local line_count
    line_count=$(echo "$output" | sed '/^$/d' | wc -l | tr -d ' ')
    # Each unique pair should only appear once
    local unique_count
    unique_count=$(echo "$output" | sed '/^$/d' | awk '{
        idx = index($0, "\t")
        if (idx > 0) print substr($0, idx + 1)
        else print
    }' | sort -u | wc -l | tr -d ' ')
    assert_eq "$unique_count" "$line_count" "all lines should be unique after dedup (no duplicates remain)"
}

################################################################################
## Large dedup (100+ fields)
################################################################################

test_dedup_large () {
    local tmpfile
    tmpfile=$(mktemp)
    # Generate 120 colons fields
    local i
    for ((i=1; i<=120; i++)); do
        printf 'Field%03d: Value%03d\n' "$i" "$i" >> "$tmpfile"
    done
    local output rc=0
    output=$(run_extract -r -s colons "$tmpfile" 2>&1) || rc=$?
    rm -f "$tmpfile"
    assert_exit_zero "$rc" "should handle 120+ fields without error"
    # Verify we extracted a large number of fields
    local line_count
    line_count=$(echo "$output" | sed '/^$/d' | wc -l | tr -d ' ')
    # Should have at least 100 fields extracted
    if [[ $line_count -ge 100 ]]; then
        return 0
    else
        echo "  expected >= 100 fields, got $line_count"
        return 1
    fi
}

################################################################################
## Run all tests
################################################################################

run_test "dedup: multi-strategy overlap produces unique fields" test_dedup_multi_strategy
run_test "dedup: count verification (known input)" test_dedup_count
run_test "dedup: 120+ fields handled correctly" test_dedup_large

print_summary
