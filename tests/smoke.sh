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

# stats: the bundled analyze engine computes summary statistics on a dataset
stats_out="$("$GLEAN" stats free 2>&1)"
check "stats produces summary statistics" "Summary stats" "$stats_out"
check "stats computes a mean over the column" "Mean" "$stats_out"

# schema reconciliation: a trimmed same-type capture (>=60% column overlap)
# unions into the base dataset instead of splitting to free.v2
RWS="$(mktemp -d)/.recon"
GLEAN_WORKSPACE="$RWS" "$GLEAN" run printf '              total   used   free   shared   buff/cache   available\nMem:  15943   2456   9876   123   3610   13234\n' >/dev/null 2>&1
GLEAN_WORKSPACE="$RWS" "$GLEAN" run printf '              total   used   free\nMem:  16000   3050   8500\n' >/dev/null 2>&1
recon_ls="$(ls "$RWS/datasets" 2>&1)"
check "trimmed capture reconciles into 'free' (no variant)" "free.tsv" "$recon_ls"
check "no free.v2 variant was created" "1" "$(ls "$RWS/datasets" | grep -c '^free')"
# the reconciled dataset holds both rows, blank-filled
check "reconciled dataset holds both captures' rows" "8500" "$(GLEAN_WORKSPACE="$RWS" "$GLEAN" show free 2>&1)"

# unsorted: a held-back capture is stored base64-encoded, but 'show'/'triage'
# render it decoded (readable), not as a raw base64 blob
UWS="$(mktemp -d)/.unsorted"
GLEAN_WORKSPACE="$UWS" "$GLEAN" --min-confidence 101 <<<'a=1;b=2' >/dev/null 2>&1
unsorted_show="$(GLEAN_WORKSPACE="$UWS" "$GLEAN" show unsorted 2>&1)"
check "show unsorted decodes the raw input (readable)" "a=1;b=2" "$unsorted_show"
check "show unsorted does not print the base64 blob" "0" \
    "$(printf '%s' "$unsorted_show" | grep -cF 'YT0xO2I9Mgo=')"
unsorted_triage="$(GLEAN_WORKSPACE="$UWS" "$GLEAN" triage 2>&1)"
check "triage decodes the raw input (readable)" "a=1;b=2" "$unsorted_triage"

# install + symlink launcher: glean must find its bundled trees when run via a
# symlink on PATH (regression guard for the GLEAN_ROOT symlink-resolution fix)
IPREFIX="$(mktemp -d)/opt"
PREFIX="$IPREFIX" bash "$HERE/../install.sh" >/dev/null 2>&1
LWS="$(mktemp -d)/.launch"
launch_out="$(GLEAN_WORKSPACE="$LWS" "$IPREFIX/bin/glean" run printf 'a=1, b=2\n' 2>&1)"
check "glean runs via the installed symlink launcher" "dataset" "$launch_out"
PREFIX="$IPREFIX" bash "$HERE/../install.sh" --uninstall >/dev/null 2>&1

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

# --- Stage B: controlled directories route captures locally -----------------
GH="$(mktemp -d)/global"
PROJ="$(mktemp -d)/proj"; mkdir -p "$PROJ/sub"; echo hi > "$PROJ/file.txt"
ctl_out="$(cd "$PROJ" && GLEAN_HOME="$GH" GLEAN_WORKSPACE="" "$GLEAN" control 2>&1)"
check "control marks a directory" "controlling" "$ctl_out"
# capture from a SUBDIR must route to the project instance, not the global store
( cd "$PROJ/sub" && GLEAN_HOME="$GH" GLEAN_WORKSPACE="" "$GLEAN" run printf 'CONTAINER  CPU\nweb  1\n' >/dev/null 2>&1 )
check "capture from subdir lands in the controlled instance" "docker-ps" "$(ls "$PROJ/.glean/datasets" 2>&1)"
check "capture from subdir did NOT touch the global store" "0" "$(ls "$GH/datasets" 2>/dev/null | grep -c .)"
check "directory context manifest was captured" "file.txt" "$(cat "$PROJ/.glean/context/manifest.tsv" 2>&1)"
inst_out="$(GLEAN_HOME="$GH" GLEAN_WORKSPACE="" "$GLEAN" instances 2>&1)"
check "instances lists the controlled dir" "$PROJ" "$inst_out"

# --- Stage C: export / import round-trip preserves datasets + provenance ----
BUNDLE="$(mktemp -d)/store.bundle"
exp_out="$("$GLEAN" export "$BUNDLE" 2>&1)"
check "export writes a bundle" "exported store" "$exp_out"
check "bundle file exists" "true" "$([[ -f "$BUNDLE" ]] && echo true)"
DEST="$(mktemp -d)/imported"
imp_out="$(GLEAN_WORKSPACE="" "$GLEAN" import "$BUNDLE" "$DEST" 2>&1)"
check "import reconstitutes the store" "imported" "$imp_out"
check "imported store lists the free dataset" "free" "$(GLEAN_WORKSPACE="$DEST" "$GLEAN" ls 2>&1)"
# provenance survives the move: row #1's original source is browsable in the copy
check "imported store preserves row #1 source" "Mem" "$(GLEAN_WORKSPACE="$DEST" "$GLEAN" source 1 2>&1)"

echo "smoke: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
