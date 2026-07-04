#!/bin/bash
################################################################################
## Chain Data Flow Verification Tests
##
## Verify that --chain actually transforms data between strategies,
## not just that it doesn't crash.
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Chain Data Flow Tests"
echo "========================================"

# --- Test 1: colons|equals verifiable transform ---

test_chain_colons_to_equals () {
    # Stage 1 (colons): extracts "Format KEY=val1" and "Type NAME=val2"
    # Chain strips field names, passes "KEY=val1" and "NAME=val2" to stage 2
    # Stage 2 (equals): re-extracts as "KEY val1" and "NAME val2"
    local tmpfile output
    tmpfile=$(mktemp)
    printf 'Format: KEY=val1\nType: NAME=val2\n' > "$tmpfile"
    output=$(run_mfe --chain 'colons|equals' -r "$tmpfile")
    rm -f "$tmpfile"
    assert_contains "$output" "KEY val1" "chain should extract KEY from colons values via equals"
    assert_contains "$output" "NAME val2" "chain should extract NAME from colons values via equals"
    assert_contains "$output" "STRAT-chain" "output should have STRAT-chain label"
}

# --- Test 2: chain + --rename applied to final output ---

test_chain_with_rename () {
    local tmpfile output
    tmpfile=$(mktemp)
    printf 'Host: localhost\nPort: 5432\n' > "$tmpfile"
    output=$(run_mfe --chain 'colons' --rename 'Host=Server' -r "$tmpfile")
    rm -f "$tmpfile"
    assert_contains "$output" "Server localhost" "rename should apply to chain output"
    assert_not_contains "$output" "Host localhost" "original name should be replaced"
}

# --- Test 3: chain + --sort applied to final output ---

test_chain_with_sort () {
    local tmpfile output
    tmpfile=$(mktemp)
    printf 'Zebra: last\nAlpha: first\n' > "$tmpfile"
    output=$(run_mfe --chain 'colons' --sort -r "$tmpfile")
    rm -f "$tmpfile"
    # After sort, Alpha should come before Zebra
    local alpha_pos zebra_pos
    alpha_pos=$(echo "$output" | grep -n "Alpha" | head -1 | cut -d: -f1)
    zebra_pos=$(echo "$output" | grep -n "Zebra" | head -1 | cut -d: -f1)
    assert_contains "$output" "Alpha first" "chain+sort should include Alpha"
    assert_contains "$output" "Zebra last" "chain+sort should include Zebra"
    if [[ -n "$alpha_pos" && -n "$zebra_pos" && "$alpha_pos" -lt "$zebra_pos" ]]; then
        assert_eq "ok" "ok" "Alpha should sort before Zebra in chain output"
    else
        assert_eq "Alpha<Zebra" "Alpha=$alpha_pos Zebra=$zebra_pos" "sort order incorrect"
    fi
}

# --- Test 4: chain + --aggregate on repeated values ---

test_chain_with_aggregate () {
    local tmpfile output
    tmpfile=$(mktemp)
    printf 'Score: 10\nScore: 20\nScore: 30\n' > "$tmpfile"
    output=$(run_mfe --chain 'colons' --aggregate -r "$tmpfile")
    rm -f "$tmpfile"
    assert_contains "$output" "Score_count 3" "chain+aggregate should compute count"
    assert_contains "$output" "Score_sum 60" "chain+aggregate should compute sum"
    assert_contains "$output" "Score_avg 20.00" "chain+aggregate should compute avg"
}

# --- Test 5: chain + --count on output ---

test_chain_with_count () {
    local tmpfile output
    tmpfile=$(mktemp)
    printf 'Host: localhost\nPort: 5432\n' > "$tmpfile"
    output=$(run_mfe --chain 'colons' --count "$tmpfile")
    rm -f "$tmpfile"
    assert_eq "$output" "2" "chain+count should count 2 fields"
}

# --- Register all tests ---

run_test "chain: colons|equals data flow" test_chain_colons_to_equals
run_test "chain: --rename on chain output" test_chain_with_rename
run_test "chain: --sort on chain output" test_chain_with_sort
run_test "chain: --aggregate on chain output" test_chain_with_aggregate
run_test "chain: --count on chain output" test_chain_with_count

print_summary
