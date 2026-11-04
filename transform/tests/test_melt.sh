#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

# Unit test for the imported transform module (provost/transform/melt.sh):
# _core_melt_tidy, _core_union_header, _core_align_rows. Mirrors the tidy-melt
# assertions from EnvoyCapture tests/test_run.sh, exercised directly on the
# functions rather than through the capture pipeline.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../melt.sh"

pass=0; fail=0
# Use a here-string, not `printf | grep -q`: grep -q exits on the first match and
# closes the pipe while printf is still writing, which under `set -o pipefail`
# surfaces as a SIGPIPE ("write error: Broken pipe") and flakily fails the check.
check () { if grep -qF -- "$2" <<< "$3"; then echo "  ok   $1"; pass=$((pass+1))
           else echo "  FAIL $1"; echo "       want: $2"; echo "       got: $3"; fail=$((fail+1)); fi; }
refute () { if grep -qF -- "$2" <<< "$3"; then echo "  FAIL $1 (unexpected: $2)"; fail=$((fail+1))
            else echo "  ok   $1"; pass=$((pass+1)); fi; }
# Exact whole-output comparison, for shape assertions a substring can't pin down.
same () { if [[ "$2" == "$3" ]]; then echo "  ok   $1"; pass=$((pass+1))
          else echo "  FAIL $1"; echo "       want: $(printf '%q' "$2")"; echo "       got:  $(printf '%q' "$3")"; fail=$((fail+1)); fi; }

# 1. A repeating entry<N>.<field> table melts to one row per record.
wide="$(printf 'entry1.name\tentry1.used\tentry2.name\tentry2.used\ttotal_entries\nMem\t10\tSwap\t20\t2\n')"
melted="$(_core_melt_tidy "$wide")"
check  "melt: header carries the n index"        $'n\tname\tused' "$melted"
check  "melt: one row per record (Mem)"          "1"$'\t'"Mem"  "$melted"
check  "melt: one row per record (Swap)"         "2"$'\t'"Swap" "$melted"
refute "melt: no wide entry1.* remains"          "entry1"      "$melted"

# 1b. total_entries (the engine's record count) is per-capture metadata, not a
#     variable: it is dropped rather than repeated on every row.
same   "melt: total_entries dropped from tidy rows" $'n\tname\tused\n1\tMem\t10\n2\tSwap\t20' "$melted"
kvte="$(_core_melt_tidy "$(printf 'engine\tstate\ttotal_entries\nInnoDB\tok\t1\n')")"
same   "melt: total_entries dropped from a wide snapshot too" $'engine\tstate\nInnoDB\tok' "$kvte"
same   "melt: a non-integer total_entries is data, kept" \
       $'n\tname\ttotal_entries\n1\ta\tmany' \
       "$(_core_melt_tidy "$(printf 'entry1.name\ttotal_entries\na\tmany\n')")"
same   "melt: a total_entries that is not the record count is kept" \
       $'n\tname\ttotal_entries\n1\ta\t7' \
       "$(_core_melt_tidy "$(printf 'entry1.name\ttotal_entries\na\t7\n')")"
same   "melt: a lone total_entries column is not dropped to nothing" \
       $'field\tvalue\ntotal_entries\t3' "$(_core_melt_tidy "$(printf 'total_entries\n3\n')")"
same   "melt: a genuine scalar still repeats per row" \
       $'n\tname\thost\n1\ta\th1\n2\tb\th1' \
       "$(_core_melt_tidy "$(printf 'entry1.name\tentry2.name\thost\ttotal_entries\na\tb\th1\t2\n')")"

# 2. Non-table scalar output passes through unchanged (opt-out).
scalar="$(printf 'a\tb\n1\t2\n')"
check  "melt: plain scalar passes through"       "1"$'\t'"2"   "$(_core_melt_tidy "$scalar")"

# 2b. A lone key/value observation goes to long form (field/value).
lone="$(_core_melt_tidy "$(printf 'distrobox\n1.7.2.1\n')")"
check  "melt: lone pair gets field/value header" $'field\tvalue' "$lone"
check  "melt: lone pair kept as one long row"    "distrobox"$'\t'"1.7.2.1" "$lone"

# 3. Header union + row alignment (the schema-reconcile helpers).
uni="$(_core_union_header $'#\tname\tused\tfree' $'#\tname\tused')"
check  "union: keeps all old columns"            $'#\tname\tused\tfree' "$uni"
aligned="$(printf '2\tSwap\t5\n' | _core_align_rows $'#\tname\tused' "$uni")"
check  "align: blank-fills a missing column"     "2"$'\t'"Swap"$'\t'"5"$'\t' "$aligned"

