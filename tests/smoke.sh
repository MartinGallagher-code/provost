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
check "first free sample gets row index #1" "#1.." "$free_out"

# second same-schema sample should append with fresh global indices (#3..#4)
free_out2="$(printf '              total        used        free      shared  buff/cache   available\nMem:           16000        3050        8500         120        4330       12800\nSwap:           2047           0        2047\n' | "$GLEAN" 2>&1)"
check "second free sample gets new global indices (#3..)" "#3.." "$free_out2"

ls_out="$("$GLEAN" ls 2>&1)"
check "ls lists 'free'" "free" "$ls_out"

show_out="$("$GLEAN" show free 2>&1)"
check "show free is tidy (per-record 'Mem' row)" "Mem" "$show_out"
check "show free melted to per-field columns" "buff_cache" "$show_out"
check "show free has visible # index column" "#" "$show_out"

# provenance: row #3 maps back to the 2nd free sample's source
src_out="$("$GLEAN" source 3 2>&1)"
check "source #3 resolves to a capture" "from capture" "$src_out"
check "source #3 shows the 2nd sample's original input (used 3050)" "3050" "$src_out"

# --- git core: run captures a command as a commit; restore brings it back ---
check "workspace is a git repo" "true" "$([[ -d "$WS/.git" ]] && echo true)"

run_out="$("$GLEAN" run printf 'CONTAINER   CPU %%\nweb  12.5%%\ndb  3.2%%\n' 2>&1)"
check "run captures a command (docker-ps)" "docker-ps" "$run_out"

log_out="$("$GLEAN" log 2>&1)"
check "log lists the run capture with its command" "printf" "$log_out"

# a capture id is tagged as a real git commit
tags="$(git -C "$WS" tag 2>&1)"
check "capture is a tagged git commit" "capture-c" "$tags"

# restore an earlier capture, then return to latest
restore_out="$("$GLEAN" restore c0001 2>&1)"
check "restore brings a capture back up" "brought up c0001" "$restore_out"
latest_out="$("$GLEAN" restore latest 2>&1)"
check "restore latest returns to the tip" "latest" "$latest_out"

# --- concurrency: parallel writers to a fresh shared store stay consistent ---
CWS="$(mktemp -d)/shared"
for i in 1 2 3 4 5 6; do ( GLEAN_WORKSPACE="$CWS" "$GLEAN" run printf "k=v$i\n" >/dev/null 2>&1 ) & done
wait
dup="$(tail -n +2 "$CWS/provenance.tsv" 2>/dev/null | cut -f1 | sort | uniq -d | wc -l | tr -d ' ')"
n="$(tail -n +2 "$CWS/provenance.tsv" 2>/dev/null | wc -l | tr -d ' ')"
check "6 concurrent captures all recorded" "6" "$n"
check "no duplicate row indices under concurrency" "0" "$dup"

echo "smoke: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
