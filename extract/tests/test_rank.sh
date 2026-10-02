#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Candidate ranking tests (--rank confidence|priority, MFE_RANK)
##
## Under --rank confidence (the default) every eligible detector runs and the
## candidates are tried highest-confidence first (ties: priority, then name);
## a candidate that extracts nothing yields to the next. --rank priority keeps
## the historical order: the first strategy in priority order whose detect
## passes and whose extract produces output. See extract/README.md
## "Confidence rubric".
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Candidate Ranking Tests"
echo "========================================"

TMPDIR_R="$(mktemp -d "${TMPDIR:-/tmp}/rank_tests.XXXXXX")"

# _winner ARGS... FILE — the --emit-meta winner name.
_winner () {
    run_mfe --emit-meta -f tsv --max-strategies 1 "$@" 2>&1 >/dev/null \
        | awk -F'\t' '/^__EXTRACT_META__/ { print $2 }'
}

# _plugin DIR NAME PRIORITY CONF MARKER EMIT — a plugin strategy that detects
# MARKER at confidence CONF and extracts EMIT (empty EMIT = extracts nothing).
_plugin () {
    local dir="$1" name="$2" prio="$3" conf="$4" marker="$5" emit="$6"
    mkdir -p "$dir"
    cat > "$dir/${name}.sh" <<STRAT
#!/bin/bash
## Name: ${name}
## Description: rank test plugin ${name}
## Version: 1.0
## Priority: ${prio}

strategy_detect () {
    _STRATEGY_CONFIDENCE=${conf}
    [[ "\$1" == *'${marker}'* ]]
}

strategy_extract () {
    [[ -n '${emit}' ]] && echo '${emit}'
    return 0
}
STRAT
}

# openssl x509 -dates: aligned-columns (priority 55) detects it, but the
# whole block is KEY=VALUE — equals (priority 65, confidence 75) outranks the
# table reading (60..69) by confidence.
_dates_fixture () {
    printf 'notBefore=Jul  1 00:00:00 2026 GMT\nnotAfter=Sep 29 00:00:00 2026 GMT\n' > "$TMPDIR_R/dates.txt"
}

test_rank_default_is_confidence () {
    _dates_fixture
    assert_eq "equals" "$(_winner "$TMPDIR_R/dates.txt")" "default ranking picks the highest-confidence candidate"
}

test_rank_priority_flag () {
    _dates_fixture
    assert_eq "aligned-columns" "$(_winner --rank priority "$TMPDIR_R/dates.txt")" "--rank priority keeps the first-by-priority winner"
    assert_eq "equals" "$(_winner --rank=confidence "$TMPDIR_R/dates.txt")" "--rank=confidence form is accepted"
}

test_rank_env_override () {
    _dates_fixture
    local w
    w="$(MFE_RANK=priority bash "$MFE_SCRIPT" --emit-meta -f tsv --max-strategies 1 "$TMPDIR_R/dates.txt" 2>&1 >/dev/null \
        | awk -F'\t' '/^__EXTRACT_META__/ { print $2 }')"
    assert_eq "aligned-columns" "$w" "MFE_RANK=priority selects priority order"
}

test_rank_invalid_value () {
    _dates_fixture
    local rc=0
    run_mfe --rank bogus -f tsv "$TMPDIR_R/dates.txt" >/dev/null 2>&1 || rc=$?
    assert_exit_nonzero "$rc" "--rank bogus is rejected"
}

# The top-ranked candidate extracts NOTHING: the next candidate must win, so
# ranking never trades a working parse for an empty one.
test_rank_empty_top_candidate_falls_through () {
    local pd="$TMPDIR_R/empty"
    _plugin "$pd" rank-empty 1 99 RANKMARK ""
    _plugin "$pd" rank-full 90 98 RANKMARK "rank_key rank_val"
    printf 'RANKMARK one\nRANKMARK two\n' > "$TMPDIR_R/empty.txt"
    assert_eq "rank-full" "$(_winner --plugin-dir "$pd" "$TMPDIR_R/empty.txt")" "an empty top candidate yields to the next"
}

