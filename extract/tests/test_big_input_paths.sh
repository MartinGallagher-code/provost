#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Big-input fast paths: bounded detection sample, file lane, awk twins
##
## Very large inputs take different ROUTES through the engine (see
## lib/_discovery.sh: BOUNDED DETECTION SAMPLE and FILE LANE, and the
## _FR_BIG_BYTES awk twins in lib/ and the generic strategies). Every route
## must produce the same bytes as the plain bash route. The knobs force a
## route on small inputs, so each test runs one input both ways and demands
## identical stdout + winner meta:
##   bash route:  _FR_BIG_BYTES=huge  _FR_LANE_BYTES=-1  _FR_SAMPLE_BYTES=-1
##   awk route:   _FR_BIG_BYTES=0
##   lane route:  _FR_BIG_BYTES=0     _FR_LANE_BYTES=0   + sampling forced
## (The same comparison over all ~3,700 corpus inputs is the CHANGELOG proof.)
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Big-input fast paths (sample / lane / awk twins)"
echo "========================================"

BIG_TMP="$(mktemp -d)"
trap 'rm -rf "$BIG_TMP"' EXIT

# _big_run OUT ENV... -- ARGS... : run the engine with ENV, stdout+meta to OUT
_big_run () {
    local out="$1"; shift
    local -a envs=()
    while [[ $# -gt 0 && "$1" != -- ]]; do envs+=("$1"); shift; done
    shift
    env "${envs[@]}" bash "$MFE_SCRIPT" --emit-meta -f tsv --max-strategies 1 "$@" \
        > "$out" 2> "$out.err" || true
    grep '^__EXTRACT_META__' "$out.err" >> "$out" || true
}

# _big_same NAME FILE [extra engine args] — bash route vs every fast route
_big_same () {
    local name="$1" f="$2"; shift 2
    local b="$BIG_TMP/$name.bash" x
    _big_run "$b" _FR_BIG_BYTES=999999999 _FR_LANE_BYTES=-1 _FR_SAMPLE_BYTES=-1 -- "$@" "$f"
    for x in awk lane; do
        case "$x" in
            awk)    _big_run "$BIG_TMP/$name.$x" _FR_BIG_BYTES=0 _FR_LANE_BYTES=-1 _FR_SAMPLE_BYTES=-1 -- "$@" "$f" ;;
            lane)   _big_run "$BIG_TMP/$name.$x" _FR_BIG_BYTES=0 _FR_LANE_BYTES=0 _FR_SAMPLE_BYTES=0 \
                        _FR_SAMPLE_HEAD=6 _FR_SAMPLE_TAIL=3 -- "$@" "$f" ;;
        esac
        if ! cmp -s "$b" "$BIG_TMP/$name.$x"; then
            _assert_failed "$name: $x route differs from the bash route"
            diff "$b" "$BIG_TMP/$name.$x" | head -5
        fi
    done
    # the bash route must have found something to compare
    assert_contains "$(cat "$b")" "__EXTRACT_META__" "$name: meta line present"
}

