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
    out="$(_sample_of "$t" _FR_SAMPLE_BYTES=0 _FR_SAMPLE_HEAD=3 _FR_SAMPLE_TAIL=2)"
    assert_eq "$out" "1|$(printf 'L1\nL2\nL3\nL49\nL50')" "head 3 + tail 2 whole lines"
}

test_sample_byte_caps () {
    local t out
    t="$(printf 'line-%03d\n' $(seq 1 50))"          # 9 bytes per line with its newline
    out="$(_sample_of "$t" _FR_SAMPLE_BYTES=0 _FR_SAMPLE_HEAD=100 _FR_SAMPLE_TAIL=100 \
             _FR_SAMPLE_HEAD_BYTES=27 _FR_SAMPLE_TAIL_BYTES=18)"
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
    assert_eq "$(_sample_of "$(printf '[\n{"a": 1},\n%.0s' $(seq 1 50))" _FR_SAMPLE_BYTES=0 _FR_SAMPLE_HEAD=3 _FR_SAMPLE_TAIL=2)" "0|" \
        "a JSON document is never cut"
    assert_eq "$(_sample_of "  <root>$(printf '\n<x/>%.0s' $(seq 1 50))" _FR_SAMPLE_BYTES=0 _FR_SAMPLE_HEAD=3 _FR_SAMPLE_TAIL=2)" "0|" \
        "an XML document is never cut"
    assert_eq "$(_sample_of "$(printf 'x%.0s' $(seq 1 100))" _FR_SAMPLE_BYTES=0 _FR_SAMPLE_HEAD_BYTES=10)" "0|" \
        "no whole line fits the head budget: no sample"
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
    _big_run "$BIG_TMP/sw.samp" _FR_SAMPLE_BYTES=0 _FR_SAMPLE_HEAD=5 _FR_SAMPLE_TAIL=3 -- "$f"
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
    _big_run "$BIG_TMP/ec.samp" _FR_SAMPLE_BYTES=0 _FR_SAMPLE_HEAD=6 _FR_SAMPLE_TAIL=3 -- "$f"
    a="$(grep __EXTRACT_META__ "$BIG_TMP/ec.full")"
    _big_run "$BIG_TMP/ec.full2" _FR_SAMPLE_BYTES=-1 -- "$f"
    b="$(grep __EXTRACT_META__ "$BIG_TMP/ec.samp")"
    assert_eq "$b" "$(grep __EXTRACT_META__ "$BIG_TMP/ec.full2")" "sampled winner + confidence == full-text run"
    assert_not_contains "$a" $'\t75' "full-text equals confidence is not the sample's 75"
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
run_test "sample: head + tail whole lines" test_sample_head_tail
run_test "sample: byte caps" test_sample_byte_caps
run_test "sample: when not taken" test_sample_not_taken
run_test "sample: accept-then-reject falls through" test_sample_confirm_rejects
run_test "sample: confidence is the full-text one" test_sample_confidence_is_full_text
run_test "hints: prefilters are conservative" test_hint_prefilters_sound
run_test "hints: big input keeps its hint route" test_hint_routing_big

print_summary
