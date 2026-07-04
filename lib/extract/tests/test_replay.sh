#!/bin/bash
################################################################################
## Replay Tests for Envoy:Explore (envoy-extract)
##
## Tests the --replay flag and -c (command line export) round-tripping
## including error handling for malformed and empty replay specs.
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Replay Tests"
echo "========================================"

################################################################################
## Non-existent strategy in replay spec
################################################################################

test_replay_nonexistent_strategy () {
    # Replaying a strategy that doesn't exist should produce no output (exits 0)
    # because the strategy loop simply skips it when it's not in the sorted list.
    local output rc=0
    output=$(run_mfe -r --replay 'nonexistent_strategy@1.0' "$SAMPLES_DIR/json/basic.json" 2>&1) || rc=$?
    # Should not crash; exit 0 with no output is acceptable
    if [[ $rc -le 1 ]]; then
        return 0
    else
        echo "  exit code was $rc (expected 0 or 1)"
        return 1
    fi
}

################################################################################
## Malformed spec (no @version)
################################################################################

test_replay_malformed_no_version () {
    # A replay spec without @version should still work; the sed strips @...
    # leaving just the strategy name which gets matched in the loop.
    local output rc=0
    output=$(run_mfe -r --replay 'json' "$SAMPLES_DIR/json/basic.json" 2>&1) || rc=$?
    assert_exit_zero "$rc" "replay without @version should not crash"
    # The strategy name 'json' should still be recognized
    assert_contains "$output" "STRAT-json" "should still run the json strategy"
}

################################################################################
## Empty spec
################################################################################

test_replay_empty_spec () {
    local output rc=0
    output=$(run_mfe --replay '' "$SAMPLES_DIR/json/basic.json" 2>&1) || rc=$?
    # Empty spec means no strategies match the replay filter; should exit cleanly
    if [[ $rc -le 1 ]]; then
        return 0
    else
        echo "  exit code was $rc (expected 0 or 1)"
        return 1
    fi
}

################################################################################
## Round-trip -c -> --replay identity
################################################################################

test_replay_roundtrip () {
    # Run once with -c to get the export command
    local cmd_output
    cmd_output=$(run_mfe -c -s colons "$SAMPLES_DIR/colons/basic.txt")
    # Extract the replay spec — third whitespace-separated token after
    # `mfe --replay`.  ENV-182 dropped the legacy single-quotes in favour
    # of printf %q, which leaves single-token specs like `colons@1.0`
    # unquoted; the old sed pattern relied on the quotes and silently
    # passed the entire cmdline through as the "spec".
    local spec
    spec=$(awk '{print $3}' <<<"$cmd_output")
    # Run original extraction with raw output
    local original
    original=$(run_mfe -r -s colons "$SAMPLES_DIR/colons/basic.txt")
    # Run replay with same spec
    local replay_output
    replay_output=$(run_mfe -r --replay "$spec" "$SAMPLES_DIR/colons/basic.txt")
    # Both should extract the same field names
    local orig_fields replay_fields
    orig_fields=$(echo "$original" | sed '/^$/d' | awk '{
        idx = index($0, "\t")
        if (idx > 0) print substr($0, idx + 1)
        else print
    }' | sort)
    replay_fields=$(echo "$replay_output" | sed '/^$/d' | awk '{
        idx = index($0, "\t")
        if (idx > 0) print substr($0, idx + 1)
        else print
    }' | sort)
    assert_eq "$orig_fields" "$replay_fields" "replay should produce same fields as original"
}

################################################################################
## Replay version enforcement
################################################################################

test_replay_matching_version () {
    # Replay with the correct version should produce no warning
    local output rc=0
    output=$(run_mfe -r --replay 'json@1.0' "$SAMPLES_DIR/json/basic.json" 2>&1) || rc=$?
    # Should NOT contain version mismatch warning
    if [[ "$output" == *"version mismatch"* ]]; then
        echo "  unexpected version mismatch warning"
        return 1
    fi
    return 0
}

test_replay_mismatched_version () {
    # Replay with a wrong version should warn on stderr
    local output rc=0
    output=$(run_mfe -r --replay 'json@9.9' "$SAMPLES_DIR/json/basic.json" 2>&1) || rc=$?
    assert_contains "$output" "version mismatch" "should warn about version mismatch"
    assert_contains "$output" "requested: 9.9" "should show requested version"
    assert_contains "$output" "installed: 1.0" "should show installed version"
}

test_replay_no_version_in_spec () {
    # Replay without version should produce no warning
    local output rc=0
    output=$(run_mfe -r --replay 'json' "$SAMPLES_DIR/json/basic.json" 2>&1) || rc=$?
    if [[ "$output" == *"version mismatch"* ]]; then
        echo "  unexpected version mismatch warning"
        return 1
    fi
    return 0
}

################################################################################
## Run all tests
################################################################################

run_test "replay: non-existent strategy in spec" test_replay_nonexistent_strategy
run_test "replay: malformed spec without @version" test_replay_malformed_no_version
run_test "replay: empty spec" test_replay_empty_spec
run_test "replay: round-trip -c -> --replay identity" test_replay_roundtrip
run_test "replay: matching version (no warning)" test_replay_matching_version
run_test "replay: mismatched version (warning)" test_replay_mismatched_version
run_test "replay: no version in spec (no warning)" test_replay_no_version_in_spec

print_summary
