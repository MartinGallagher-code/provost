#!/bin/bash
# ENV-061: envoy-browse TUI state-machine and helper tests.
# Sources envoy-browse under MDX_TESTING=1 and exercises parsing, classification,
# search filtering, scroll/selection state, and the export helpers (exported by
# ENV-068). No real TTY; no rendering is asserted pixel-wise — only structural.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

BROWSE="$(cd "$SCRIPT_DIR/.." && pwd)/envoy-browse"

# Run body in a clean subshell with envoy-browse sourced in MDX_TESTING mode.
_tui_eval () {
    local body="$1"
    ENV061_TEST_BODY="$body" BROWSE="$BROWSE" MDX_TESTING=1 bash -c '
        set +e
        source "$BROWSE"
        trap - ERR
        set +e
        eval "$ENV061_TEST_BODY"
    ' _inner < /dev/null
    return $?
}

# ── parse_items ────────────────────────────────────────────────

test_parse_items_counts_items () {
    local out
    out=$(_tui_eval '
        out=$(bash "$MDA_BIN" --all "$SAMPLES_DIR_VAR"/trees.csv)
        parse_items "$out"
        printf "items=%d selectable=%d\n" "${#ITEM_TITLE[@]}" "${#SELECTABLE[@]}"
    ' )
    assert_contains "$out" "items=" "parse_items should populate ITEM_TITLE"
    # At least a handful of items in a full analysis
    local n
    n=$(printf '%s' "$out" | awk -F'=' '/items=/{print $2+0}')
    (( n >= 5 )) || { echo "  ASSERT FAILED: expected >=5 items, got $n"; return 1; }
}

# ── classify_title ─────────────────────────────────────────────

test_classify_summary_title () {
    local out
    out=$(_tui_eval 'printf "%s" "$(classify_title "Dataset overview")"')
    [[ "$out" == "summary" ]] || { echo "  ASSERT FAILED: expected summary, got: $out"; return 1; }
}

test_classify_variable_title () {
    local out
    out=$(_tui_eval 'printf "%s" "$(classify_title "Histogram: MyCol")"')
    [[ "$out" == "variable" ]] || { echo "  ASSERT FAILED: expected variable, got: $out"; return 1; }
}

test_classify_multi_title () {
    local out
    out=$(_tui_eval 'printf "%s" "$(classify_title "Correlation matrix")"')
    [[ "$out" == "multi" ]] || { echo "  ASSERT FAILED: expected multi, got: $out"; return 1; }
}

# ── search_filter ──────────────────────────────────────────────

test_search_filter_matches_substring () {
    local out
    out=$(_tui_eval '
        SELECTABLE=(0 1 2)
        ITEM_TITLE=([0]="Dataset overview" [1]="Column types" [2]="Missing values")
        ITEM_TITLE_LOWER=([0]="dataset overview" [1]="column types" [2]="missing values")
        VAR_NAMES=(); VAR_NAMES_LOWER=()
        search_term="column"
        search_filter
        printf "%d" "${#search_matches[@]}"
    ')
    [[ "$out" == "1" ]] || { echo "  ASSERT FAILED: expected 1 match, got $out"; return 1; }
}

test_search_filter_case_insensitive () {
    local out
    out=$(_tui_eval '
        SELECTABLE=(0 1)
        ITEM_TITLE=([0]="Strongest Correlations" [1]="Data quality score")
        ITEM_TITLE_LOWER=([0]="strongest correlations" [1]="data quality score")
        VAR_NAMES=(); VAR_NAMES_LOWER=()
        search_term="CORR"
        search_filter
        printf "%d" "${#search_matches[@]}"
    ')
    [[ "$out" == "1" ]] || { echo "  ASSERT FAILED: expected 1 case-insensitive match, got $out"; return 1; }
}

test_watch_file_token_changes () {
    local tmp out
    tmp=$(mktemp)
    printf 'a,b\n1,2\n' > "$tmp"
    out=$(_tui_eval "
        t1=\$(_watch_file_token '$tmp' mtime-size)
        sleep 1
        printf 'a,b\n1,3\n' > '$tmp'
        t2=\$(_watch_file_token '$tmp' mtime-size)
        [[ \"\$t1\" != \"\$t2\" ]] && printf changed || printf unchanged
    ")
    rm -f "$tmp"
    [[ "$out" == "changed" ]] || { echo "  ASSERT FAILED: expected token change, got $out"; return 1; }
}

test_watch_reload_preserves_selected_item () {
    local tmp out
    tmp=$(mktemp)
    printf 'name,value\nalpha,1\nbeta,2\n' > "$tmp"
    out=$(_tui_eval "
        MDA_ARGS=('$tmp')
        watch_mode=1
        watch_target='$tmp'
        watch_preserve_view=1
        show_all=1
        load_items
        for ((i=0; i<\${#SELECTABLE[@]}; i++)); do
            item=\"\${SELECTABLE[\$i]}\"
            if [[ \"\$item\" == var:* && \"\${VAR_NAMES[\${item#var:}]}\" == value ]]; then
                selected_pos=\$i
                break
            fi
        done
        before=\$(_browse_selected_key)
        printf 'name,value\nalpha,1\nbeta,3\ngamma,5\n' > '$tmp'
        _watch_reload test >/dev/null 2>&1 || true
        after=\$(_browse_selected_key)
        printf '%s|%s' \"\$before\" \"\$after\"
    ")
    rm -f "$tmp"
    [[ "$out" == "var:value|var:value" ]] || { echo "  ASSERT FAILED: expected selected variable preserved, got $out"; return 1; }
}

test_watch_target_after_flags () {
    local tmp out
    tmp=$(mktemp)
    printf 'name,value\nalpha,1\n' > "$tmp"
    out=$(BROWSE="$BROWSE" MDX_TESTING=1 bash -c '
        set +e
        source "$BROWSE" --watch --interval 2 "$1"
        trap - ERR
        printf "%s|%s|%s" "$watch_mode" "$watch_interval" "$watch_target"
    ' _inner "$tmp")
    rm -f "$tmp"
    [[ "$out" == "1|2|$tmp" ]] || { echo "  ASSERT FAILED: expected watch target after flags, got $out"; return 1; }
}

test_search_filter_empty_term_clears () {
    local out
    out=$(_tui_eval '
        SELECTABLE=(0 1)
        ITEM_TITLE=([0]="A" [1]="B")
        ITEM_TITLE_LOWER=([0]="a" [1]="b")
        VAR_NAMES=(); VAR_NAMES_LOWER=()
        search_term=""
        search_matches=(99)
        search_filter
        printf "%d" "${#search_matches[@]}"
    ')
    [[ "$out" == "0" ]] || { echo "  ASSERT FAILED: empty search should clear, got $out"; return 1; }
}

# ── search_next / search_prev cycling ──────────────────────────

test_search_next_wraps_around () {
    local out
    out=$(_tui_eval '
        search_matches=(2 5 8)
        search_match_idx=0
        selected_pos=0; detail_scroll=0
        search_next
        a="$selected_pos"
        search_next
        b="$selected_pos"
        search_next
        c="$selected_pos"   # should wrap
        printf "%s,%s,%s" "$a" "$b" "$c"
    ')
    [[ "$out" == "5,8,2" ]] || { echo "  ASSERT FAILED: next cycle, got $out"; return 1; }
}

test_search_prev_wraps_around () {
    local out
    out=$(_tui_eval '
        search_matches=(2 5 8)
        search_match_idx=0
        selected_pos=2; detail_scroll=0
        search_prev   # wraps to last
        printf "%s" "$selected_pos"
    ')
    [[ "$out" == "8" ]] || { echo "  ASSERT FAILED: prev wrap, got $out"; return 1; }
}

# ── pad_line / text-width helpers ──────────────────────────────

test_pad_line_truncates_and_pads () {
    local long short
    long=$(_tui_eval 'pad_line "abcdefghij" 5')
    short=$(_tui_eval 'pad_line "ab" 5')
    [[ ${#long} -eq 5 ]] || { echo "  ASSERT FAILED: truncate len=${#long}"; return 1; }
    [[ ${#short} -eq 5 ]] || { echo "  ASSERT FAILED: pad len=${#short}"; return 1; }
}

# ── export helpers still present (ENV-068 contract) ────────────

test_export_default_path_still_present () {
    local out
    out=$(_tui_eval 'selected_pos=0; SELECTABLE=(0); ITEM_TAG=([0]="GOOD"); ITEM_TITLE=([0]="X"); ITEM_BODY=([0]="y"); VAR_NAMES=(); VAR_TAG=(); export_default_path current')
    assert_contains "$out" "./envoy-browse-item-" "default path preserved"
}

# ── key-parser coverage markers ────────────────────────────────

test_normal_mode_keys_registered () {
    # Static grep: these cases must exist in the dispatch loop
    local key
    for key in 'a)' 'g)' 'q)' 'w)' 'W)' 'n)' 'N)'; do
        grep -qE "^[[:space:]]+${key}[[:space:]]*$" "$BROWSE" || {
            echo "  ASSERT FAILED: key case $key not present in event loop"
            return 1
        }
    done
    # "?" and "/" cases use quoted keys
    grep -qF '"?")' "$BROWSE" || { echo "  ASSERT FAILED: \"?\") case missing"; return 1; }
    grep -qE '^[[:space:]]+/\)' "$BROWSE" || { echo "  ASSERT FAILED: /) case missing"; return 1; }
}

test_search_mode_keys_registered () {
    grep -qE '^[[:space:]]+ESC\)' "$BROWSE" || { echo "  ASSERT FAILED: ESC case missing"; return 1; }
    grep -qE '^[[:space:]]+ENTER\)' "$BROWSE" || { echo "  ASSERT FAILED: ENTER case missing"; return 1; }
    grep -qE '^[[:space:]]+BACKSPACE\)' "$BROWSE" || { echo "  ASSERT FAILED: BACKSPACE case missing"; return 1; }
}

# ── Pipe SAMPLES_DIR into the subshell (helpers.sh sets it) ────
export SAMPLES_DIR_VAR="$SAMPLES_DIR"
export MDA_BIN="$MDA_SCRIPT"

run_test "ENV-061 parse_items populates ITEM_TITLE and SELECTABLE" test_parse_items_counts_items
run_test "ENV-061 classify_title: summary" test_classify_summary_title
run_test "ENV-061 classify_title: variable" test_classify_variable_title
run_test "ENV-061 classify_title: multi" test_classify_multi_title
run_test "ENV-061 search_filter substring match" test_search_filter_matches_substring
run_test "ENV-061 search_filter case-insensitive" test_search_filter_case_insensitive
run_test "envoy-browse watch file token changes" test_watch_file_token_changes
run_test "envoy-browse watch reload preserves selected item" test_watch_reload_preserves_selected_item
run_test "envoy-browse watch target can follow flags" test_watch_target_after_flags
run_test "ENV-061 empty search clears matches" test_search_filter_empty_term_clears
run_test "ENV-061 search_next wraps around" test_search_next_wraps_around
run_test "ENV-061 search_prev wraps to last" test_search_prev_wraps_around
run_test "ENV-061 pad_line truncates and pads to exact width" test_pad_line_truncates_and_pads
run_test "ENV-061 ENV-068 export_default_path helper present" test_export_default_path_still_present
run_test "ENV-061 normal-mode key cases registered" test_normal_mode_keys_registered
run_test "ENV-061 search-mode key cases registered" test_search_mode_keys_registered

print_summary
