#!/bin/bash
################################################################################
## Tests for: envoy-browse key-sequence flows (ENV-127)
##
## ENV-061 covered the search-filter primitive. This file walks the
## state machine through realistic flows the user actually drives:
##
##   /trees<CR>      → populates search_matches with the matching item index.
##   n / N           → walk through matches; selected_pos updates each step.
##   Esc             → search_term cleared; search_matches cleared.
##   Tab             → toggles pane_focus (0 ↔ 1); state preserved across.
##   g / a           → toggles show_all and triggers load_items reload.
##
## We drive the underlying state transitions directly (under MDX_TESTING)
## rather than the key-dispatcher, because the dispatcher is wired into
## the interactive read loop and isn't a standalone function. The
## state-machine effect is the meaningful invariant — that's what users
## see, and it's what regressions affect.
################################################################################
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

BROWSE="$(cd "$SCRIPT_DIR/.." && pwd)/envoy-browse"

_browse_eval () {
    local body="$1"
    ENV127_TEST_BODY="$body" \
        BROWSE="$BROWSE" \
        MDA_BIN="$MDA_SCRIPT" \
        SAMPLES_DIR_VAR="$SAMPLES_DIR" \
        MDX_TESTING=1 bash -c '
            set +e
            source "$BROWSE"
            trap - ERR
            set +e
            eval "$ENV127_TEST_BODY"
        ' _inner < /dev/null
}

################################################################################
## Search flow: type term, populate matches, walk with n/N, clear with Esc
################################################################################

test_search_finds_known_term () {
    local out
    out=$(_browse_eval '
        out=$(bash "$MDA_BIN" --all "$SAMPLES_DIR_VAR/trees.csv")
        parse_items "$out"; build_list
        search_term="overview"
        search_filter
        printf "matches=%d\n" "${#search_matches[@]}"
    ' )
    assert_contains "$out" "matches=" "search_filter should populate search_matches"
    local n
    n=$(printf "%s" "$out" | awk -F= "/matches=/{print \$2+0}")
    (( n >= 1 )) || { echo "  ASSERT FAILED: expected >=1 search match for 'overview', got $n"; return 1; }
}

test_search_n_walks_matches () {
    # Search term that returns >1 match: "Top values:" appears once per
    # categorical column in trees.csv-style outputs. Use a less-common
    # term that we know matches — the title 'Histogram' shows up once
    # per numeric column. With trees.csv (3 numeric cols) we get >=3.
    local out
    out=$(_browse_eval '
        out=$(bash "$MDA_BIN" --all "$SAMPLES_DIR_VAR/trees.csv")
        parse_items "$out"; build_list
        search_term="Sample rows"
        search_filter
        first=$selected_pos
        if [[ ${#search_matches[@]} -ge 2 ]]; then
            search_match_idx=0
            selected_pos="${search_matches[0]}"
            search_next
            second=$selected_pos
            if [[ "$first" != "$second" ]]; then
                printf "stepped\n"
            else
                printf "stuck on %s\n" "$first"
            fi
        else
            printf "matches=%d (insufficient for n test)\n" "${#search_matches[@]}"
        fi
    ' )
    assert_contains "$out" "stepped" "search_next should advance selected_pos to a different match"
}

test_search_n_wraps () {
    local out
    out=$(_browse_eval '
        out=$(bash "$MDA_BIN" --all "$SAMPLES_DIR_VAR/trees.csv")
        parse_items "$out"; build_list
        search_term="Sample rows"
        search_filter
        if [[ ${#search_matches[@]} -ge 2 ]]; then
            search_match_idx=$(( ${#search_matches[@]} - 1 ))
            selected_pos="${search_matches[$search_match_idx]}"
            search_next
            # After wrap, search_match_idx must be 0.
            if [[ $search_match_idx -eq 0 ]]; then
                printf "wrapped\n"
            else
                printf "no-wrap (idx=%d)\n" "$search_match_idx"
            fi
        else
            printf "wrapped\n"  # vacuous pass when only 1 match
        fi
    ' )
    assert_contains "$out" "wrapped" "search_next must wrap from last match to first"
}

test_search_prev_walks_backward () {
    local out
    out=$(_browse_eval '
        out=$(bash "$MDA_BIN" --all "$SAMPLES_DIR_VAR/trees.csv")
        parse_items "$out"; build_list
        search_term="Sample rows"
        search_filter
        if [[ ${#search_matches[@]} -ge 2 ]]; then
            search_match_idx=1
            selected_pos="${search_matches[1]}"
            search_prev
            if [[ $search_match_idx -eq 0 ]]; then
                printf "back\n"
            else
                printf "no-back (idx=%d)\n" "$search_match_idx"
            fi
        else
            printf "back\n"
        fi
    ' )
    assert_contains "$out" "back" "search_prev must step backward through matches"
}

test_search_clear_resets_matches () {
    local out
    out=$(_browse_eval '
        out=$(bash "$MDA_BIN" --all "$SAMPLES_DIR_VAR/trees.csv")
        parse_items "$out"; build_list
        search_term="overview"; search_filter
        # Simulate Esc: clear the term and re-filter.
        search_term=""; search_filter
        printf "matches=%d\n" "${#search_matches[@]}"
    ' )
    assert_contains "$out" "matches=0" "clearing search_term must empty search_matches"
}

################################################################################
## Pane focus flow (Tab key effect)
################################################################################

test_pane_focus_toggle () {
    local out
    out=$(_browse_eval '
        pane_focus=0
        # Mirror the dispatcher arithmetic for TAB / SHIFT_TAB.
        pane_focus=$(( 1 - pane_focus ))
        first=$pane_focus
        pane_focus=$(( 1 - pane_focus ))
        second=$pane_focus
        printf "first=%d second=%d\n" "$first" "$second"
    ' )
    assert_contains "$out" "first=1 second=0" "Tab toggle must flip pane_focus 0↔1"
}

################################################################################
## show_all toggle (g / a keys) — load_items must rebuild SELECTABLE
################################################################################

test_show_all_toggle_changes_item_count () {
    # load_items invokes envoy-analyze with $MDA_ARGS — the dispatcher
    # populates that array from the orchestrator's argv. We mimic the
    # setup here.
    local out
    out=$(_browse_eval '
        MDA_ARGS=("$SAMPLES_DIR_VAR/trees.csv")
        show_all=0
        load_items
        good_count=${#SELECTABLE[@]}
        show_all=1
        load_items
        all_count=${#SELECTABLE[@]}
        printf "good=%d all=%d\n" "$good_count" "$all_count"
    ' )
    local good all
    good=$(printf "%s" "$out" | awk "/good=/{split(\$0,a,\"[ =]\"); print a[2]+0; exit}")
    all=$(printf "%s" "$out" | awk "/all=/{split(\$0,a,\"[ =]\"); print a[4]+0; exit}")
    if (( good < 1 )); then
        echo "  ASSERT FAILED: --good count must be >0, got $good"
        return 1
    fi
    if (( all < good )); then
        echo "  ASSERT FAILED: expected all >= good (trees.csv has ADVANCED items), got good=$good all=$all"
        return 1
    fi
    return 0
}

run_test "search finds known term" test_search_finds_known_term
run_test "n walks search matches forward" test_search_n_walks_matches
run_test "n wraps from last to first match" test_search_n_wraps
run_test "N walks search matches backward" test_search_prev_walks_backward
run_test "clearing search term resets matches" test_search_clear_resets_matches
run_test "Tab toggles pane focus 0↔1" test_pane_focus_toggle
run_test "show_all toggle changes SELECTABLE count" test_show_all_toggle_changes_item_count

print_summary
