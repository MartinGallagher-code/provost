#!/usr/bin/env bash
# Phase-1 smoke test: inject → ls → show end-to-end in a throwaway workspace.
set -euo pipefail

# Hermetic: test THIS repo's bundled extract/analyze/transform trees, never a
# stale engine a developer happens to have in their global store. glean resolves
# its engine from $GLEAN_HOME first (see _find_engine), so an old ~/.glean/extract
# would otherwise shadow the bundled one and misclassify inputs. Clear every GLEAN_*
# knob the caller's shell may carry, then set only what the test needs.
unset GLEAN_HOME GLEAN_MIN_CONFIDENCE GLEAN_RECONCILE_OVERLAP GLEAN_QUIET GLEAN_MAX_INPUT
# Capture is async BY DEFAULT now; the bulk of these checks assert on the
# synchronous "→ dataset" result, so pin the foreground path for determinism
# (exactly how a script that needs the result inline would invoke glean). The
# dedicated async block below overrides this with GLEAN_ASYNC=1 / --async.
export GLEAN_ASYNC=0

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GLEAN="$HERE/../glean"
WS="$(mktemp -d)/.glean"
export GLEAN_WORKSPACE="$WS"

pass=0; fail=0
check () { # desc, expected-substring, actual
    # Here-string, not `printf | grep -q`: grep -q exits on the first match and
    # closes the pipe mid-write, which under `set -o pipefail` flakily surfaces
    # as a SIGPIPE ("Broken pipe") and fails the check.
    if grep -qF -- "$2" <<< "$3"; then
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

# rm: delete a dataset, prune its provenance rows, and (by default) purge the
# captures that fed it — all committed, with the git history preserved.
# --no-purge keeps the captures.
RMWS="$(mktemp -d)/.rm"
GLEAN_WORKSPACE="$RMWS" "$GLEAN" run printf 'a=1, b=2\n' >/dev/null 2>&1        # -> kv-pairs (capture c0001)
GLEAN_WORKSPACE="$RMWS" "$GLEAN" run printf '   total used free\nMem: 100 40 60\n' >/dev/null 2>&1  # -> free (c0002)
rm_missing="$(GLEAN_WORKSPACE="$RMWS" "$GLEAN" rm -f nope 2>&1 || true)"
check "rm refuses a missing dataset" "no such dataset: nope" "$rm_missing"
# --no-purge: dataset + provenance go, but the source capture is kept
rm_out="$(GLEAN_WORKSPACE="$RMWS" "$GLEAN" rm -f --no-purge kv-pairs 2>&1)"
check "rm reports the deletion" "deleted kv-pairs" "$rm_out"
check "rm removes the dataset file" "0" "$(ls "$RMWS/datasets" 2>/dev/null | grep -c '^kv-pairs.tsv$')"
check "rm prunes the dataset's provenance rows" "0" \
    "$(tail -n +2 "$RMWS/provenance.tsv" | grep -cw 'kv-pairs')"
check "rm keeps other datasets' provenance rows" "1" \
    "$(tail -n +2 "$RMWS/provenance.tsv" | grep -cw 'free')"
check "rm --no-purge keeps the source capture" "true" \
    "$([[ -d "$RMWS/captures/c0001" ]] && echo true)"
# default (purge on): also drops the capture dir that fed the removed dataset
GLEAN_WORKSPACE="$RMWS" "$GLEAN" rm -f free >/dev/null 2>&1
check "rm purges the source capture dir by default" "true" \
    "$([[ ! -d "$RMWS/captures/c0002" ]] && echo true)"
check "rm commits the deletion (history preserved)" "rm: deleted" \
    "$(git -C "$RMWS" log --oneline 2>&1 | head -1)"

# async is the DEFAULT: a bare inject (no --async, GLEAN_ASYNC unset) backgrounds.
DEFWS="$(mktemp -d)/.defasync"
def_out="$(printf 'x=1\n' | env -u GLEAN_ASYNC GLEAN_WORKSPACE="$DEFWS" "$GLEAN" 2>&1)"
check "async is the default for a bare inject" "queued (async" "$def_out"
# --sync forces the foreground path (prints the resulting dataset inline)
sync_out="$(printf 'p=1, q=2\n' | env -u GLEAN_ASYNC GLEAN_WORKSPACE="$DEFWS" "$GLEAN" --sync 2>&1)"
check "--sync forces the foreground path" "dataset" "$sync_out"

# --async: inject returns immediately and the capture lands in the background.
# Also a concurrency guard — several detached ingests must not collide on row #s
# (regression guard for the _lock $BASHPID fix; $$ is wrong in the async subshell).
AWS="$(mktemp -d)/.async"
async_out="$(printf '              total   used   free\nMem:  100 40 60\n' | GLEAN_WORKSPACE="$AWS" "$GLEAN" --async 2>&1)"
check "async injection reports it queued in the background" "queued (async" "$async_out"
# fire a few more without waiting, then poll for all of them to land
for i in 1 2 3 4; do printf "k=v%s\n" "$i" | GLEAN_WORKSPACE="$AWS" "$GLEAN" --async >/dev/null 2>&1; done
async_landed=0
for _try in $(seq 1 100); do
    rows=0
    [[ -f "$AWS/provenance.tsv" ]] && rows=$(($(wc -l < "$AWS/provenance.tsv") - 1))
    [[ "$rows" -ge 5 ]] && { async_landed=1; break; }
    sleep 0.2
done
check "async captures land in the background store" "1" "$async_landed"
async_dups=$(tail -n +2 "$AWS/provenance.tsv" | cut -f1 | sort | uniq -d | wc -l | tr -d ' ')
check "no duplicate row indices across async captures" "0" "$async_dups"

# --- git core: run captures a command as a commit; restore brings it back ---
check "workspace is a git repo" "true" "$([[ -d "$WS/.git" ]] && echo true)"

run_out="$("$GLEAN" run printf 'CONTAINER   COMMAND\nweb  "/entry web"\ndb  "/entry db"\n' 2>&1)"
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
( cd "$PROJ/sub" && GLEAN_HOME="$GH" GLEAN_WORKSPACE="" "$GLEAN" run printf 'CONTAINER  COMMAND\nweb  "/x"\n' >/dev/null 2>&1 )
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

# --- plugin strategies + metadata prologue (deframe integration) -----------
# An external project's strategies reach detection via --plugin-dir (or
# $GLEAN_PLUGIN_DIR) — no ~/.mfe/strategies symlink required.
PLUG="$(mktemp -d)/strategies"; mkdir -p "$PLUG"
cat > "$PLUG/frames.sh" <<'EOS'
#!/bin/bash
## Name: frames
## Description: smoke-test plugin strategy — '@@frame N status' lines
## Version: 1.0
## Priority: 10
## Sample: samples/frames/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    [[ "$text" == "@@frame "* ]] || return 1
    _STRATEGY_CONFIDENCE=95
    return 0
}

