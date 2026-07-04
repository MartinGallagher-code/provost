#!/usr/bin/env bash
# Phase-1 smoke test: inject → ls → show end-to-end in a throwaway workspace.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GLEAN="$HERE/../glean"
WS="$(mktemp -d)/.glean"
export GLEAN_WORKSPACE="$WS"

pass=0; fail=0
check () { # desc, expected-substring, actual
    if printf '%s' "$3" | grep -qF -- "$2"; then
        echo "  ok   $1"; pass=$((pass+1))
    else
        echo "  FAIL $1"; echo "       want substring: $2"; echo "       got: $3"; fail=$((fail+1))
    fi
}

free_out="$(printf '              total        used        free      shared  buff/cache   available\nMem:           15943        2456        9876         123        3610       13234\nSwap:           2047           0        2047\n' | "$GLEAN" 2>&1)"
check "free injects into 'free'" "dataset 'free'" "$free_out"

# second same-schema sample should append (4 rows total)
free_out2="$(printf '              total        used        free      shared  buff/cache   available\nMem:           16000        3050        8500         120        4330       12800\nSwap:           2047           0        2047\n' | "$GLEAN" 2>&1)"
check "second free sample appends (4 rows)" "4 row(s) total" "$free_out2"

ls_out="$("$GLEAN" ls 2>&1)"
check "ls lists 'free'" "free" "$ls_out"

show_out="$("$GLEAN" show free 2>&1)"
check "show free is tidy (per-record 'Mem' row)" "Mem" "$show_out"
check "show free melted to per-field columns" "buff_cache" "$show_out"

echo "smoke: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