# --- generated inputs (each exercises one twin; kept small so the bash route
#     stays quick) -------------------------------------------------------------
_gen () {
    local f="$BIG_TMP/$1.txt"
    case "$1" in
        ps)
            printf 'USER         PID %%CPU %%MEM    VSZ   RSS TTY      STAT START   TIME COMMAND\n'
            local i; for ((i = 1; i <= 60; i++)); do
                printf '%-10s %6d %4.1f %4.1f %6d %5d %-8s %-4s %5s %6s %s\n' \
                    root "$i" 0.$((i % 10)) 1.$((i % 7)) $((i * 1000)) $((i * 10)) '?' Ss 09:0$((i % 10)) 0:0$((i % 10)) \
                    "/usr/bin/app --flag $i"
            done ;;
        df)
            printf 'Filesystem     1K-blocks    Used Available Use%% Mounted on\n'
            local i; for ((i = 1; i <= 30; i++)); do
                printf '/dev/mapper/vg-root%d\n' "$i"
                printf '                98G    45G       48G  49%% /mnt/%d\n' "$i"
                printf 'tmpfs           %d       0      %d   0%% /run/%d\n' $((i * 100)) $((i * 100)) "$i"
            done
            printf '4 filesystems listed.\n' ;;
        units)
            printf 'SENSOR     TEMP    FAN     VOLT\n'
            printf '           (C)     (RPM)   (V)\n'
            local i; for ((i = 1; i <= 40; i++)); do printf 'cpu%-6d  %d.5    %d    1.%d\n' "$i" $((40 + i)) $((900 + i)) "$i"; done
            printf 'SENSOR     TEMP    FAN     VOLT\n'
            printf 'gpu0       55.0    1200    1.1\n' ;;
        headerless)
            local i; for ((i = 1; i <= 50; i++)); do printf 'host%d  up  %d  ok  not confined\n' "$i" $((i * 3)); done ;;
        csv)
            printf '\xef\xbb\xbfname,"Last, First",notes,amount\n'
            local i; for ((i = 1; i <= 40; i++)); do
                printf '%d,"Doe, J%d","he said ""hi""",3/4"\n' "$i" "$i"
                printf 'x%d,"multi\nline, here",  spaced  ,"1,234"\n' "$i"
                printf '\n'
            done ;;
        csvnum)
            local i; for ((i = 1; i <= 60; i++)); do printf '%d,%d.5,%d\n' "$i" "$i" $((i * 3)); done ;;
        syslog)
            local i; for ((i = 1; i <= 40; i++)); do
                printf 'Sep  %d 10:0%d:00 host kernel: [ 12.3] usb 1-1: new device  \n' $((i % 9 + 1)) $((i % 10))
                printf 'Oct 12 11:11:11 h2 CRON[%d]: (root) CMD (x  y)\n' "$i"
                printf 'Nov 01 00:00:00 h4 proc[1][2]x: a\tb   c\n'
                printf 'Jan 02 03:04:05 h6 p]x[: m\n'
            done ;;
        syslog_short)
            local i; for ((i = 1; i <= 40; i++)); do
                printf 'Oct 12 11:11:11 h2 CRON[%d]: ok\n' "$i"
                printf 'Dec 31 23:59:59 h5\n'
            done ;;
        kv)
            local i; for ((i = 1; i <= 40; i++)); do
                printf 'KEY_%d=value %d\n  * bullet_%d = spaced value  \nexport EXP_%d=/usr/bin\n' "$i" "$i" "$i" "$i"
                printf 'DATE_%d=built on: Mon Jan 26 12:30:45 2024 ok\nPAREN_%d=(some thing here) x\nEMPTY_%d=\n' "$i" "$i" "$i"
                printf '9digit_%d=x\nKEY(ctx)_%d = value\n+SIG_%d=1\n' "$i" "$i" "$i"
            done ;;
        kvglob)
            local i; for ((i = 1; i <= 40; i++)); do printf 'K%d=(a*b c) d\nL%d=(x&y z) w\n' "$i" "$i"; done ;;
        pins)
            local i; for ((i = 1; i <= 40; i++)); do printf 'pkg%d==1.%d.0\n' "$i" "$i"; done ;;
        cfg)
            local i; for ((i = 1; i <= 40; i++)); do printf 'feat%d="x"\nflag%d\n' "$i" "$i"; done ;;
        json)
            printf '[\n'
            local i; for ((i = 1; i <= 40; i++)); do
                printf '  {"id": %d, "name": "n%d", "tags": ["a", "b"], "meta": {"k": "v %d"}}%s\n' "$i" "$i" "$i" "$([[ $i -lt 40 ]] && echo ,)"
            done
            printf ']\n' ;;
        banners)
            printf 'USER  PID  CMD\n'
            local i; for ((i = 1; i <= 30; i++)); do printf 'u%d  %d  cmd%d\n' "$i" "$i" "$i"; done
            printf '== section two ==\n'
            for ((i = 1; i <= 30; i++)); do printf 'v%d  %d  cmd%d\n' "$i" "$i" "$i"; done ;;
        crlf)
            local i; printf 'NAME  SIZE  STATE\r\n'
            for ((i = 1; i <= 40; i++)); do printf 'disk%d  %dG  \033[32mok\033[0m\r\n' "$i" "$i"; done ;;
        eqtable)
            local i; for ((i = 1; i <= 40; i++)); do printf 'opt%d = value %d\n' "$i" "$i"; done ;;
        share)
            printf 'libfoo%d Foo library\n' 1 2 3
            printf 'libbar Bar library for many things\nlibbaz Bazlib\n'
            local i; for ((i = 1; i <= 20; i++)); do printf 'libm%d Middle library for many things\nlibq%d Quuxlib\n' "$i" "$i"; done
            printf 'libend%d End library\n' 1 2 3
            printf 'libzz Last library for many things\nlibyy Yylib\n' ;;
        colons)
            local i; for ((i = 1; i <= 25; i++)); do
                printf 'Name %d: foo  bar \nBuilt on: Mon Jan 26 12:30:%02d 2024 ok\n' "$i" "$i"
                printf 'Features %d:\n    PCI is supported\n    USB (very nice) here  \n' "$i"
                printf 'Lone %d:\n      only one item\n' "$i"
                printf 'Paren (some thing here) %d: x\n[ro.product.m%d]: [Pixel 8]\nURL: //host/%d\n' "$i" "$i" "$i"
                printf '9lead: x\nkey with   spaces %d  :\tval\t\na:b: c%d\n  * Bullet %d: yes\n' "$i" "$i" "$i"
                printf 'no colon line %d here\n-----\n   \nEmpty %d:   \nThis is a very long key name that goes on and on beyond fifty: v\n' "$i" "$i"
            done ;;
        colons_dash)
            local i; for ((i = 1; i <= 40; i++)); do printf -- '- Certificate %d: X.509\n  - Size: %d\n' "$i" "$i"; done ;;
        blockrec)
            local i; for ((i = 1; i <= 30; i++)); do
                printf 'Name: pkg%d\n  * Key two :  v%d  \nx = y: z\nURL: http://x/%d\nA=1\nB==2\n9k: no\nC=\t\nD=3\r\n' "$i" "$i" "$i"
                printf 'Long key that is definitely longer than fifty characters: x\n\n'
                [[ $((i % 5)) -eq 0 ]] && printf '\n\nonly text %d\n   \n\n' "$i"
            done
            printf 'Name: last' ;;
    esac > "$f"
    printf '%s\n' "$f"
}

