#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Column-type consistency and the consistency hold (lib/_discovery.sh)
##
## Consistency = the share of a parse's typed cells that match their column's
## type family (_FR_CONS_AWK, measured in the coverage pass). --emit-meta
## carries it as a 5th field. When the first ranked candidate to produce
## output is a generic parse with a mixed column and consistency under
## _FR_CONS_MIN (95), the next candidates within _FR_CONS_WINDOW (20)
## confidence points get a turn; one that keeps as many lines and types its
## columns materially better (+_FR_CONS_GAIN, itself >= _FR_CONS_MIN, fewer
## mixed columns, comparable evidence) replaces it.
##
## Fixtures (samples/consistency/, written for this test — no corpus or
## benchmark input):
##   pkg-table-overflow.txt   constructed: a package table under a full-width
##                            `----` rule whose long names overflow their
##                            column (vertical-line cuts them; the gutter grid
##                            reads them whole)
##   virsh-snapshot-list.txt  `virsh snapshot-list`: a long snapshot name
##                            shifts the multi-token creation date
##   tab-kv-blocks.txt        constructed: blank-separated `Key:<TAB>value`
##                            blocks (tsv reads a two-column table whose value
##                            column mixes names, addresses and masks)
##   smbclient-ls.txt         `smbclient -c ls`: headerless, multi-word names
##                            and a five-token date — misplaced, and nothing
##                            better exists: low consistency is REPORTED
##   ps-get-package.txt       PowerShell Get-Package: multi-word names, empty
##                            cells, a non-ASCII ellipsis — fixed-width is
##                            right and consistent: nothing changes
##   scoop-list.txt           `scoop list`: overflowing versions under per-
##                            column rules — fixed-width is right: kept
##   peer-table-relabel.txt   constructed: a time-peer table with a two-word
##                            header label; the whole-cell alternative slides
##                            the labels (relabel guard)
##   csv-multiline-cells.csv  constructed: quoted CSV with multi-line cells and
##                            rows that alternate types on purpose (row guard)
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Column-Type Consistency Tests"
echo "========================================"

EXTRACT_DIR="$(dirname "$PROVOST_EXTRACT_SCRIPT")"
CNS="$EXTRACT_DIR/samples/consistency"
TMPDIR_T="$(mktemp -d "${TMPDIR:-/tmp}/consistency_tests.XXXXXX")"

# _meta ARGS... — the --emit-meta line's fields 2-5 (strategy, conf, cov, cons)
_meta () {
    run_extract --emit-meta -f tsv --max-strategies 1 "$@" 2>&1 >/dev/null \
        | awk -F'\t' '/^__EXTRACT_META__/ { print $2 "\t" $3 "\t" $4 "\t" $5 }'
}
_winner () { _meta "$@" | cut -f1; }
_cons () { _meta "$@" | cut -f4; }
_plain () { run_extract -f plain --max-strategies 1 "$@" 2>/dev/null; }

test_meta_has_consistency () {
    local m; m="$(_meta "$CNS/ps-get-package.txt")"
    assert_match "$m" $'^fixed-width\t80\t100\t100$' "meta: strategy, confidence, coverage, consistency 100"
    m="$(run_extract --emit-meta -f tsv --max-strategies 1 "$CNS/ps-get-package.txt" 2>&1 >/dev/null | grep '^__EXTRACT_META__')"
    assert_eq "$(awk -F'\t' '{ print NF }' <<< "$m")" "5" "meta line has 5 fields"
}

test_meta_consistency_not_measured () {
    assert_eq "$(_FR_COV_BYTES=0 _cons "$CNS/ps-get-package.txt")" "-" "consistency above _FR_COV_BYTES is '-'"
    # a single-record key/value parse has no column with 3 cells: not judged
    printf 'alpha: 1\nbeta: two\ngamma: /x/y\n' > "$TMPDIR_T/kv.txt"
    assert_eq "$(_cons "$TMPDIR_T/kv.txt")" "-" "nothing to judge is '-'"
}

