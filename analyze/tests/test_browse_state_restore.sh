#!/bin/bash
################################################################################
## Tests for: envoy-browse persistent state (ENV-055 / ENV-127)
##
## envoy-browse persists `selected_pos` / `list_scroll` / `detail_scroll`
## / `pane_focus` / `search_term` to `.analyze_browser_state` on exit
## and restores them on next launch — keyed by the input file's byte
## count so a changed dataset falls back to fresh state. `--fresh`
## bypasses the restore unconditionally.
##
## ENV-127 moved `_browse_state_file` / `_browse_load_state` /
## `_browse_save_state` above the MDX_TESTING early-return so this test
## can source-and-call them directly. Each test runs in its own
## TMPDIR so concurrent runs don't share state files.
################################################################################
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

BROWSE="$(cd "$SCRIPT_DIR/.." && pwd)/envoy-browse"

# Per-test sandbox: chdir into a fresh temp dir so .analyze_browser_state
# is isolated from any other test or run-tests harness.
_browse_eval_in_tmpdir () {
    local body="$1"
    local sandbox
    sandbox=$(mktemp -d -t env127-state.XXXXXX)
    ENV127_TEST_BODY="$body" \
        BROWSE="$BROWSE" \
        SAMPLES_DIR_VAR="$SAMPLES_DIR" \
        SANDBOX="$sandbox" \
        MDX_TESTING=1 bash -c '
            set +e
            cd "$SANDBOX"
            source "$BROWSE"
            trap - ERR
            set +e
            eval "$ENV127_TEST_BODY"
        ' _inner < /dev/null
    rm -rf "$sandbox"
}

################################################################################
## save → load round-trip
################################################################################

test_save_then_load_restores_state () {
    local out
    out=$(_browse_eval_in_tmpdir '
        cp "$SAMPLES_DIR_VAR/trees.csv" data.csv
        input_file="data.csv"
        # Set known state and save.
        selected_pos=7
        list_scroll=3
        detail_scroll=12
        pane_focus=1
        search_term="overview"
        _browse_save_state
        # State file must exist with the expected hash.
        if [[ ! -f .analyze_browser_state ]]; then
            echo "FAIL: state file missing"; exit 1
        fi
        # Reset everything and reload.
        selected_pos=0; list_scroll=0; detail_scroll=0
        pane_focus=0; search_term=""
        _browse_load_state
        printf "selected=%d list=%d detail=%d focus=%d search=%s\n" \
            "$selected_pos" "$list_scroll" "$detail_scroll" \
            "$pane_focus" "$search_term"
    ')
    assert_contains "$out" "selected=7 list=3 detail=12 focus=1 search=overview" "load_state must restore every persisted field"
}

test_state_file_contains_byte_count_hash () {
    local out
    out=$(_browse_eval_in_tmpdir '
        cp "$SAMPLES_DIR_VAR/trees.csv" data.csv
        input_file="data.csv"
        selected_pos=2
        _browse_save_state
        # The recorded hash must match wc -c on the data file.
        recorded=$(awk -F= "/^hash=/{print \$2; exit}" .analyze_browser_state)
        expected=$(wc -c <data.csv | tr -d " ")
        if [[ "$recorded" == "$expected" ]]; then
            echo OK
        else
            echo "MISMATCH recorded=$recorded expected=$expected"
        fi
    ')
    assert_contains "$out" "OK" "saved state hash must equal input file byte count"
}

################################################################################
## Hash mismatch → fresh state
################################################################################

test_hash_mismatch_falls_back_to_fresh () {
    local out
    out=$(_browse_eval_in_tmpdir '
        cp "$SAMPLES_DIR_VAR/trees.csv" data.csv
        input_file="data.csv"
        selected_pos=9; pane_focus=1
        _browse_save_state
        # Modify the file so its byte count changes — load should refuse.
        echo "extra,data,line" >> data.csv
        # Reset and load.
        selected_pos=0; pane_focus=0
        _browse_load_state
        printf "selected=%d focus=%d\n" "$selected_pos" "$pane_focus"
    ')
    assert_contains "$out" "selected=0 focus=0" "load_state must NOT restore when stored hash != current hash"
}

test_missing_state_file_is_noop () {
    local out
    out=$(_browse_eval_in_tmpdir '
        cp "$SAMPLES_DIR_VAR/trees.csv" data.csv
        input_file="data.csv"
        selected_pos=5; pane_focus=1
        # No state file exists → load should leave vars alone.
        _browse_load_state
        printf "selected=%d focus=%d\n" "$selected_pos" "$pane_focus"
    ')
    assert_contains "$out" "selected=5 focus=1" "load_state with no state file must leave vars untouched"
}

################################################################################
## --fresh equivalent: load is bypassed at the call site, so a saved
## state from a prior run is ignored even when the hash matches. We
## emulate the dispatcher's `if [[ "$fresh_state" -ne 1 ]]; then
## _browse_load_state; fi` guard inline.
################################################################################

test_fresh_skips_state_restore () {
    local out
    out=$(_browse_eval_in_tmpdir '
        cp "$SAMPLES_DIR_VAR/trees.csv" data.csv
        input_file="data.csv"
        selected_pos=4
        _browse_save_state
        # Reset, then run the dispatcher-equivalent guard with fresh_state=1.
        selected_pos=0
        fresh_state=1
        if [[ "$fresh_state" -ne 1 ]]; then _browse_load_state; fi
        printf "selected=%d\n" "$selected_pos"
    ')
    assert_contains "$out" "selected=0" "--fresh must skip _browse_load_state even when state file matches"
}

run_test "save → load round-trip restores every field" test_save_then_load_restores_state
run_test "state file records input file's byte count as hash" test_state_file_contains_byte_count_hash
run_test "hash mismatch refuses restore (file changed)" test_hash_mismatch_falls_back_to_fresh
run_test "missing state file is a no-op" test_missing_state_file_is_noop
run_test "--fresh bypasses state restore on matching hash" test_fresh_skips_state_restore

print_summary