test_routes_ps ()           { _big_same ps "$(_gen ps)"; }
test_routes_df_wrap ()      { _big_same df "$(_gen df)"; }
test_routes_units_repeat () { _big_same units "$(_gen units)"; }
test_routes_headerless ()   { _big_same headerless "$(_gen headerless)"; }
test_routes_csv_quoted ()   { _big_same csv "$(_gen csv)"; }
test_routes_csv_numeric ()  { _big_same csvnum "$(_gen csvnum)"; }
test_routes_syslog ()       { _big_same syslog "$(_gen syslog)"; }
test_routes_syslog_short () { _big_same syslog_short "$(_gen syslog_short)"; }
test_routes_equals ()       { _big_same kv "$(_gen kv)" -s equals; }
test_routes_equals_glob ()  { _big_same kvglob "$(_gen kvglob)" -s equals; }
test_routes_equals_pins ()  { _big_same pins "$(_gen pins)"; }
test_routes_equals_cfg ()   { _big_same cfg "$(_gen cfg)"; }
test_routes_json_array ()   { _big_same json "$(_gen json)"; }
test_routes_banners ()      { _big_same banners "$(_gen banners)"; }
test_routes_crlf_ansi ()    { _big_same crlf "$(_gen crlf)"; }
test_routes_eq_table ()     { _big_same eqtable "$(_gen eqtable)"; }
test_routes_colons ()       { _big_same colons "$(_gen colons)" -s colons; }
test_routes_colons_dash ()  { _big_same colons_dash "$(_gen colons_dash)" -s colons; }
test_routes_blockrec ()     { _big_same blockrec "$(_gen blockrec)" -s block-records; }