test_low_consistency_reported () {
    # smbclient ls: tokens spread a five-token date and multi-word names over
    # the columns; no candidate does better, so the claim is kept — and its
    # consistency says it is misplaced
    local m; m="$(_meta "$CNS/smbclient-ls.txt")"
    assert_match "$m" $'^aligned-columns\t[0-9]+\t100\t[0-7][0-9]$' "misplaced parse: full coverage, consistency < 80"
    assert_eq "$(_FR_CONS_MIN=0 _winner "$CNS/smbclient-ls.txt")" "aligned-columns" "nothing better: same winner with the hold off"
}

test_cut_words_yield () {
    # vertical-line cuts `boost-algorithm` at a fixed column; the cut halves
    # are no words of the input, so its parse is inconsistent and the gutter
    # grid's whole-name parse replaces it
    assert_eq "$(_FR_CONS_MIN=0 _winner "$CNS/pkg-table-overflow.txt")" "vertical-line" "hold off: vertical-line claims it"
    local m; m="$(_meta "$CNS/pkg-table-overflow.txt")"
    assert_match "$m" $'^aligned-columns\t[0-9]+\t100\t100$' "hold on: aligned-columns, consistency 100"
    local out; out="$(_plain "$CNS/pkg-table-overflow.txt")"
    assert_contains "$out" "boost-algorithm" "names kept whole"
    assert_contains "$out" "qtbase[core,gui,widgets,network]" "overflowing name kept whole"
    assert_contains "$out" "4.25.1#1" "version with a port revision kept"
}

test_shifted_date_yields () {
    assert_eq "$(_FR_CONS_MIN=0 _winner "$CNS/virsh-snapshot-list.txt")" "vertical-line" "hold off: vertical-line"
    assert_eq "$(_winner "$CNS/virsh-snapshot-list.txt")" "aligned-columns" "hold on: aligned-columns"
    local out; out="$(_plain "$CNS/virsh-snapshot-list.txt")"
    assert_contains "$out" "after-install-fixes-and-cleanup" "long snapshot name whole"
    assert_contains "$out" "2026-10-05" "its date is not split"
}

test_tab_kv_blocks_yield () {
    assert_eq "$(_FR_CONS_MIN=0 _winner "$CNS/tab-kv-blocks.txt")" "tsv" "hold off: tsv (two columns: key, mixed value)"
    assert_eq "$(_winner "$CNS/tab-kv-blocks.txt")" "block-records" "hold on: one record per block"
    assert_eq "$(_winner --generic "$CNS/tab-kv-blocks.txt")" "block-records" "--generic: hold applies"
}

test_consistent_claims_kept () {
    local f
    for f in ps-get-package scoop-list; do
        assert_eq "$(_winner "$CNS/$f.txt")" "fixed-width" "$f: fixed-width kept"
        assert_eq "$(_plain "$CNS/$f.txt")" "$(_FR_CONS_MIN=0 _plain "$CNS/$f.txt")" "$f: output unchanged by the hold"
    done
}

test_pinned_and_priority_not_held () {
    local c; c="$(_cons -s vertical-line "$CNS/pkg-table-overflow.txt")"
    assert_match "$c" '^[0-9]+$' "pinned: consistency measured"
    [[ "$c" =~ ^[0-9]+$ && "$c" -lt 95 ]] || _assert_failed "pinned vertical-line reports < 95 (got $c)"
    assert_eq "$(_winner -s vertical-line "$CNS/pkg-table-overflow.txt")" "vertical-line" "pinned strategy is never held"
    assert_eq "$(_winner --rank priority "$CNS/pkg-table-overflow.txt")" "$(_FR_CONS_MIN=0 _winner --rank priority "$CNS/pkg-table-overflow.txt")" "--rank priority: unaffected"
}

