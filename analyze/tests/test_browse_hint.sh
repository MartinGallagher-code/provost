#!/bin/bash
################################################################################
## Tests for: envoy-browse startup `Press ? for help` hint (ENV-134)
##
## Pins:
##   * Fresh-launch render shows the hint text in the footer.
##   * After the hint dismissal flag is set (mirrors first key press), the
##     hint text is gone but the footer width is unchanged (no layout shift).
##   * `--no-hint` and `EF_BROWSE_NO_HINT=1` suppress the hint from the
##     start.
##   * `--help` advertises the new flag.
##
## Approach: source envoy-browse under `MDX_TESTING=1` and call `render`
## directly with a fixed terminal size, then assert on the captured output.
## Mirrors the harness used by the other test_browse_*.sh files.
################################################################################
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

BROWSE="$(cd "$SCRIPT_DIR/.." && pwd)/envoy-browse"

# Mirror of the helper used by test_browse_render.sh — runs `body` after
# sourcing envoy-browse in MDX_TESTING mode (which short-circuits the main
# render loop, leaving render / parse_items / build_list available for
# direct invocation).
_browse_eval () {
    local body="$1"
    local extra_env="${2:-}"
    ENV134_TEST_BODY="$body" \
        BROWSE="$BROWSE" \
        MDA_BIN="$MDA_SCRIPT" \
        SAMPLES_DIR_VAR="$SAMPLES_DIR" \
        env $extra_env MDX_TESTING=1 bash -c '
            set +e
            source "$BROWSE"
            trap - ERR
            set +e
            eval "$ENV134_TEST_BODY"
        ' _inner < /dev/null
}

# Visible-character length of the footer line (last newline-terminated row
# of the render). Strips ANSI CSI escape sequences before counting so the
# style bytes around the hint don't skew the width.
_footer_visible_width () {
    local frame="$1"
    # Last non-empty line.
    local last
    last=$(printf '%s' "$frame" | awk 'NF{l=$0} END{print l}')
    # Strip CSI escapes.
    local stripped
    stripped=$(printf '%s' "$last" | sed -E $'s/\x1b\\[[0-9;?]*[A-Za-z]//g')
    printf '%d' "${#stripped}"
}

################################################################################
## Hint visible on fresh launch
################################################################################

test_hint_visible_on_fresh_launch () {
    local out
    out=$(_browse_eval '
        out=$(bash "$MDA_BIN" --all "$SAMPLES_DIR_VAR/trees.csv")
        parse_items "$out"; build_list
        term_w=80; term_h=24; get_term_size () { term_w=80; term_h=24; }
        # _HINT_DISMISSED defaults to 0; opt_no_hint defaults to 0.
        render 2>/dev/null
    ' )
    assert_contains "$out" "Press ? for help" "fresh launch must show the hint"
}

################################################################################
## Hint hidden after dismissal — but width unchanged
################################################################################

test_hint_hidden_after_dismissal () {
    local out
    out=$(_browse_eval '
        out=$(bash "$MDA_BIN" --all "$SAMPLES_DIR_VAR/trees.csv")
        parse_items "$out"; build_list
        term_w=80; term_h=24; get_term_size () { term_w=80; term_h=24; }
        _HINT_DISMISSED=1
        render 2>/dev/null
    ' )
    if [[ "$out" == *"Press ? for help"* ]]; then
        echo "  ASSERT FAILED: dismissed hint should not appear in footer"
        return 1
    fi
}

test_dismissed_hint_preserves_footer_width () {
    # Hinting and not-hinting must produce the same visible footer width
    # so dismissal doesn't shift the rest of the line.
    local with_hint without_hint
    with_hint=$(_browse_eval '
        out=$(bash "$MDA_BIN" --all "$SAMPLES_DIR_VAR/trees.csv")
        parse_items "$out"; build_list
        term_w=80; term_h=24; get_term_size () { term_w=80; term_h=24; }
        render 2>/dev/null
    ' )
    without_hint=$(_browse_eval '
        out=$(bash "$MDA_BIN" --all "$SAMPLES_DIR_VAR/trees.csv")
        parse_items "$out"; build_list
        term_w=80; term_h=24; get_term_size () { term_w=80; term_h=24; }
        _HINT_DISMISSED=1
        render 2>/dev/null
    ' )
    local w1 w2
    w1=$(_footer_visible_width "$with_hint")
    w2=$(_footer_visible_width "$without_hint")
    if [[ "$w1" != "$w2" ]]; then
        echo "  ASSERT FAILED: footer width changed on dismissal (hint=$w1, dismissed=$w2)"
        return 1
    fi
    if [[ "$w1" -lt 80 ]]; then
        echo "  ASSERT FAILED: footer should fill 80-col terminal, got $w1"
        return 1
    fi
}

################################################################################
## Suppression knobs
################################################################################

test_no_hint_flag_suppresses () {
    local out
    out=$(_browse_eval '
        out=$(bash "$MDA_BIN" --all "$SAMPLES_DIR_VAR/trees.csv")
        parse_items "$out"; build_list
        term_w=80; term_h=24; get_term_size () { term_w=80; term_h=24; }
        opt_no_hint=1
        render 2>/dev/null
    ' )
    if [[ "$out" == *"Press ? for help"* ]]; then
        echo "  ASSERT FAILED: --no-hint should suppress the hint text"
        return 1
    fi
}

test_env_var_suppresses () {
    # The env var path runs at script-source time. Source with the var set
    # and verify opt_no_hint comes out of source initialisation as 1.
    local out
    out=$(_browse_eval '
        echo "opt_no_hint=$opt_no_hint"
    ' "EF_BROWSE_NO_HINT=1")
    assert_contains "$out" "opt_no_hint=1" "EF_BROWSE_NO_HINT=1 should set opt_no_hint=1"
}

################################################################################
## --help advertises the flag
################################################################################

test_help_documents_no_hint () {
    local out
    out=$(bash "$BROWSE" --help 2>&1)
    assert_contains "$out" "--no-hint" "--help must document --no-hint"
    assert_contains "$out" "EF_BROWSE_NO_HINT" "--help must mention the env var"
}

run_test "ENV-134 hint visible on fresh launch" test_hint_visible_on_fresh_launch
run_test "ENV-134 hint hidden after dismissal" test_hint_hidden_after_dismissal
run_test "ENV-134 dismissal preserves footer width (no layout shift)" test_dismissed_hint_preserves_footer_width
run_test "ENV-134 --no-hint suppresses the hint" test_no_hint_flag_suppresses
run_test "ENV-134 EF_BROWSE_NO_HINT=1 sets opt_no_hint" test_env_var_suppresses
run_test "ENV-134 --help advertises --no-hint and the env var" test_help_documents_no_hint

print_summary
