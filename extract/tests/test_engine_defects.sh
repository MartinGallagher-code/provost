#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Engine defects found by the round-3 benchmark (2026-10-20): wrong output,
## or no output, where the right output is clearly defined.
##
## Every fixture is written for this test (none is a corpus or benchmark
## input); each reproduces the CAUSE on a different tool shape:
##   1. no output at all — a `[Section]` first line over `{…}`-ending lines
##      (json detects it, extracts nothing, and text-lines declined it as a
##      JSON document); and the catch-all net when every candidate is empty;
##   2. tsv dropped the cells of a row wider than the header (coverage 75);
##   3. a header split into words repeats a name (`IMAGE NAME` after `NAME`):
##      the second value overwrote the first (plain and tidy disagreed);
##   4. fixed-width's slicer cut the leading digit of a right-aligned value
##      one character wider than its rule run (1204736 -> 204736);
##   5. gnu-version invented `warranty 0` for a banner without that line;
##   6. the pytest-summary hint (dot-leader-row) claimed a pytest report with
##      no dot leaders because a `...` sat inside a path or a sentence.
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Engine Defect Regression Tests"
echo "========================================"

T="$(mktemp -d "${TMPDIR:-/tmp}/engine_defects.XXXXXX")"
_meta () {
    run_extract --emit-meta -f tsv --max-strategies 1 "$@" 2>&1 >/dev/null \
        | awk -F'\t' '/^__EXTRACT_META__/ { print $2; exit }'
}
_plain () { run_extract -f plain --max-strategies 1 "$@" 2>/dev/null; }

# --- 1. no output at all ------------------------------------------------------

test_section_tag_first_line_is_text () {
    cat > "$T/flags.txt" <<'EOF'
[Runtime options]
     bool UseFastPath                = true                {product} {default}
     intx MaxDepth                   = 16                  {product} {default}
    ccstr LogDir                     =                     {product} {command line}
   size_t BufferBytes                = 65536               {product} {ergonomic}
EOF
    local out; out="$(_plain "$T/flags.txt")"
    assert_contains "$out" "UseFastPath" "a [Section] first line over {…}-ending lines still gives every line"
    assert_contains "$out" "[Runtime options]" "the section line is kept"
    out="$(run_extract --explain "$T/flags.txt" 2>&1)"
    assert_match "$out" 'MATCH +text-lines' "text-lines no longer takes a closed [tag] for a JSON array"
    # a genuine JSON array is still not wrapped line by line
    printf '[\n  1,\n  2\n]\n' > "$T/arr.json"
    out="$(run_extract --explain "$T/arr.json" 2>&1)"
    assert_not_contains "$out" "MATCH    text-lines" "a multi-line JSON array is still markup"
}

test_catch_all_net_when_every_candidate_is_empty () {
    # json detects it ({ … }), extracts nothing, and every other parser
    # declines; text-lines' own detector declines the `":` markup.
    printf '{"x": broken here\nalpha\nbeta gamma delta epsilon zeta\none two\nthe "end": }\n' > "$T/broken.txt"
    local out w
    w="$(_meta "$T/broken.txt")"
    assert_eq "text-lines" "$w" "the catch-all keeps every line when every candidate is empty"
    out="$(_plain "$T/broken.txt")"
    assert_contains "$out" "entry3.A beta gamma delta epsilon zeta" "lines kept whole"
    out="$(run_extract -f plain --max-strategies 1 --rank priority "$T/broken.txt" 2>/dev/null)"
    assert_contains "$out" "entry2.A alpha" "the net applies in priority mode too"
    out="$(run_extract --multi -f tsv --max-strategies 1 "$T/broken.txt" 2>/dev/null)"
    assert_contains "$out" "text-lines" "and to --multi"
    # not when pinned, not above the catch-all's confidence, not on one prose line
    out="$(run_extract -f plain -s json "$T/broken.txt" 2>&1)"
    assert_contains "$out" "No fields extracted" "a pinned strategy is not replaced"
    out="$(run_extract -f plain --min-confidence 60 "$T/broken.txt" 2>&1)"
    assert_contains "$out" "No fields extracted" "--min-confidence above 50 keeps the net off"
    printf 'no extractable content in this one line\n' > "$T/prose.txt"
    out="$(run_extract -f plain "$T/prose.txt" 2>&1)"
    assert_contains "$out" "No fields extracted" "a single prose line stays unextracted"
}