test_hold_switches () {
    assert_eq "$(_FR_CONS_WINDOW=5 _winner "$CNS/pkg-table-overflow.txt")" "vertical-line" "window too narrow: claim kept"
    assert_eq "$(_FR_CONS_GAIN=101 _winner "$CNS/pkg-table-overflow.txt")" "vertical-line" "unreachable gain: claim kept"
    assert_eq "$(_FR_CONS_HOLD_BYTES=100 _winner "$CNS/pkg-table-overflow.txt")" "vertical-line" "input over _FR_CONS_HOLD_BYTES: not held"
    assert_match "$(_FR_CONS_HOLD_BYTES=100 _cons "$CNS/pkg-table-overflow.txt")" '^[0-9]+$' "... but its consistency is still reported"
    # a claim kept after the hold is the never-held claim byte for byte
    assert_eq "$(_FR_CONS_GAIN=101 _plain "$CNS/pkg-table-overflow.txt")" "$(_FR_CONS_MIN=0 _plain "$CNS/pkg-table-overflow.txt")" "restored claim == never-held output"
}

test_bespoke_is_not_held () {
    # a bespoke (plugin) strategy whose SIZE column mixes numbers and words:
    # tool knowledge, never second-guessed, though aligned-columns would
    # type the table better
    mkdir -p "$TMPDIR_T/plug"
    cat > "$TMPDIR_T/plug/mixed-cols.sh" <<'STRAT'
#!/bin/bash
## Name: mixed-cols
## Description: consistency test plugin — a fixed, deliberately mixed layout
## Version: 1.0
## Priority: 5

strategy_detect () { _STRATEGY_CONFIDENCE=92; [[ "$1" == NAME*SIZE* ]]; }
strategy_extract () { printf '%s\n' "$1" | awk 'NR > 1 && NF { n++; print "row" n ".name " $1; print "row" n ".size " (n % 2 ? $2 : "big") }'; }
STRAT
    printf 'NAME   SIZE\nalpha  12\nbeta   7\ngamma  31\ndelta  4\n' > "$TMPDIR_T/mixed.txt"
    local m; m="$(_meta --plugin-dir "$TMPDIR_T/plug" "$TMPDIR_T/mixed.txt")"
    assert_match "$m" $'^mixed-cols\t92\t[0-9]+\t[0-9]+$' "bespoke claim kept"
    [[ "$(cut -f4 <<< "$m")" -lt 95 ]] || _assert_failed "plugin parse reports its mixed column (got $m)"
}

