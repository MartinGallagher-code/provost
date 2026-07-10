#!/usr/bin/env bash
# Unit test for the imported transform module (glean/transform/melt.sh):
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

# 1. A repeating entry<N>.<field> table melts to one row per record.
wide="$(printf 'entry1.name\tentry1.used\tentry2.name\tentry2.used\ttotal_entries\nMem\t10\tSwap\t20\t2\n')"
melted="$(_core_melt_tidy "$wide")"
check  "melt: header carries the n index"        $'n\tname\tused' "$melted"
check  "melt: one row per record (Mem)"          "1"$'\t'"Mem"  "$melted"
check  "melt: one row per record (Swap)"         "2"$'\t'"Swap" "$melted"
check  "melt: scalar column repeated per row"    "total_entries" "$melted"
refute "melt: no wide entry1.* remains"          "entry1"      "$melted"

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

echo "melt: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