# The twins' raw strategy_extract stdout (every trailing newline included) is
# byte-identical to the bash loops', not just the tidy result.
_raw_extract () {  # STRATEGY-FILE INPUT BIG-BYTES
    bash -c '
        source "$1/lib/_log.sh"; source "$1/lib/_helpers.sh"; source "$1/lib/_techniques.sh"
        _FR_BIG_BYTES=$4; source "$1/strategies/$2"
        text="$(cat "$3")"; strategy_extract "$text"' _ "$(dirname "$MFE_SCRIPT")" "$@"
}
test_twins_raw_bytes () {
    local spec st in
    for spec in delimited/colons.sh:colons delimited/colons.sh:colons_dash delimited/block-records.sh:blockrec; do
        st="${spec%%:*}"; in="$(_gen "${spec#*:}")"
        _raw_extract "$st" "$in" 999999999 > "$BIG_TMP/raw.bash"
        _raw_extract "$st" "$in" 0 > "$BIG_TMP/raw.awk"
        if ! cmp -s "$BIG_TMP/raw.bash" "$BIG_TMP/raw.awk"; then
            _assert_failed "$spec: awk twin's raw extract differs from the bash loop"
            diff "$BIG_TMP/raw.bash" "$BIG_TMP/raw.awk" | head -5
        fi
        assert_contains "$(cat "$BIG_TMP/raw.bash")" " " "$spec: raw extract not empty"
    done
}

# --- the detection sample itself ---------------------------------------------
_sample_of () {  # TEXT [ENV...] -> prints "<sampled> <sample>"
    local t="$1"; shift
    env "$@" bash -c '
        set -o pipefail
        source "$1/lib/_log.sh"; source "$1/lib/_helpers.sh"; source "$1/lib/_discovery.sh"
        text="$2"; _detect_sample_build
        printf "%s|%s" "$_DET_SAMPLED" "$_DET_TEXT"' _ "$(dirname "$MFE_SCRIPT")" "$t"
}

test_sample_head_tail () {
    local t out
    t="$(printf 'L%d\n' $(seq 1 50))"
    out="$(_sample_of "$t" _FR_SAMPLE_BYTES=0 _FR_SAMPLE_HEAD=3 _FR_SAMPLE_TAIL=2 _FR_SAMPLE_MID=0 _FR_SAMPLE_NOVEL=0)"
    assert_eq "$out" "1|$(printf 'L1\nL2\nL3\nL49\nL50')" "head 3 + tail 2 whole lines (no middle windows)"
}

test_sample_byte_caps () {
    local t out
    t="$(printf 'line-%03d\n' $(seq 1 50))"          # 9 bytes per line with its newline
    out="$(_sample_of "$t" _FR_SAMPLE_BYTES=0 _FR_SAMPLE_HEAD=100 _FR_SAMPLE_TAIL=100 \
             _FR_SAMPLE_HEAD_BYTES=27 _FR_SAMPLE_TAIL_BYTES=18 _FR_SAMPLE_MID=0 _FR_SAMPLE_NOVEL=0)"
    assert_eq "$out" "1|$(printf 'line-001\nline-002\nline-003\nline-049\nline-050')" \
        "byte caps keep whole lines only"
}

test_sample_not_taken () {
    local t
    t="$(printf 'L%d\n' $(seq 1 50))"
    assert_eq "$(_sample_of "$t")" "0|" "small input: no sample (default threshold)"
    assert_eq "$(_sample_of "$t" _FR_SAMPLE_BYTES=0 _FR_SAMPLE_HEAD=40 _FR_SAMPLE_TAIL=10)" "0|" \
        "head + tail covering every line: no sample"
    assert_eq "$(_sample_of "$t" _FR_SAMPLE_BYTES=-1 _FR_SAMPLE_HEAD=3 _FR_SAMPLE_TAIL=2)" "0|" \
        "_FR_SAMPLE_BYTES=-1 disables sampling"
    # A JSON / XML document IS sampled for the ordinary detectors, but flagged
    # as a document so the grammar strategies (_FR_DOC_STRATEGIES) see it whole.
    assert_eq "$(_doc_of "$(printf '[\n{"a": 1},\n%.0s' $(seq 1 50))" _FR_SAMPLE_BYTES=0 _FR_SAMPLE_HEAD=3 _FR_SAMPLE_TAIL=2 _FR_SAMPLE_WIN=2)" "1|1" \
        "a JSON document is sampled and flagged as a document"
    assert_eq "$(_doc_of "  <root>$(printf '\n<x/>%.0s' $(seq 1 50))" _FR_SAMPLE_BYTES=0 _FR_SAMPLE_HEAD=3 _FR_SAMPLE_TAIL=2 _FR_SAMPLE_WIN=2)" "1|1" \
        "an XML document is sampled and flagged as a document"
    assert_eq "$(_doc_of "$(printf 'a b\n1 2\n%.0s' $(seq 1 50))" _FR_SAMPLE_BYTES=0 _FR_SAMPLE_HEAD=3 _FR_SAMPLE_TAIL=2 _FR_SAMPLE_WIN=2)" "1|0" \
        "a table is sampled and not flagged"
    assert_eq "$(_sample_of "$(printf 'x%.0s' $(seq 1 100))" _FR_SAMPLE_BYTES=0 _FR_SAMPLE_HEAD_BYTES=10)" "0|" \
        "no whole line fits the head budget: no sample"
}

# MIDDLE WINDOWS. Between head and tail the sample carries contiguous blocks
# of whole lines: EVEN windows at evenly spaced byte offsets over the body,
# and NOVEL windows where a line shape first appears (opening up to
# _FR_SAMPLE_LEAD lines early, stretched while new shapes keep coming) —
# file order kept, never overlapping, never duplicating the tail.
test_sample_mid_even_windows () {
    local t out
    t="$(printf 'L%02d\n' $(seq 1 50))"              # one shape: even windows only
    out="$(_sample_of "$t" _FR_SAMPLE_BYTES=0 _FR_SAMPLE_HEAD=3 _FR_SAMPLE_TAIL=2 \
             _FR_SAMPLE_MID=3 _FR_SAMPLE_WIN=2)"
    assert_eq "$out" "1|$(printf 'L%02d\n' 1 2 3 4 5 20 21 36 37 49 50)" \
        "3 even windows of 2 lines at 0, 1/3, 2/3 of the body, in file order"
    out="$(_sample_of "$t" _FR_SAMPLE_BYTES=0 _FR_SAMPLE_HEAD=3 _FR_SAMPLE_TAIL=2 \
             _FR_SAMPLE_MID=3 _FR_SAMPLE_WIN=4 _FR_SAMPLE_WIN_BYTES=7)"
    assert_eq "$out" "1|$(printf 'L01\nL02\nL03\nL04\nL20\nL36\nL49\nL50')" \
        "window byte cap keeps whole lines only"
    out="$(_sample_of "$t" _FR_SAMPLE_BYTES=0 _FR_SAMPLE_HEAD=3 _FR_SAMPLE_TAIL=8 \
             _FR_SAMPLE_MID=2 _FR_SAMPLE_WIN=20)"
    assert_eq "$(printf '%s' "${out#1|}" | tr '\n' ' ')" "$(printf 'L%02d ' $(seq 1 23) $(seq 28 49))L50" \
        "a window running into the tail stops before it (no duplicate lines)"
    # blank-separated records: an even window opens back at the blank line
    # just above it, and the blank above the tail joins the tail
    t="$(for i in $(seq 1 12); do printf 'rec%02d\n  a: %d\n\n' "$i" "$i"; done)"
    out="$(_sample_of "$t" _FR_SAMPLE_BYTES=0 _FR_SAMPLE_HEAD=4 _FR_SAMPLE_TAIL=2 _FR_SAMPLE_MID=2 _FR_SAMPLE_WIN=3)"
    assert_eq "$(printf '%s' "${out#1|}" | tr '\n' '/')" "rec01/  a: 1//rec02/  a: 2//rec03/  a: 3//rec08/  a: 8//rec12/  a: 12" \
        "windows end and start, and the tail starts, records whole at blank lines"
    # group lines over indented children: a window waits for a group line,
    # finishes the group in hand, and the tail backs up to its group line —
    # the head + tail sample glued grp02 to grp20's children
    t="$(for i in $(seq 1 20); do printf '* grp%02d\n  k1: %d\n  k2: x\n' "$i" "$i"; done)"
    out="$(_sample_of "$t" _FR_SAMPLE_BYTES=0 _FR_SAMPLE_HEAD=4 _FR_SAMPLE_TAIL=2 _FR_SAMPLE_MID=2 _FR_SAMPLE_WIN=2)"
    assert_eq "$(printf '%s' "${out#1|}" | tr '\n' '/')" \
        "* grp01/  k1: 1/  k2: x/* grp02/  k1: 2/  k2: x/* grp12/  k1: 12/  k2: x/* grp20/  k1: 20/  k2: x" \
        "hierarchical text: every junction joins whole groups"
    t="$(printf 'L%02d\n' $(seq 1 20); printf 'a b %d\n' $(seq 21 30); printf 'L%02d\n' $(seq 31 50))"
    assert_eq "$(_sample_of "$t" _FR_SAMPLE_BYTES=0 _FR_SAMPLE_HEAD=20 _FR_SAMPLE_TAIL=20 _FR_SAMPLE_MID=0 _FR_SAMPLE_WIN=10)" "0|" \
        "head + windows + tail covering every line: no sample"
}

test_sample_novel_window () {
    local t out
    t="$(printf 'item %d done\n' $(seq 1 40); printf 'Disks:\nNAME  SIZE  STATE\n'
         printf 'd%d  %dG  ok\n' 1 1 2 2 3 3 4 4 5 5; printf 'item %d done\n' $(seq 41 80))"
    out="$(_sample_of "$t" _FR_SAMPLE_BYTES=0 _FR_SAMPLE_HEAD=3 _FR_SAMPLE_TAIL=2 _FR_SAMPLE_MID=0 _FR_SAMPLE_WIN=4)"
    assert_eq "$(printf '%s' "${out#1|}" | tr '\n' '/')" \
        "item 1 done/item 2 done/item 3 done/item 39 done/item 40 done/Disks:/NAME  SIZE  STATE/d1  1G  ok/d2  2G  ok/item 79 done/item 80 done" \
        "a block that changes shape mid-file lands in the sample, title + header + rows contiguous"
    out="$(_sample_of "$t" _FR_SAMPLE_BYTES=0 _FR_SAMPLE_HEAD=3 _FR_SAMPLE_TAIL=2 _FR_SAMPLE_MID=0 _FR_SAMPLE_NOVEL=0 _FR_SAMPLE_WIN=4)"
    assert_eq "$(printf '%s' "${out#1|}" | tr '\n' '/')" "item 1 done/item 2 done/item 3 done/item 79 done/item 80 done" \
        "_FR_SAMPLE_MID=0 _FR_SAMPLE_NOVEL=0: the head + tail sample"
}

# MIDDLE-EVIDENCE FALSE REJECT. describe-report needs a "Section:" line, a
# header and a dash row, contiguous; here the only such block (Conditions)
# sits in the middle and the tail holds bare event rows. The head + tail
# sample hid it (describe-report rejected the sample, colons won); the middle
# windows carry it, so the sampled run picks the full-text winner.
test_sample_mid_evidence_no_false_reject () {
    local f="$BIG_TMP/describe.txt" full samp old i
    {
        printf 'Name:                   web\nNamespace:              prod\n'
        for ((i = 1; i <= 8; i++)); do printf 'Label%d:                 app=web%d\n' "$i" "$i"; done
        printf 'Conditions:\n  Type           Status  Reason\n  ----           ------  ------\n'
        printf '  Available      True    MinimumReplicasAvailable\n  Progressing    True    NewReplicaSetAvailable\n'
        for ((i = 1; i <= 8; i++)); do printf 'Extra%d:                 value %d\n' "$i" "$i"; done
        printf 'Events:\n  Type    Reason   Age  From  Message\n  ----    ------   ---  ----  -------\n'
        for ((i = 1; i <= 6; i++)); do printf '  Normal  Scaled   %dm   ctl   scaled up %d\n' "$i" "$i"; done
    } > "$f"
    _big_run "$BIG_TMP/de.full" _FR_SAMPLE_BYTES=-1 -- "$f"
    _big_run "$BIG_TMP/de.samp" _FR_SAMPLE_BYTES=0 _FR_SAMPLE_HEAD=8 _FR_SAMPLE_TAIL=4 _FR_SAMPLE_WIN=4 -- "$f"
    _big_run "$BIG_TMP/de.old" _FR_SAMPLE_BYTES=0 _FR_SAMPLE_HEAD=8 _FR_SAMPLE_TAIL=4 _FR_SAMPLE_MID=0 _FR_SAMPLE_NOVEL=0 -- "$f"
    full="$(cat "$BIG_TMP/de.full")"; samp="$(cat "$BIG_TMP/de.samp")"; old="$(grep __EXTRACT_META__ "$BIG_TMP/de.old")"
    assert_contains "$full" $'__EXTRACT_META__\tdescribe-report' "full text: describe-report wins"
    assert_eq "$samp" "$full" "sampled run (middle windows) == full-text run"
    # the reproduction: the old head + tail sample falsely rejected it
    assert_not_contains "$old" $'\tdescribe-report' "head + tail sample reproduces the false reject"
}

_doc_of () {  # TEXT [ENV...] -> prints "<sampled>|<document>"
    local t="$1"; shift
    env "$@" bash -c '
        set -o pipefail
        source "$1/lib/_log.sh"; source "$1/lib/_helpers.sh"; source "$1/lib/_discovery.sh"
        text="$2"; _detect_sample_build
        printf "%s|%s" "$_DET_SAMPLED" "$_DET_DOC"' _ "$(dirname "$MFE_SCRIPT")" "$t"
}

# A big JSON array or XML document picks the same winner, with the same
# output, whether or not the ordinary detectors screen a (tiny) sample: the
# document grammars still parse the whole, uncut document.
test_sample_documents_whole () {
    local j="$BIG_TMP/doc.json" x="$BIG_TMP/doc.xml" f n
    { printf '[\n'; local i; for ((i = 1; i < 400; i++)); do printf '  {"id": %d, "name": "n%d", "ok": true},\n' "$i" "$i"; done
      printf '  {"id": 400, "name": "n400", "ok": false}\n]\n'; } > "$j"
    { printf '<?xml version="1.0"?>\n<items>\n'; local i; for ((i = 1; i <= 400; i++)); do printf '  <item id="%d">v%d</item>\n' "$i" "$i"; done
      printf '</items>\n'; } > "$x"
    for f in "$j" "$x"; do
        n="${f##*/}"
        _big_run "$BIG_TMP/$n.whole" _FR_SAMPLE_BYTES=-1 -- "$f"
        _big_run "$BIG_TMP/$n.samp" _FR_SAMPLE_BYTES=0 _FR_SAMPLE_HEAD=3 _FR_SAMPLE_TAIL=2 -- "$f"
        if ! cmp -s "$BIG_TMP/$n.whole" "$BIG_TMP/$n.samp"; then
            _assert_failed "$n: sampled detection differs from whole-document detection"
            diff "$BIG_TMP/$n.whole" "$BIG_TMP/$n.samp" | head -5
        fi
        assert_contains "$(cat "$BIG_TMP/$n.whole")" "__EXTRACT_META__" "$n: meta line present"
    done
}

# A strategy that ACCEPTS the sample but REJECTS the full text must fall
# through exactly as before: syslog lines only at the head and tail, a
# non-syslog majority in between.
test_sample_confirm_rejects () {
    local f="$BIG_TMP/sandwich.txt" a b
    {
        local i
        for ((i = 1; i <= 5; i++)); do printf 'Oct 12 11:11:11 h2 CRON[%d]: job %d\n' "$i" "$i"; done
        for ((i = 1; i <= 60; i++)); do printf 'plain line %d with words\n' "$i"; done
        for ((i = 1; i <= 3; i++)); do printf 'Oct 12 11:11:11 h2 CRON[%d]: job %d\n' "$i" "$i"; done
    } > "$f"
    _big_run "$BIG_TMP/sw.full" _FR_SAMPLE_BYTES=-1 -- "$f"
    _big_run "$BIG_TMP/sw.samp" _FR_SAMPLE_BYTES=0 _FR_SAMPLE_HEAD=5 _FR_SAMPLE_TAIL=3 _FR_SAMPLE_MID=0 _FR_SAMPLE_NOVEL=0 -- "$f"
    a="$(cat "$BIG_TMP/sw.full")"; b="$(cat "$BIG_TMP/sw.samp")"
    assert_eq "$b" "$a" "sample-accept / full-reject falls through to the same winner"
    assert_not_contains "$b" $'__EXTRACT_META__\tsyslog' "syslog must not win on its sample"
}

# The reported confidence is the FULL-text one: equals is 75 only when >=90%
# of lines are KEY=VALUE; the sample is 100%, the full text is not.
test_sample_confidence_is_full_text () {
    local f="$BIG_TMP/eqconf.txt" a b
    {
        local i
        for ((i = 1; i <= 6; i++)); do printf 'K%d=v%d\n' "$i" "$i"; done
        for ((i = 1; i <= 20; i++)); do printf 'K%d=v%d\nfree text %d here\n' "$i" "$i" "$i"; done
        for ((i = 1; i <= 3; i++)); do printf 'T%d=v%d\n' "$i" "$i"; done
    } > "$f"
    _big_run "$BIG_TMP/ec.full" _FR_SAMPLE_BYTES=-1 -- -s equals "$f"
    _big_run "$BIG_TMP/ec.samp" _FR_SAMPLE_BYTES=0 _FR_SAMPLE_HEAD=6 _FR_SAMPLE_TAIL=3 _FR_SAMPLE_MID=0 _FR_SAMPLE_NOVEL=0 -- "$f"
    a="$(grep __EXTRACT_META__ "$BIG_TMP/ec.full")"
    _big_run "$BIG_TMP/ec.full2" _FR_SAMPLE_BYTES=-1 -- "$f"
    b="$(grep __EXTRACT_META__ "$BIG_TMP/ec.samp")"
    assert_eq "$b" "$(grep __EXTRACT_META__ "$BIG_TMP/ec.full2")" "sampled winner + confidence == full-text run"
    assert_not_contains "$a" $'\t75' "full-text equals confidence is not the sample's 75"
}

# SAMPLE SLACK: a share-threshold detector must not falsely REJECT its sample.
# pkg-config declines when one token count covers >= 60% of lines: the 10-line
# sample (head 5 + tail 5) sits exactly at 60% (6 three-token lines), the full
# text far below. Without slack the sample screen dropped pkg-config and a
# catch-all won; with it the sampled run picks the full-text winner.
test_sample_share_threshold_no_false_reject () {
    local f full samp noslack
    f="$(_gen share)"
    _big_run "$BIG_TMP/sh.full" _FR_SAMPLE_BYTES=-1 -- "$f"
    _big_run "$BIG_TMP/sh.samp" _FR_SAMPLE_BYTES=0 _FR_SAMPLE_HEAD=5 _FR_SAMPLE_TAIL=5 _FR_SAMPLE_MID=0 _FR_SAMPLE_NOVEL=0 -- "$f"
    _big_run "$BIG_TMP/sh.noslack" _FR_SAMPLE_BYTES=0 _FR_SAMPLE_HEAD=5 _FR_SAMPLE_TAIL=5 _FR_SAMPLE_SLACK=0 _FR_SAMPLE_MID=0 _FR_SAMPLE_NOVEL=0 -- "$f"
    full="$(cat "$BIG_TMP/sh.full")"; samp="$(cat "$BIG_TMP/sh.samp")"; noslack="$(grep __EXTRACT_META__ "$BIG_TMP/sh.noslack")"
    assert_contains "$full" $'__EXTRACT_META__\tpkg-config' "full text: pkg-config accepts"
    assert_eq "$samp" "$full" "sampled run == full-text run (no false reject)"
    # the reproduction: with the slack off, the sample screen rejects
    assert_not_contains "$noslack" $'\tpkg-config' "slack 0 reproduces the false reject"
}

# The slack only ever reaches the SAMPLE screen: full-text detection (and so
# every small input) sees _FR_SLACK=0 whatever _FR_SAMPLE_SLACK says.
test_sample_slack_full_text_untouched () {
    local f a b
    f="$(_gen share)"
    _big_run "$BIG_TMP/sl.a" _FR_SAMPLE_BYTES=-1 -- "$f"
    _big_run "$BIG_TMP/sl.b" _FR_SAMPLE_BYTES=-1 _FR_SAMPLE_SLACK=90 _FR_SLACK=90 -- "$f"
    a="$(cat "$BIG_TMP/sl.a")"; b="$(cat "$BIG_TMP/sl.b")"
    assert_eq "$b" "$a" "unsampled run ignores the slack knobs"
}

# The streaming dedup (seen-set) keeps exactly the lines the sort pipeline
# kept: first of each field part, in input order; a SOH byte routes the input
# through the sort pipeline itself.
test_dedup_stream_equals_sort () {
    local in="$BIG_TMP/dd.txt" soh="$BIG_TMP/dd_soh.txt" runs="$BIG_TMP/dd_runs.txt" back="$BIG_TMP/dd_back.txt" f r
    printf 'S:1\ta 1\nS:2\tb 2\n\nS:3\ta 1\nT:1\tb 2\nT:2\tc x y\nnolabel z\nU:9\tnolabel z\nS:4\ta 1 \n' > "$in"
    { cat "$in"; printf 'S:5\tq\001\nS:6\tq\001\nS:7\tr\001s\001t\n'; } > "$soh"
    # record runs (windowed seen-set) / a prefix that comes back (one set)
    printf 'S:1\tentry1.a 1\nS:2\tentry1.a 1\nS:3\tentry1.b 2\n\nS:4\tentry2.a 1\nS:5\tentry2.a 1\nS:6\tx 1\nS:7\tx 1\n' > "$runs"
    { cat "$runs"; printf 'S:8\tentry1.a 1\nS:9\tentry1.c 3\n'; } > "$back"
    for f in "$in" "$soh" "$runs" "$back"; do
        r="$(bash -c '
            source "$1/lib/_log.sh"; source "$1/lib/_helpers.sh"; source "$1/lib/_postprocess.sh"
            a="$(_dedup_pipe "$2" | od -c)"                                   # file: streaming / SOH sort
            b="$(_dedup_pipe < "$2" | od -c)"                                 # stdin, unknown SOH: sort pipeline
            c="$(_DD_SOH=0; [[ "$(cat "$2")" == *$'"'"'\001'"'"'* ]] && _DD_SOH=1; _DD_SOH=$_DD_SOH _dedup_pipe < "$2" | od -c)"
            [[ "$a" == "$b" && "$b" == "$c" ]] && echo same || { echo "$a"; echo ---; echo "$b"; echo ---; echo "$c"; }
        ' _ "$(dirname "$MFE_SCRIPT")" "$f")"
        assert_eq "$r" "same" "dedup routes agree on ${f##*/}"
    done
}

# _fr_absent_literals on a big text (64 KB prefix + one grep -F) answers
# exactly as the per-literal scan, including a literal that first occurs
# past the prefix and one that never occurs.
test_absent_literals_big () {
    local r
    r="$(bash -c '
        source "$1/lib/_helpers.sh"
        t="$(for ((i = 0; i < 5000; i++)); do printf "row %d alpha beta gamma delta\n" "$i"; done)"
        t+=$'"'"'\nlate: literal here'"'"'
        L=$'"'"'alpha\nlate: literal\nnever seen\n\001x\ngamma delta'"'"'
        a="$(_fr_absent_literals "$t" "$L")"; b="$(_fr_absent_literals_scan "$t" "$L")"
        c="$(_fr_absent_literals "${t%late*}" "$L")"; d="$(_fr_absent_literals_scan "${t%late*}" "$L")"
        printf "%s|%s|%s" "$([[ "$a" == "$b" ]] && echo same || echo diff)" "$([[ "$c" == "$d" ]] && echo same || echo diff)" "$(tr "\n\001" ",^" <<< "$a")"
    ' _ "$(dirname "$MFE_SCRIPT")")"
    assert_eq "$r" "same|same|never seen,^x," "big-text absent literals == per-literal scan"
}

# --- hint prefilters (exactness of the literal / first-atom reasoning) --------
test_hint_prefilters_sound () {
    local r
    r="$(bash -c '
        source "$1/lib/_log.sh"; source "$1/lib/_helpers.sh"; source "$1/lib/_discovery.sh"
        _hint_required_literal "RX: +bytes"; printf "%s|" "$_HRL"
        _hint_required_literal "^BSS +SIGNAL +FREQ"; printf "%s|" "$_HRL"
        _hint_required_literal "a|bcdef"; printf "%s|" "$_HRL"
        _hint_required_literal "ab*cd"; printf "%s|" "$_HRL"
        _hint_required_literal "x(abc)?yz"; printf "%s|" "$_HRL"
        _hint_first_atom "^[ipvc][ A]{3}"; printf "%s|" "$_HFA"
        _hint_first_atom "^a|b"; printf "%s|" "$_HFA"
        _hint_first_atom "^ *UNIT"; printf "%s|" "$_HFA"
        _hint_first_atom "^\\.{5,}"; printf "%s" "$_HFA"
    ' _ "$(dirname "$MFE_SCRIPT")")"
    assert_eq "$r" 'bytes|SIGNAL ||cd|yz|^[ipvc]|||^\.' "required literals / first atoms are conservative"
}

# A big input still honours its hint row through the presence prefilter.
test_hint_routing_big () {
    local f="$BIG_TMP/hint.txt"
    { printf 'avg-cpu:  %%user   %%nice %%system\n           1.00    0.00    2.00\n\n'
      printf 'Device  r/s  w/s\n'; local i; for ((i = 1; i <= 40; i++)); do printf 'sd%d  %d.0  %d.0\n' "$i" "$i" "$i"; done; } > "$f"
    _big_same hintbig "$f"
}

run_test "routes: ps table" test_routes_ps
run_test "routes: df first-cell wrap + summary line" test_routes_df_wrap
run_test "routes: units row + header repeat" test_routes_units_repeat
run_test "routes: headerless table (phrase merge)" test_routes_headerless
run_test "routes: csv quoted/multi-line/BOM" test_routes_csv_quoted
run_test "routes: csv numeric headerless" test_routes_csv_numeric
run_test "routes: syslog" test_routes_syslog
run_test "routes: syslog short lines (bash abort parity)" test_routes_syslog_short
run_test "routes: equals kv + clean_text" test_routes_equals
run_test "routes: equals glob/& paren (bash fallback)" test_routes_equals_glob
run_test "routes: equals pins" test_routes_equals_pins
run_test "routes: equals cfg" test_routes_equals_cfg
run_test "routes: json array" test_routes_json_array
run_test "routes: == banners" test_routes_banners
run_test "routes: CRLF + ANSI" test_routes_crlf_ansi
run_test "routes: ' = ' table decline" test_routes_eq_table
run_test "routes: colons kv (dates, parens, folds, brackets)" test_routes_colons
run_test "routes: colons dash bullets" test_routes_colons_dash
run_test "routes: block-records" test_routes_blockrec
run_test "twins: raw extract bytes (colons, block-records)" test_twins_raw_bytes
run_test "sample: head + tail whole lines" test_sample_head_tail
run_test "sample: byte caps" test_sample_byte_caps
run_test "sample: when not taken" test_sample_not_taken
run_test "sample: even middle windows (shape, caps, tail)" test_sample_mid_even_windows
run_test "sample: novel middle window (contiguous block)" test_sample_novel_window
run_test "sample: middle evidence — no false reject" test_sample_mid_evidence_no_false_reject
run_test "sample: documents keep whole-document grammar detection" test_sample_documents_whole
run_test "sample: accept-then-reject falls through" test_sample_confirm_rejects
run_test "sample: confidence is the full-text one" test_sample_confidence_is_full_text
run_test "sample: share threshold — no false reject (slack)" test_sample_share_threshold_no_false_reject
run_test "sample: slack never reaches full-text detection" test_sample_slack_full_text_untouched
run_test "dedup: streaming seen-set == sort pipeline" test_dedup_stream_equals_sort
run_test "presence: big-text absent literals exact" test_absent_literals_big
run_test "hints: prefilters are conservative" test_hint_prefilters_sound
run_test "hints: big input keeps its hint route" test_hint_routing_big

print_summary