test_pruning_exact () {
    local f a b
    for f in "$CNS"/*.txt; do
        a="$(run_extract --emit-meta -f tsv --max-strategies 1 "$f" 2>&1)"
        b="$(_EAS_NOPRUNE=1 run_extract --emit-meta -f tsv --max-strategies 1 "$f" 2>&1)"
        assert_eq "$b" "$a" "$(basename "$f"): unpruned == pruned"
    done
}

test_routes_identical () {
    local f a b c
    for f in "$CNS/pkg-table-overflow.txt" "$CNS/tab-kv-blocks.txt"; do
        a="$(run_extract --emit-meta -f tsv --max-strategies 1 "$f" 2>&1)"
        b="$(_FR_LANE_BYTES=0 run_extract --emit-meta -f tsv --max-strategies 1 "$f" 2>&1)"
        c="$(_FR_BIG_BYTES=0 run_extract --emit-meta -f tsv --max-strategies 1 "$f" 2>&1)"
        assert_eq "$b" "$a" "$(basename "$f"): file lane == plain"
        assert_eq "$c" "$a" "$(basename "$f"): awk twins == plain"
    done
    a="$(_FR_CONS_GAIN=101 run_extract --emit-meta -f tsv --max-strategies 1 "$CNS/pkg-table-overflow.txt" 2>&1)"
    b="$(_FR_CONS_GAIN=101 _FR_LANE_BYTES=0 run_extract --emit-meta -f tsv --max-strategies 1 "$CNS/pkg-table-overflow.txt" 2>&1)"
    assert_eq "$b" "$a" "restored held claim: file lane == plain"
}

test_explain_preview () {
    local ex; ex="$(run_extract --explain "$CNS/pkg-table-overflow.txt" 2>/dev/null)"
    assert_contains "$ex" "CONS" "explain shows a consistency column"
    assert_contains "$ex" "Consistency: 'vertical-line'" "explain previews the hold"
    assert_contains "$ex" "REPLACES 'vertical-line'" "explain names the replacement"
}

test_relabel_is_not_a_fix () {
    # a two-word header (`Host name`) over long cells: vertical-line cuts
    # every cell, aligned-columns keeps them whole but slides the labels
    # from the third column on (`name` holds the stratum). Both read the
    # same header and disagree on what sits under it: the claim stays.
    local f="$CNS/peer-table-relabel.txt"
    assert_eq "$(_winner "$f")" "vertical-line" "relabelling alternative does not replace the claim"
    assert_contains "$(run_extract --explain "$f" 2>/dev/null)" "relabels it" "explain says why"
}

test_more_rows_is_not_a_fix () {
    # quoted CSV whose rows alternate types on purpose, with multi-line
    # cells: csv is right; aligned-columns cuts it into two glued text
    # columns — "consistent", and one row per physical line. A yield never
    # adds records.
    local f="$CNS/csv-multiline-cells.csv"
    assert_eq "$(_winner "$f")" "csv" "an alternative with more records does not replace the claim"
    assert_contains "$(run_extract --explain "$f" 2>/dev/null)" "splits the rows further" "explain says why"
}

test_classifier_families () {
    # through a pinned strategy (never held): a column of sizes with one
    # `Oct` in it is mixed; versions with a `2.0` and words with a phrase
    # are not
    printf 'NAME    SIZE   VERSION\nalpha   12K    1.2.3\nbeta    3.5M   2.0\ngamma   Oct    10.4.1\ndelta   7G     0.9.12\n' > "$TMPDIR_T/sz.txt"
    local c; c="$(_cons -s aligned-columns "$TMPDIR_T/sz.txt")"
    [[ "$c" =~ ^[0-9]+$ && "$c" -lt 95 ]] || _assert_failed "a word among sizes is a mismatch (got $c)"
    printf 'NAME           SIZE   VERSION\nalpha          12K    1.2.3\nbeta version   3.5M   2.0\ngamma          1G     10.4.1\ndelta          7G     0.9.12\n' > "$TMPDIR_T/ok.txt"
    assert_eq "$(_cons -s aligned-columns "$TMPDIR_T/ok.txt")" "100" "phrases among names, 2.0 among versions: consistent"
    printf 'HOST        ADDR             SEEN\nweb01       10.0.0.1         2026-10-13 09:12\ndb01        10.0.0.2         2026-10-12 23:05\ncache01     fe80::1          2026-10-11 07:00\n' > "$TMPDIR_T/addr.txt"
    assert_eq "$(_cons -s aligned-columns "$TMPDIR_T/addr.txt")" "100" "IPv4 + IPv6 addresses, datetimes: consistent"
}

run_test "meta carries consistency"                 test_meta_has_consistency
run_test "consistency not measured / nothing judged" test_meta_consistency_not_measured
run_test "low consistency is reported"              test_low_consistency_reported
run_test "cut words: claim yields"                  test_cut_words_yield
run_test "shifted date: claim yields"               test_shifted_date_yields
run_test "tab key/value blocks: claim yields"       test_tab_kv_blocks_yield
run_test "consistent claims are kept"               test_consistent_claims_kept
run_test "pinned / priority ranking not held"       test_pinned_and_priority_not_held
run_test "hold switches"                            test_hold_switches
run_test "a bespoke claim is not held"              test_bespoke_is_not_held
run_test "pruning stays exact"                      test_pruning_exact
run_test "file lane / awk twin routes identical"    test_routes_identical
run_test "explain previews the hold"                test_explain_preview
run_test "a relabelling alternative is no fix"     test_relabel_is_not_a_fix
run_test "an alternative with more rows is no fix"  test_more_rows_is_not_a_fix
run_test "classifier families"                      test_classifier_families

rm -rf "$TMPDIR_T"
print_summary