strategy_extract () {
    local text="$1" entry=0 line f2 f3 result=""
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" == "@@frame "* ]] || continue
        entry=$((entry + 1))
        f2="${line#@@frame }"; f3="${f2#* }"; f2="${f2%% *}"
        result+="entry${entry}.frame ${f2}"$'\n'
        result+="entry${entry}.status ${f3}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
EOS
FRAMES_IN="$(mktemp)"; printf '@@frame 1 ok\n@@frame 2 dropped\n' > "$FRAMES_IN"
plug_out="$("$GLEAN" --plugin-dir "$PLUG" "$FRAMES_IN" 2>&1)"
check "--plugin-dir strategy wins the parse" "dataset 'frames'" "$plug_out"
check "plugin parse carries its confidence" "conf 95" "$plug_out"
plugcap="$(ls "$WS/captures" | sort | tail -1)"
check "capture meta records the plugin dir" "$PLUG" "$(cat "$WS/captures/$plugcap/meta.tsv")"
plug_env_out="$(GLEAN_PLUGIN_DIR="$PLUG" "$GLEAN" run --sync -- cat "$FRAMES_IN" 2>&1)"
check "GLEAN_PLUGIN_DIR reaches 'run' detection too" "dataset 'frames'" "$plug_env_out"
badplug_out="$("$GLEAN" --plugin-dir /nonexistent/nowhere "$FRAMES_IN" 2>&1 || true)"
check "--plugin-dir validates the directory up front" "plugin strategy dir not found" "$badplug_out"

# A leading '#%' prologue is capture context, not data: peeled before
# detection (generic parsers stay uncorrupted), stored as context.txt, and
# 'glean source' still shows the input verbatim.
pro_out="$(printf '#%% source: deframe\n#%% frame: 7\n              total        used        free      shared  buff/cache   available\nMem:           15943        2456        9876         123        3610       13234\nSwap:           2047           0        2047\n' | "$GLEAN" 2>&1)"
check "'#%' prologue does not corrupt detection (body still 'free')" "dataset 'free'" "$pro_out"
procap="$(ls "$WS/captures" | sort | tail -1)"
check "prologue stored with the capture as context.txt" "#% frame: 7" "$(cat "$WS/captures/$procap/context.txt" 2>&1)"
check "capture meta records the context" "context" "$(cat "$WS/captures/$procap/meta.tsv")"
prorow="$(printf '%s\n' "$pro_out" | sed -n 's/.*rows #\([0-9]*\)\..*/\1/p' | head -1)"
check "source of a prologue capture is verbatim (header included)" "#% source: deframe" "$("$GLEAN" source "$prorow" 2>&1)"

# '#%' after the first data line is data, not context — nothing is peeled.
printf 'alias ll='\''ls -alF'\''\n#%% not-a-prologue\n' | "$GLEAN" >/dev/null 2>&1 || true
midcap="$(ls "$WS/captures" | sort | tail -1)"
check "mid-file '#%' is data — no context recorded" "0" "$(ls "$WS/captures/$midcap/context.txt" 2>/dev/null | grep -c .)"

echo "smoke: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