# Equal confidence: priority breaks the tie, then the strategy name.
test_rank_tie_breaks_on_priority_then_name () {
    local pd="$TMPDIR_R/tie"
    _plugin "$pd" rank-b 5 97 TIEMARK "b_key b"
    _plugin "$pd" rank-a 5 97 TIEMARK "a_key a"
    _plugin "$pd" rank-c 90 97 TIEMARK "c_key c"
    printf 'TIEMARK x\nTIEMARK y\n' > "$TMPDIR_R/tie.txt"
    assert_eq "rank-a" "$(_winner --plugin-dir "$pd" "$TMPDIR_R/tie.txt")" "tie: lower priority number, then name (LC_ALL=C)"
}

# A LOWER-priority strategy with higher confidence wins by default, and loses
# under --rank priority.
test_rank_confidence_beats_priority () {
    local pd="$TMPDIR_R/cb"
    _plugin "$pd" rank-early 2 60 CBMARK "early_key e"
    _plugin "$pd" rank-late 90 98 CBMARK "late_key l"
    printf 'CBMARK x\nCBMARK y\n' > "$TMPDIR_R/cb.txt"
    assert_eq "rank-late" "$(_winner --plugin-dir "$pd" "$TMPDIR_R/cb.txt")" "confidence ranking prefers the stronger evidence"
    assert_eq "rank-early" "$(_winner --rank priority --plugin-dir "$pd" "$TMPDIR_R/cb.txt")" "priority ranking prefers the earlier strategy"
}

# PRUNING (exact): with --max-strategies 1 a detector whose confidence ceiling
# cannot beat the best so far is skipped. If the top candidate then extracts
# nothing, the pass is redone unpruned — `adb shell getprop` output looks like
# JSON (json scores 85) but json extracts nothing; colons (ceiling 60) was
# pruned and must still win.
test_rank_pruned_top_failure_redoes () {
    local f="$TMPDIR_R/getprop.txt"
    printf '%s\n' '[ro.product.model]: [Pixel 8]' '[ro.product.brand]: [google]' \
        '[ro.build.version.release]: [14]' '[ro.build.version.sdk]: [34]' \
        '[dalvik.vm.heapsize]: [512m]' > "$f"
    assert_eq "$(_winner "$f")" "colons" "pruned run falls back to colons"
    assert_eq "$(_EAS_NOPRUNE=1 _winner "$f")" "colons" "unpruned run agrees"
}

# Pruning never changes a winner (the corpus proves it at scale; this pins a
# few shapes).
test_rank_pruning_is_exact () {
    local f n=0
    for f in "$SCRIPT_DIR/../samples/aligned-columns/basic.txt" \
             "$SCRIPT_DIR/../samples/csv/"*.csv \
             "$SCRIPT_DIR/../samples/json/"*; do
        [[ -f "$f" ]] || continue
        n=$((n + 1))
        assert_eq "$(_winner "$f")" "$(_EAS_NOPRUNE=1 _winner "$f")" "same winner: ${f##*/}"
    done
    [[ $n -gt 0 ]] || _assert_failed "no samples found"
}

# --explain lists matches in RANK order: its first MATCH is the winner.
test_rank_explain_lists_rank_order () {
    local f="$SCRIPT_DIR/../samples/aligned-columns/basic.txt" first
    first="$(run_mfe --explain "$f" 2>/dev/null | awk '$1 == "MATCH" { print $2; exit }')"
    assert_eq "$first" "$(_winner "$f")" "first --explain MATCH is the winner"
}

run_test "rank: default is confidence" test_rank_default_is_confidence
run_test "rank: --rank priority / --rank=confidence" test_rank_priority_flag
run_test "rank: MFE_RANK env override" test_rank_env_override
run_test "rank: invalid --rank value rejected" test_rank_invalid_value
run_test "rank: empty top candidate falls through" test_rank_empty_top_candidate_falls_through
run_test "rank: ties break on priority then name" test_rank_tie_breaks_on_priority_then_name
run_test "rank: confidence beats priority (and --rank priority restores it)" test_rank_confidence_beats_priority
run_test "rank: pruned top candidate failure redoes unpruned" test_rank_pruned_top_failure_redoes
run_test "rank: pruning is exact" test_rank_pruning_is_exact
run_test "rank: --explain lists matches in rank order" test_rank_explain_lists_rank_order

rm -rf "$TMPDIR_R"
print_summary