# 4. Digit-suffixed names that are NOT the engine's record prefix keep their names.
py="$(_core_melt_tidy "$(printf 'python3.path\tpython3.version\n/usr/bin/python3\t3.12.1\n')")"
same   "digit-key: python3.* stays two wide named columns" \
       $'python3.path\tpython3.version\n/usr/bin/python3\t3.12.1' "$py"
tls="$(_core_melt_tidy "$(printf 'TLSv1.2\tTLSv1.3\nenabled\tdisabled\n')")"
same   "digit-key: TLSv1.2/TLSv1.3 are names, not record 1" \
       $'TLSv1.2\tTLSv1.3\nenabled\tdisabled' "$tls"
eth="$(_core_melt_tidy "$(printf 'eth0.mtu\teth0.state\teth1.mtu\teth1.state\n1500\tUP\t9000\tDOWN\n')")"
same   "digit-key: eth0/eth1 family melts with the name kept as a key" \
       $'key\tmtu\tstate\neth0\t1500\tUP\neth1\t9000\tDOWN' "$eth"
eth10="$(_core_melt_tidy "$(printf 'eth10.mtu\teth2.mtu\thost\n1\t2\tbox\n')")"
same   "digit-key: family rows order by number (eth2 before eth10), scalars repeat" \
       $'key\tmtu\thost\neth2\t2\tbox\neth10\t1\tbox' "$eth10"
same   "digit-key: members sharing no field are not a family (pass through)" \
       $'python2.path\tpython3.version\n/usr/bin/python2\t3.12' \
       "$(_core_melt_tidy "$(printf 'python2.path\tpython3.version\n/usr/bin/python2\t3.12\n')")"
same   "digit-key: two families at once pass through" \
       $'eth0.mtu\teth1.mtu\tsda1.size\tsda2.size\n1\t2\t3\t4' \
       "$(_core_melt_tidy "$(printf 'eth0.mtu\teth1.mtu\tsda1.size\tsda2.size\n1\t2\t3\t4\n')")"
same   "digit-key: a record table next to a digit-suffixed name is not reshaped" \
       $'entry1.a\tentry2.a\tpython3.version\nx\ty\t3.12' \
       "$(_core_melt_tidy "$(printf 'entry1.a\tentry2.a\tpython3.version\nx\ty\t3.12\n')")"
same   "digit-key: other engine record labels (port, row, …) still melt to n" \
       $'n\tport\tstate\n1\t22/tcp\topen\n2\t80/tcp\tclosed' \
       "$(_core_melt_tidy "$(printf 'port1.port\tport1.state\tport2.port\tport2.state\n22/tcp\topen\t80/tcp\tclosed\n')")"

# 5. Record order is numeric (entry2 before entry10), not lexical or header order,
#    and a large table melts in well under the old O(n^2) time.
same   "order: records sort numerically" \
       $'n\tv\n2\tb\n9\tc\n10\ta' \
       "$(_core_melt_tidy "$(printf 'entry10.v\tentry2.v\tentry9.v\na\tb\tc\n')")"
same   "order: sparse ids (merge-sort path) still sort numerically" \
       $'n\tv\n5\tb\n70\tc\n1000000\ta' \
       "$(_core_melt_tidy "$(printf 'entry1000000.v\tentry5.v\tentry70.v\na\tb\tc\n')")"
same   "order: family members tying on number keep header order (stable)" \
       $'key\tv\neth1\ta\neth01\tb\neth2\tc' \
       "$(_core_melt_tidy "$(printf 'eth2.v\teth1.v\teth01.v\nc\ta\tb\n')")"
big="$(awk 'BEGIN{ n=20000; h=""; v=""
  for (k=n; k>=1; k--) { h=h (k<n?"\t":"") "entry" k ".name\tentry" k ".size"; v=v (k<n?"\t":"") "f" k "\t" k }
  print h "\ttotal_entries"; print v "\t" n }')"
t0=$(date +%s%N); bigm="$(_core_melt_tidy "$big")"; t1=$(date +%s%N)
ms=$(( (t1 - t0) / 1000000 ))
same   "order: 20k reversed records come out 1..20000 (first, last, count)" \
       $'n\tname\tsize\n1\tf1\t1\n20000\tf20000\t20000\n20001' \
       "$(printf '%s\n' "$bigm" | sed -n '1,2p;$p'; printf '%s\n' "$bigm" | wc -l | tr -d ' ')"
