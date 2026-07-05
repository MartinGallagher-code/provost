#!/bin/bash
################################################################################
## Tests for: envoy-browse SIGWINCH / resize handling (ENV-127)
##
## envoy-browse reads its dimensions via `get_term_size` (which calls
## `stty size`). On a real SIGWINCH the next render-loop iteration
## re-invokes get_term_size and the layout re-flows. We can't deliver a
## real SIGWINCH from the source-harness, but we *can* verify that:
##
##   1. get_term_size picks up changed `stty size` values.
##   2. get_term_size has a sensible fallback when stty is unavailable.
##   3. render() respects the new dimensions on the next call (no items
##      dropped, separator column moves).
##
## Together these pin the regression we care about: a resize must not
## leave the layout frozen at the old dimensions.
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

test_get_term_size_reads_stty () {
    local out
    out=$(_browse_eval '
        # Stub stty to return a known value, then call the real helper.
        stty () { echo "30 100"; }
        get_term_size
        printf "h=%s w=%s\n" "$term_h" "$term_w"
    ' )
    assert_contains "$out" "h=30 w=100" "get_term_size must parse stty's 'rows cols' output"
}

test_get_term_size_picks_up_changes () {
    # First read 24x80, then 40x120 — second value must take effect.
    # Note: get_term_size uses `$(stty size)` which spawns a subshell, so
    # the stub's counter has to live on disk to be observed across calls.
    local idx_file
    idx_file=$(mktemp)
    echo 0 > "$idx_file"
    local out
    out=$(_browse_eval "
        idx_file='$idx_file'
        stty () {
            local n; n=\$(<\"\$idx_file\"); n=\$((n + 1)); echo \"\$n\" > \"\$idx_file\"
            if [[ \$n -eq 1 ]]; then echo \"24 80\"; else echo \"40 120\"; fi
        }
        export -f stty
        get_term_size; first_h=\$term_h; first_w=\$term_w
        get_term_size; second_h=\$term_h; second_w=\$term_w
        printf 'first=%sx%s second=%sx%s\n' \"\$first_h\" \"\$first_w\" \"\$second_h\" \"\$second_w\"
    ")
    rm -f "$idx_file"
    assert_contains "$out" "first=24x80 second=40x120" "consecutive get_term_size calls must reflect updated stty output"
}

test_get_term_size_fallback_when_stty_fails () {
    local out
    out=$(_browse_eval '
        # Make stty fail outright.
        stty () { return 1; }
        get_term_size
        printf "h=%s w=%s\n" "$term_h" "$term_w"
    ' )
    # Default is 24x80 per the source.
    assert_contains "$out" "h=24 w=80" "get_term_size must fall back to 24x80 when stty fails"
}

test_render_separator_moves_with_term_width () {
    # Verify the separator column shifts when term_w changes — the
    # actual SIGWINCH-driven re-render uses exactly this path.
    local out80 out120
    out80=$(_browse_eval '
        out=$(bash "$MDA_BIN" --all "$SAMPLES_DIR_VAR/trees.csv")
        parse_items "$out"; build_list
        term_w=80; term_h=24; get_term_size () { term_w=80; term_h=24; }
        render 2>/dev/null
    ' )
    out120=$(_browse_eval '
        out=$(bash "$MDA_BIN" --all "$SAMPLES_DIR_VAR/trees.csv")
        parse_items "$out"; build_list
        term_w=120; term_h=40; get_term_size () { term_w=120; term_h=40; }
        render 2>/dev/null
    ' )
    # 80-wide: left_w = 32, separator at col 34.
    # 120-wide: left_w = 48, separator at col 50.
    if [[ "$out80" != *$'\033''['*';34H'* ]]; then
        echo "  ASSERT FAILED: 80-wide render missing separator at col 34"
        return 1
    fi
    if [[ "$out120" != *$'\033''['*';50H'* ]]; then
        echo "  ASSERT FAILED: 120-wide render missing separator at col 50"
        return 1
    fi
    return 0
}

test_resize_does_not_lose_items () {
    # Render at 24x80 then at 40x120 with the same SELECTABLE — both
    # outputs should reference the first item (no rows dropped on resize).
    local outA outB
    outA=$(_browse_eval '
        out=$(bash "$MDA_BIN" --all "$SAMPLES_DIR_VAR/trees.csv")
        parse_items "$out"; build_list
        term_w=80; term_h=24; get_term_size () { term_w=80; term_h=24; }
        render 2>/dev/null
    ' )
    outB=$(_browse_eval '
        out=$(bash "$MDA_BIN" --all "$SAMPLES_DIR_VAR/trees.csv")
        parse_items "$out"; build_list
        term_w=120; term_h=40; get_term_size () { term_w=120; term_h=40; }
        render 2>/dev/null
    ' )
    assert_contains "$outA" "Dataset overview" "small-terminal render keeps Dataset overview"
    assert_contains "$outB" "Dataset overview" "large-terminal render keeps Dataset overview"
}

run_test "get_term_size reads stty 'rows cols'" test_get_term_size_reads_stty
run_test "get_term_size picks up dimension changes" test_get_term_size_picks_up_changes
run_test "get_term_size falls back on stty failure" test_get_term_size_fallback_when_stty_fails
run_test "render separator moves with term width" test_render_separator_moves_with_term_width
run_test "resize keeps items in the layout" test_resize_does_not_lose_items

print_summary