# --- 2. tsv rows wider than the header ----------------------------------------

test_tsv_keeps_cells_past_the_header () {
    printf 'name\tsize\nalpha\t10\nbeta\t20\tx1\textra\ngamma\t30\n' > "$T/wide.tsv"
    assert_eq "tsv" "$(_meta "$T/wide.tsv")" "tsv claims it"
    local out; out="$(_plain "$T/wide.tsv")"
    assert_contains "$out" "entry2.C x1" "a cell past the header gets a positional name"
    assert_contains "$out" "entry2.D extra" "every cell past the header is kept"
    assert_contains "$out" "entry2.size 20" "the named cells are unchanged"
    # a positional name never takes a real label
    printf 'C\tB\nalpha\t10\nbeta\t20\tx1\n' > "$T/clash.tsv"
    out="$(_plain "$T/clash.tsv")"
    assert_contains "$out" "entry2.col3 x1" "a clash with a real label falls back to colN"
    # a log whose lines only sometimes carry a tab-separated suffix is not
    # TSV (most of its lines hold no tab)
    printf '12:00:01 START run-7\tqueue=default\n12:00:01 init worker pool\n12:00:02 [INFO]\tstep 1\tcompile ok\n12:00:03 still waiting for lock\n12:00:04 still waiting for lock\n12:00:05 [WARN]\tstep 2\tslow disk\n12:00:06 END run-7\n' > "$T/log.txt"
    local w; w="$(_meta "$T/log.txt")"
    [[ "$w" != tsv ]] || _assert_failed "incidental tabs on a minority of lines are not TSV (got $w)"
}

# --- 3. repeated names in one record -------------------------------------------

test_repeated_header_word_keeps_both_values () {
    cat > "$T/vms.txt" <<'EOF'
ID      NAME          SIZE      STATE    REGION     PUBLIC IP      IMAGE NAME
vm-101  build-box-1   M-2       running  eu-west-2  198.51.100.4   Rocky Linux 9
vm-102  build-box-2   M-2       running  eu-west-2  198.51.100.9   Rocky Linux 9
vm-207  jumphost      XXLARGE-12 stopped eu-west-1                 Alpine Edge
EOF
    local out; out="$(_plain "$T/vms.txt")"
    assert_contains "$out" "entry1.NAME build-box-1" "the first NAME keeps its value"
    assert_contains "$out" "entry1.NAME_2 9" "the repeated NAME becomes NAME_2"
    local n; n="$(printf '%s\n' "$out" | grep -c '^entry1\.NAME ')"
    assert_eq "1" "$n" "no record holds a name twice"
    # the tidy table agrees with the plain output
    run_extract -f tsv --max-strategies 1 "$T/vms.txt" > "$T/vms.wide" 2>/dev/null
    out="$(source "$SCRIPT_DIR/../../transform/melt.sh"; _core_melt_tidy_file "$T/vms.wide")"
    assert_contains "$out" "build-box-1" "the melt keeps the first value"
}

# --- 4. fixed-width: a right-aligned value wider than its run ------------------