if [[ $ms -lt 5000 ]]; then echo "  ok   perf: 20k records melt in ${ms}ms (< 5000ms)"; pass=$((pass+1))
else echo "  FAIL perf: 20k records took ${ms}ms (want < 5000ms)"; fail=$((fail+1)); fi

# 6. Values and edge shapes.
same   "edge: values with '=', '.', spaces and quotes survive verbatim" \
       $'n\tk\n1\ta=b.c d\n2\t"q" \'s\'' \
       "$(_core_melt_tidy "$(printf 'entry1.k\tentry2.k\na=b.c d\t"q" '\''s'\''\n')")"
same   "edge: dotted field names keep everything after the first dot" \
       $'n\ta.b\n1\tx' "$(_core_melt_tidy "$(printf 'entry1.a.b\nx\n')")"
same   "edge: a missing cell in a sparse record is blank, not shifted" \
       $'n\ta\tb\n1\tx\ty\n2\t\tz' \
       "$(_core_melt_tidy "$(printf 'entry1.a\tentry1.b\tentry2.b\nx\ty\tz\n')")"
same   "edge: a record field named n does not duplicate the index column" \
       $'_n\tn\tt\n1\t0\ta\n2\t1\tb' \
       "$(_core_melt_tidy "$(printf 'entry1.n\tentry1.t\tentry2.n\tentry2.t\ttotal_entries\n0\ta\t1\tb\t2\n')")"
same   "edge: a scalar named capture does not duplicate the capture column" \
       $'_capture\tn\tv\tcapture\nc7\t1\tx\tlive' \
       "$(_core_melt_tidy "$(printf 'entry1.v\tcapture\nx\tlive\n')" c7)"
same   "edge: a non-table wide passes through byte-for-byte (even a ragged row)" \
       $'a\tb\n1\t2\t3' "$(_core_melt_tidy $'a\tb\n1\t2\t3')"
same   "edge: empty input stays empty" "" "$(_core_melt_tidy "")"
same   "edge: header-only input passes through" $'a\tb' "$(_core_melt_tidy $'a\tb')"
same   "edge: multi-row (already tidy) input passes through" \
       $'entry1.a\n1\n2' "$(_core_melt_tidy $'entry1.a\n1\n2')"
same   "edge: capture id with backslashes is kept verbatim" \
       $'capture\tn\ta\nC:\\tmp\\x\t1\tv' "$(_core_melt_tidy $'entry1.a\nv' 'C:\tmp\x')"

# 7. Union/align must not reinterpret backslashes in column names (awk -v did:
#    `a\tb` became a TAB and split one column into two).
same   "union: backslash names are not escape-processed" \
       $'x\ta\\tb\tc\\\\d' "$(_core_union_header $'x\ta\\tb' $'c\\\\d\tx')"
same   "align: backslash names still match by name" \
       $'2\t\t1' "$(printf '1\t2\n' | _core_align_rows $'a\\tb\tx' $'x\tnew\ta\\tb')"
same   "align: a repeated source name maps to its first column" \
       $'1' "$(printf '1\t2\n' | _core_align_rows $'a\ta' 'a')"
same   "union: empty old header yields the new one" $'a\tb' "$(_core_union_header '' $'a\tb')"

# 7b. A REPEATED name never loses a value (2026-10-20): a field named twice in
#     one record (a two-word header split into words: `Public IPv4`,
#     `Private IPv4`) used to keep only the later value; the second is now
#     name_2 (the first free suffix). Pass-through and scalar names likewise.
same   "dup: a field repeated in a record keeps both values" \
       $'n\tname\tip\tip_2\n1\tweb\t1.1.1.1\t10.0.0.1\n2\tdb\t2.2.2.2\t10.0.0.2' \
       "$(_core_melt_tidy $'entry1.name\tentry1.ip\tentry1.ip\tentry2.name\tentry2.ip\tentry2.ip\ttotal_entries\nweb\t1.1.1.1\t10.0.0.1\tdb\t2.2.2.2\t10.0.0.2\t2')"
same   "dup: the suffix skips a name already taken" \
       $'n\tip\tip_2\tip_3\n1\ta\tb\tc' \
       "$(_core_melt_tidy $'entry1.ip\tentry1.ip_2\tentry1.ip\na\tb\tc')"
same   "dup: an empty repeat never blanks the first value" \
       $'n\ta\ta_2\n1\tx\t\n2\ty\tz' "$(_core_melt_tidy $'entry1.a\tentry1.a\tentry2.a\tentry2.a\nx\t\ty\tz')"
same   "dup: a pass-through header gets unique names" \
       $'a\ta_2\tb\n1\t2\t3' "$(_core_melt_tidy $'a\ta\tb\n1\t2\t3')"
same   "dup: pass-through minus total_entries, unique names" \
       $'a\ta_2\n1\t2' "$(_core_melt_tidy $'a\ta\ttotal_entries\n1\t2\t5')"
same   "dup: a scalar named like a field is renamed, not merged" \
       $'n\tx\tx_2\n1\tv\ts' "$(_core_melt_tidy $'entry1.x\tx\nv\ts')"

# 7b. A data column named `#` would collide with the row id provost puts in
#     front of every dataset (PV-011): the melt renames it #_2 (the first
#     free #_K), in every output shape, and reports the rename when asked.
same   "row id: a table's # column becomes #_2 (pass-through, many rows)" \
       $'#_2\tname\n0\tether1\n1\tether2' "$(_core_melt_tidy $'#\tname\n0\tether1\n1\tether2')"
same   "row id: a record field named # becomes #_2 (melted)" \
       $'n\t#_2\tname\n1\t0\tether1\n2\t1\tether2' \
       "$(_core_melt_tidy $'entry1.#\tentry1.name\tentry2.#\tentry2.name\n0\tether1\t1\tether2')"
same   "row id: a scalar named # becomes #_2 (melted)" \
       $'n\tname\t#_2\n1\ta\t7' "$(_core_melt_tidy $'entry1.name\t#\na\t7')"
same   "row id: a one-row snapshot's # becomes #_2" \
       $'#_2\tstate\n3\tok' "$(_core_melt_tidy $'#\tstate\n3\tok')"
same   "row id: #_2 already taken -> #_3, the existing #_2 is kept" \
       $'#_3\t#_2\n1\t2' "$(_core_melt_tidy $'#\t#_2\n1\t2')"
same   "row id: two # columns -> #_2 and #_3, in order" \
       $'#_2\tx\t#_3\n1\ta\t2\n4\tb\t5' "$(_core_melt_tidy $'#\tx\t#\n1\ta\t2\n4\tb\t5')"
same   "row id: names that only contain # are left alone" \
       $'#x\tx#\t##\n1\t2\t3' "$(_core_melt_tidy $'#x\tx#\t##\n1\t2\t3')"
same   "row id: a lone # observation is a value in long form, not renamed" \
       $'field\tvalue\n#\t5' "$(_core_melt_tidy $'#\n5')"
_rn_dir="$(mktemp -d)"
printf '#\tname\n0\tether1\n' > "$_rn_dir/w"
_core_melt_tidy_file "$_rn_dir/w" "" "$_rn_dir/r" > "$_rn_dir/o"
same   "row id: the RENAMES file says #=#_2" "#=#_2" "$(cat "$_rn_dir/r")"
printf 'a\tb\n1\t2\n' > "$_rn_dir/w"
_core_melt_tidy_file "$_rn_dir/w" "" "$_rn_dir/r" > "$_rn_dir/o"
same   "row id: no rename leaves the RENAMES file empty (truncated)" "0" "$(wc -c < "$_rn_dir/r" | tr -d ' ')"
rm -rf "$_rn_dir"

# 8. _core_melt_tidy_file FILE == _core_melt_tidy "$(cat FILE)" byte for byte
#    (provost melts the engine's output file directly), including the
#    trailing-newline and empty-file shapes the $(cat) round trip normalises.
_mt_dir="$(mktemp -d)"
_mt_n=0
for _mt_in in $'entry1.name\tentry2.name\ttotal_entries\na\tb\t2\n' \
              $'entry1.name\tentry2.name\ttotal_entries\na\tb\t2' \
              $'entry1.name\tentry2.name\ttotal_entries\na\tb\t2\n\n\n' \
              $'a\tb\n\n1\t2\n' $'\n\nentry1.a\nv\n' '' $'\n' $'\n\n\n' \
              $'python3.path\tpython3.version\n/usr/bin/python3\t3.12.1\n' \
              $'total_entries\n3\n' $'distrobox\n1.7.2.1\n' $'x\n'; do
    _mt_n=$((_mt_n + 1))
    printf '%s' "$_mt_in" > "$_mt_dir/w"
    same "melt file == melt \$(cat) (#$_mt_n)" \
         "$(_core_melt_tidy "$(cat "$_mt_dir/w")" 'cap-1'; echo .)" \
         "$(_core_melt_tidy_file "$_mt_dir/w" 'cap-1'; echo .)"
done
rm -rf "$_mt_dir"

echo "melt: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
