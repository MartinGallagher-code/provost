#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

# Unit test for provost/transform/types.sh (PV-040, column types): each cell's
# kind, a column's type from its cells, the join across captures (widening,
# mixed, never narrowing), rebuilding a dataset's record from its rows, the
# file's own form, and a sample of the corpus goldens checked by hand and
# frozen in types-corpus.tsv. Runs under whatever `awk` is first on PATH
# (mawk on Ubuntu; CI runs it under mawk and gawk).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../types.sh"
ROOT="$(cd "$HERE/../.." && pwd)"

pass=0; fail=0
same () { if [[ "$2" == "$3" ]]; then echo "  ok   $1"; pass=$((pass+1))
          else echo "  FAIL $1"; echo "       want: $(printf '%q' "$2")"; echo "       got:  $(printf '%q' "$3")"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

# kind VALUE -> the cell's kind ("-": not judged)
kind () { printf '%s\n' "$1" | _core_types_leaf; }
# col TYPESFILE NAME -> "type share cells counts set_by" of column NAME
col () { awk -F'\t' -v c="$2" '$1 == c { print $2, $3, $4, $5, $6 }' "$1"; }
# ds FILE ROW... -> a dataset: '#', 'capture', then the columns of the first
# ROW (its header); each ROW tab-separated
ds () { local f="$1"; shift; printf '%s\n' "$@" > "$f"; }

echo "== each cell's kind"
while IFS='|' read -r v want; do
    same "kind of '$v'" "$want" "$(kind "$v")"
done <<'EOF'
42|integer
-7|integer
1,234|integer
3.14|decimal
.5|decimal
1,234.5|decimal
37%|percent
12.5 %|percent
10:23|time
00:05:01|time
10:23 PM|time
30ms|duration
5m|duration
1h30m|duration
5 days|duration
2-03:04:05|duration
26:00:00|duration
20G|quantity
5M|quantity
1.5 KiB|quantity
100MB/s|quantity
64Mi|quantity
$5|quantity
2026-11-13|datetime
Nov 13 10:00|datetime
2026-11-13T10:00Z|datetime
Mon|datetime
5 days ago|datetime
2024.01.15|datetime
13.11.2026|datetime
10.0.0.1|address
1.2.3.4|address
::1|address
aa:bb:cc:dd:ee:ff|address
10.0.0.1:443|address
2.4.1|version
v1.0|version
1.2.3-rc1|version
2024.1.0|version
0x1f|hex
3f2a9c1|hex
550e8400-e29b-41d4-a716-446655440000|hex
/usr/bin|path
~/x|path
http://example.org/a|path
yes|boolean
off|boolean
enabled|boolean
hello|text
two words|text
8,1|text
-|-
n/a|-
none|-
<none>|-
?|-
|-
EOF

echo "== a column's type"
# one capture, its cells as given
one () {
    local hdr=$'#\tcapture\tv' r i=0
    { printf '%s\n' "$hdr"; for r in "$@"; do i=$((i+1)); printf '%d\tc0001\t%s\n' "$i" "$r"; done; } > "$T/one.tsv"
    rm -f "$T/one.types"; _core_types_update "$T/one.types" "$T/one.tsv"
    col "$T/one.types" v
}
same "integers" "integer 100 3 integer=3 c0001" "$(one 1 2 3)"
same "integers and a decimal: decimal" "decimal 100 3 integer=2,decimal=1 c0001" "$(one 1 2 3.5)"
same "numbers and sizes: quantity" "quantity 100 3 integer=1,quantity=2 c0001" "$(one 0 20G 1.5K)"
same "numbers and per cents: percent" "percent 100 3 integer=1,percent=2 c0001" "$(one 0 5% 7%)"
same "per cents and sizes: quantity" "quantity 100 2 percent=1,quantity=1 c0001" "$(one 5% 3G)"
same "clock readings: time" "time 100 2 time=2 c0001" "$(one 10:23 00:05)"
same "clock readings and a day count: duration" "duration 100 2 time=1,duration=1 c0001" "$(one 05:23 2-03:04:05)"
same "clock readings and dates: datetime" "datetime 100 2 time=1,datetime=1 c0001" "$(one 10:23 2026-11-13)"
same "paths and words: text" "text 100 2 path=1,text=1 c0001" "$(one /usr/bin sshd)"
same "blanks and placeholders are not judged" "integer 100 2 integer=2 c0001" "$(one 1 '' - n/a 2)"
same "no value at all: empty" "empty  0  " "$(one '' -)"
same "9 integers and a word: integer, 90%" "integer 90 10 integer=9,text=1 c0001" "$(one 1 2 3 4 5 6 7 8 9 x)"
same "8 integers and 2 words: mixed" "mixed  10 integer=8,text=2 c0001" "$(one 1 2 3 4 5 6 7 8 x z)"
same "mostly words, some numbers: text" "text 60 5 integer=2,text=3 c0001" "$(one a b c 1 2)"
same "half numbers, half dates: mixed" "mixed  4 integer=2,datetime=2 c0001" "$(one 1 2 2026-01-01 2026-01-02)"
# a dotted quad whose parts are all at most 255 is read as an address
same "dotted quads and versions: text" "text 100 2 address=1,version=1 c0001" "$(one 1.2.3.4 1.2.3)"

echo "== across captures"
# rec CAPID ROW... : file one more capture's rows (column v, and w) into
# $T/m.tsv and record it; prints the record of v
rec () {
    local c="$1" r n; shift
    [[ -f "$T/m.tsv" ]] || printf '#\tcapture\tv\tw\n' > "$T/m.tsv"
    n=$(( $(wc -l < "$T/m.tsv") ))
    printf '#\tcapture\tv\tw\n' > "$T/cap.tsv"
    for r in "$@"; do printf '%d\t%s\t%s\tz\n' "$n" "$c" "$r" >> "$T/cap.tsv"; n=$((n+1)); done
    tail -n +2 "$T/cap.tsv" >> "$T/m.tsv"
    _core_types_update "$T/m.types" "$T/m.tsv" "$T/cap.tsv" "$c"
    col "$T/m.types" v
}
rm -f "$T/m.tsv" "$T/m.types"
same "c1: integers" "integer 100 2 integer=2 c0001" "$(rec c0001 1 2)"
same "c2: a decimal widens it" "decimal 100 3 integer=2,decimal=1 c0002" "$(rec c0002 2.5)"
same "c3: integers again never narrow it" "decimal 100 13 integer=12,decimal=1 c0002" "$(rec c0003 1 2 3 4 5 6 7 8 9 10)"
same "c4: sizes widen it to quantity" "quantity 100 15 integer=12,decimal=1,quantity=2 c0004" "$(rec c0004 3G 4K)"
same "c5: a word among many numbers: still quantity, share down" "quantity 93 16 integer=12,decimal=1,quantity=2,text=1 c0004" "$(rec c0005 unlimited)"
same "c6: the cells change kind: mixed" "mixed  36 integer=12,decimal=1,quantity=2,text=21 c0006" "$(rec c0006 aa bb cc dd ee ff gg hh ii jj kk ll mm nn oo pp qq rr ss tt)"
same "c7: numbers again: it stays mixed" "mixed  136 integer=112,decimal=1,quantity=2,text=21 c0006" "$(rec c0007 $(seq 100))"
same "the other column is untouched by v's changes" "text 100 136 text=136 c0001" "$(col "$T/m.types" w)"
same "a rebuild from the rows, capture by capture, gives the same record" \
    "$(cat "$T/m.types")" "$(_core_types_update "$T/r.types" "$T/m.tsv" && cat "$T/r.types")"
rm -f "$T/m.tsv" "$T/m.types"
rec c0001 alpha beta gamma >/dev/null
same "words, then one capture of a number: text holds it" "text 75 4 integer=1,text=3 c0001" "$(rec c0002 5)"
rm -f "$T/m.tsv" "$T/m.types"
rec c0001 1 2 3 >/dev/null
same "numbers, then a capture of words: mixed" "mixed  6 integer=3,text=3 c0002" "$(rec c0002 a b c)"
rm -f "$T/m.tsv" "$T/m.types"
rec c0001 10:23 11:00 >/dev/null
same "times, then dates: datetime" "datetime 100 4 time=2,datetime=2 c0002" "$(rec c0002 2026-01-01 2026-01-02)"
same "...then a duration: mixed (a datetime holds no duration)" "mixed  14 time=2,duration=10,datetime=2 c0003" "$(rec c0003 5m 6m 7m 8m 9m 1h 2h 3h 4h 5h)"
rm -f "$T/m.tsv" "$T/m.types"
rec c0001 '' '' >/dev/null
same "an empty column takes the first capture with values" "integer 100 1 integer=1 c0002" "$(rec c0002 7)"

echo "== the file"
ds "$T/d.tsv" $'#\tcapture\tn\tb\ta' $'1\tc0001\t1\tx\t' $'2\tc0001\t2\ty\t'
_core_types_update "$T/d.types" "$T/d.tsv"
same "header" "$_CORE_TYPES_HDR" "$(head -1 "$T/d.types")"
same "one line a column, in the dataset's order, '#' and capture left out" "n b a" "$(tail -n +2 "$T/d.types" | cut -f1 | tr '\n' ' ' | sed 's/ $//')"
same "a column with no value is empty, with no share, counts or capture" $'a\tempty\t\t0\t\t' "$(grep '^a' "$T/d.types")"
ds "$T/d2.tsv" $'#\t_capture\tcapture\tv' $'1\tc0001\tmine\t1'
_core_types_update "$T/d2.types" "$T/d2.tsv"
same "a data column named capture is typed; provost's _capture is not" "capture v" "$(tail -n +2 "$T/d2.types" | cut -f1 | tr '\n' ' ' | sed 's/ $//')"
# a reconcile adds a column: the record follows the dataset's header
ds "$T/d.tsv" $'#\tcapture\tn\tb\ta\tnew' $'1\tc0001\t1\tx\t\t' $'2\tc0001\t2\ty\t\t' $'3\tc0002\t1\tz\t\t5'
printf '#\tcapture\tn\tb\tnew\n3\tc0002\t1\tz\t5\n' > "$T/c2.tsv"
_core_types_update "$T/d.types" "$T/d.tsv" "$T/c2.tsv" c0002
same "a column a later capture adds is appended in the dataset's order" "n b a new" "$(tail -n +2 "$T/d.types" | cut -f1 | tr '\n' ' ' | sed 's/ $//')"
same "...typed from that capture" "integer 100 1 integer=1 c0002" "$(col "$T/d.types" new)"
same "a well-formed file has no findings" "" "$(_core_types_valid "$T/d.types")"
printf 'x\ty\n' > "$T/bad1"
same "a wrong header is a finding" "its header is not column, type, share, cells, counts, set_by" "$(_core_types_valid "$T/bad1")"
{ printf '%s\n' "$_CORE_TYPES_HDR"
  printf 'a\tinteger\t100\t2\tinteger=2\tc0001\n'
  printf 'a\tinteger\t100\t2\tinteger=2\tc0001\n'
  printf 'b\tnumber\t100\t2\tinteger=2\tc0001\n'
  printf 'c\tinteger\t100\t3\tinteger=2\tc0001\n'
  printf 'd\tmixed\t50\t2\tinteger=2\tc0001\n'
  printf 'e\tinteger\t100\t2\tinteger=2\n'
} > "$T/bad2"
bad="$(_core_types_valid "$T/bad2")"
same "a column twice" 'column "a" is listed twice' "$(sed -n 1p <<< "$bad")"
same "an unknown type" 'line 4: type "number" is not one provost records' "$(sed -n 2p <<< "$bad")"
same "counts that do not add up to cells" 'line 5: counts add up to 2, cells is 3' "$(sed -n 3p <<< "$bad")"
same "...three findings at most" "3" "$(wc -l <<< "$bad" | tr -d ' ')"
{ printf '%s\n' "$_CORE_TYPES_HDR"; printf 'd\tmixed\t50\t2\tinteger=2\tc0001\n'; } > "$T/bad3"
same "a mixed column with a share" 'line 2: a mixed column has a share' "$(_core_types_valid "$T/bad3")"
{ printf '%s\n' "$_CORE_TYPES_HDR"; printf 'e\tinteger\t100\t2\tinteger=2\n'; } > "$T/bad4"
same "five fields" 'line 2: 5 fields, not 6' "$(_core_types_valid "$T/bad4")"
{ printf '%s\n' "$_CORE_TYPES_HDR"; printf 'e\tinteger\t100\t2\tint=2\tc0001\n'; } > "$T/bad5"
same "a count of no kind" 'line 2: counts names "int", not a kind' "$(_core_types_valid "$T/bad5")"
{ printf '%s\n' "$_CORE_TYPES_HDR"; printf 'e\tinteger\t101\t2\tinteger=2\tc0001\n'; } > "$T/bad6"
same "a share over 100" 'line 2: share "101" is not a per cent' "$(_core_types_valid "$T/bad6")"
{ printf '%s\n' "$_CORE_TYPES_HDR"; printf 'e\tinteger\t100\t2\tinteger=2\tc7\n'; } > "$T/bad7"
same "a set_by that is no capture id" 'line 2: set_by "c7" is not a capture id' "$(_core_types_valid "$T/bad7")"
same "an unreadable dataset leaves the record as it was" "1" "$(_core_types_update "$T/d.types" "$T/nope.tsv" >/dev/null 2>&1; echo $?)"
same "...the record unchanged" "integer 100 1 integer=1 c0002" "$(col "$T/d.types" new)"
same "...and no work file behind" "" "$(ls -A "$T" | grep '^\.types' || true)"
same "a record from a future provost's type is mixed when joined" "mixed" "$(
    { printf '%s\n' "$_CORE_TYPES_HDR"; printf 'v\tcolour\t100\t1\t\tc0001\n'; } > "$T/f.types"
    printf '#\tcapture\tv\n2\tc0002\t5\n' > "$T/f.tsv"
    _core_types_update "$T/f.types" "$T/f.tsv" "$T/f.tsv" c0002; col "$T/f.types" v | cut -d' ' -f1)"
same "a missing classifier is an error, not a guess" "1" "$(_CORE_CTYPE_AWK="" _CORE_CTYPE_FILE=/nonexistent _core_types_update "$T/x.types" "$T/d.tsv" 2>/dev/null; echo $?)"

echo "== the corpus sample (types-corpus.tsv, checked by hand)"
n=0
while IFS= read -r g; do
    f="$ROOT/tests/corpus/expected/$g.tsv"
    _core_types_update "$T/g.types" "$f"
    want="$(awk -F'\t' -v g="$g" '$1 == g { print $2 "\t" $3 }' "$HERE/types-corpus.tsv")"
    same "$g" "$want" "$(tail -n +2 "$T/g.types" | cut -f1,2)"
    n=$((n+1))
done < <(awk -F'\t' '!/^#/ && NR > 1 && $1 != "golden" && !s[$1]++ { print $1 }' "$HERE/types-corpus.tsv")
same "the sample is twelve goldens" "12" "$n"

echo
echo "types: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