test_fixed_width_never_cuts_a_value () {
    cat > "$T/files.txt" <<'EOF'
Mode   Length Name
----   ------ ----
-a--      482 a.txt
-a--  1204736 b.txt
-a----l  2210 c.txt
-a--       16 d.txt
EOF
    assert_eq "fixed-width" "$(_meta "$T/files.txt")" "fixed-width claims it"
    local out; out="$(_plain "$T/files.txt")"
    assert_contains "$out" "row2.Length 1204736" "the leading digit stays (the column widens left)"
    assert_contains "$out" "row2.Mode -a--" "the previous column does not take it"
    assert_contains "$out" "row3.Mode -a----l" "a left-aligned value wider than its run stays whole"
    assert_contains "$out" "row3.Length 2210" "and its neighbour is unchanged"
    # vertical-line cuts at label midpoints: a right-aligned value crossing
    # one goes whole to the label it overlaps
    printf 'Name      used   soft   hard\n============================\nalpha       10    50 1024000\nbeta         5      0      0\ngamma       77     10     20\n' > "$T/quota.txt"
    out="$(run_extract -f plain -s vertical-line "$T/quota.txt" 2>/dev/null)"
    assert_contains "$out" "entry1.hard 1024000" "vertical-line keeps a value that crosses a midpoint"
    assert_contains "$out" "entry1.soft 50" "and leaves its neighbour alone"
}

# --- 5. gnu-version: nothing that is not in the input --------------------------

test_gnu_version_invents_nothing () {
    cat > "$T/ver.txt" <<'EOF'
frobnicate 2.4.1
Copyright (C) 2026 Example Project
License: MIT
Written by A. Person.
EOF
    assert_eq "gnu-version" "$(_meta "$T/ver.txt")" "gnu-version claims it"
    local out; out="$(_plain "$T/ver.txt")"
    assert_not_contains "$out" "warranty" "no warranty field without a warranty line"
    assert_contains "$out" "license MIT" "the rest is unchanged"
    printf 'frobnicate 2.4.1\nCopyright (C) 2026 Example Project\nLicense: MIT\nThere is NO WARRANTY, to the extent permitted by law.\n' > "$T/ver2.txt"
    out="$(_plain "$T/ver2.txt")"
    assert_contains "$out" "warranty 1" "the NO WARRANTY line still gives warranty"
}

# --- 6. a hint target declines a near-miss --------------------------------------

test_dot_leader_needs_a_filler_token () {
    cat > "$T/collect.txt" <<'EOF'
============================= test session starts ==============================
platform linux -- Python 3.12.1, pytest-8.0.0
collected 3 items

<Module tests/test_a.py>
  <Function test_one> -- .../tests/test_a.py:12
    Check the parser, then the writer...a long docstring
  <Function test_two> -- .../tests/test_a.py:30
    Round-trip a value through ...encode/decode

======================== 3 tests collected in 0.02s =========================
EOF
    local w; w="$(_meta "$T/collect.txt")"
    [[ "$w" != pytest-summary ]] || _assert_failed "a '...' inside a path or a word is no dot leader (got $w)"
    cat > "$T/run.txt" <<'EOF'
============================= test session starts ==============================
platform linux -- Python 3.12.1, pytest-8.0.0
collected 30 items

tests/test_io.py ..........ss..        [ 46%]
tests/test_net.py ......F.........     [100%]
========================= 1 failed, 27 passed, 2 skipped =========================
EOF
    assert_eq "pytest-summary" "$(_meta "$T/run.txt")" "a real progress run is still claimed"
    local out; out="$(_plain "$T/run.txt")"
    assert_contains "$out" "entry1.B ss" "the markers stay"
    assert_contains "$out" "entry2.result 100%" "and the result"
}

run_test "1. [Section] first line is text"           test_section_tag_first_line_is_text
run_test "1. catch-all net"                           test_catch_all_net_when_every_candidate_is_empty
run_test "2. tsv keeps cells past the header"         test_tsv_keeps_cells_past_the_header
run_test "3. repeated header word keeps both values"  test_repeated_header_word_keeps_both_values
run_test "4. fixed-width never cuts a value"          test_fixed_width_never_cuts_a_value
run_test "5. gnu-version invents nothing"             test_gnu_version_invents_nothing
run_test "6. dot leaders need a filler token"         test_dot_leader_needs_a_filler_token

rm -rf "$T"
print_summary
