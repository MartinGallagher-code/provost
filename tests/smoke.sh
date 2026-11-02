#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

# Phase-1 smoke test: inject → ls → show end-to-end in a throwaway workspace.
set -euo pipefail

# Hermetic: clear every PROVOST_* knob the caller's shell may carry, then set
# only what the test needs. (provost loads its engines only from its own
# install dir, never from a store, so a developer's ~/.provost can't shadow the
# bundled trees — that is asserted below too.)
unset PROVOST_HOME PROVOST_MIN_CONFIDENCE PROVOST_RECONCILE_OVERLAP PROVOST_QUIET PROVOST_MAX_INPUT \
      PROVOST_LOCK_TIMEOUT PROVOST_LOCK_MAX_AGE PROVOST_MULTI PROVOST_CONTEXT_COLUMNS PROVOST_PLUGIN_DIR \
      PROVOST_AUTO_MULTI PROVOST_MIN_COVERAGE PROVOST_MIN_CONSISTENCY PROVOST_MODEL \
      PROVOST_LLM PROVOST_LLM_MODEL PROVOST_LLM_API_KEY PROVOST_LLM_BASE_URL ANTHROPIC_API_KEY
# From a non-interactive caller capture is synchronous by default anyway; pin
# the foreground path explicitly for determinism. The async blocks below
# override this with --async / env -u PROVOST_ASYNC.
export PROVOST_ASYNC=0

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROVOST="$HERE/../provost"
WS="$(mktemp -d)/.provost"
export PROVOST_WORKSPACE="$WS"

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
check_not () { # desc, forbidden-substring, actual
    if grep -qF -- "$2" <<< "$3"; then
        echo "  FAIL $1"; echo "       must NOT contain: $2"; echo "       got: $3"; fail=$((fail+1))
    else
        echo "  ok   $1"; pass=$((pass+1))
    fi
}
# Table output with runs of spaces and tabs squeezed to one space: 'show' and
# 'search' align columns with column(1) where it is installed, and print the
# TSV's tabs where it is not.
sq () { tr -s ' \t' '  '; }
# Exit status of a command (stdout/stderr discarded), without tripping set -e.
rc_of () { local rc=0; "$@" >/dev/null 2>&1 || rc=$?; echo "$rc"; }
# git on a test store with a throwaway identity (the smoke's own git use).
tgit () { git -C "$1" -c user.name=smoke -c user.email=smoke@localhost -c commit.gpgsign=false "${@:2}"; }
# The lock owner "host" string provost writes for this machine.
LOCK_HOST="${HOSTNAME:-$(uname -n)}"
_ns="$(readlink /proc/self/ns/pid 2>/dev/null || true)"; LOCK_HOST="$LOCK_HOST${_ns:+/$_ns}"
# A pid that is certainly gone.
dead_pid () { sleep 0 & local p=$!; wait "$p" 2>/dev/null || true; echo "$p"; }

free_out="$(printf '              total        used        free      shared  buff/cache   available\nMem:           15943        2456        9876         123        3610       13234\nSwap:           2047           0        2047\n' | "$PROVOST" 2>&1)"
check "free injects into 'free'" "dataset 'free'" "$free_out"
check "first free sample gets row index #1" "#1.." "$free_out"

# second same-schema sample should append with fresh global indices (#3..#4)
free_out2="$(printf '              total        used        free      shared  buff/cache   available\nMem:           16000        3050        8500         120        4330       12800\nSwap:           2047           0        2047\n' | "$PROVOST" 2>&1)"
check "second free sample gets new global indices (#3..)" "#3.." "$free_out2"

ls_out="$("$PROVOST" ls 2>&1)"
check "ls lists 'free'" "free" "$ls_out"

show_out="$("$PROVOST" show free 2>&1)"
check "show free is tidy (per-record 'Mem' row)" "Mem" "$show_out"
check "show free melted to per-field columns" "buff_cache" "$show_out"
check "show free has visible # index column" "#" "$show_out"

# provenance: row #3 maps back to the 2nd free sample's source
src_out="$("$PROVOST" source 3 2>&1)"
check "source #3 resolves to a capture" "from capture" "$src_out"
check "source #3 shows the 2nd sample's original input (used 3050)" "3050" "$src_out"

# stats: the bundled analyze engine computes summary statistics on a dataset
stats_out="$("$PROVOST" stats free 2>&1)"
check "stats produces summary statistics" "Summary stats" "$stats_out"
check "stats computes a mean over the column" "Mean" "$stats_out"

# schema reconciliation: a trimmed same-type capture (>=60% column overlap)
# unions into the base dataset instead of splitting to free.v2
RWS="$(mktemp -d)/.recon"
PROVOST_WORKSPACE="$RWS" "$PROVOST" run --name free printf '              total   used   free   shared   buff/cache   available\nMem:  15943   2456   9876   123   3610   13234\n' >/dev/null 2>&1
PROVOST_WORKSPACE="$RWS" "$PROVOST" run --name free printf '              total   used   free\nMem:  16000   3050   8500\n' >/dev/null 2>&1
recon_ls="$(ls "$RWS/datasets" 2>&1)"
check "trimmed capture reconciles into 'free' (no variant)" "free.tsv" "$recon_ls"
check "no free.v2 variant was created" "1" "$(ls "$RWS/datasets" | grep -c '^free')"
# the reconciled dataset holds both rows, blank-filled
check "reconciled dataset holds both captures' rows" "8500" "$(PROVOST_WORKSPACE="$RWS" "$PROVOST" show free 2>&1)"

# unsorted: a held-back capture is stored base64-encoded, but 'show'/'triage'
# render it decoded (readable), not as a raw base64 blob
UWS="$(mktemp -d)/.unsorted"
PROVOST_WORKSPACE="$UWS" "$PROVOST" --min-confidence 101 <<<'a=1;b=2' >/dev/null 2>&1
unsorted_show="$(PROVOST_WORKSPACE="$UWS" "$PROVOST" show unsorted 2>&1)"
check "show unsorted decodes the raw input (readable)" "a=1;b=2" "$unsorted_show"
check "show unsorted does not print the base64 blob" "0" \
    "$(grep -cF 'YT0xO2I9Mgo=' <<< "$unsorted_show" || true)"
unsorted_triage="$(PROVOST_WORKSPACE="$UWS" "$PROVOST" triage 2>&1)"
check "triage decodes the raw input (readable)" "a=1;b=2" "$unsorted_triage"
# the one-awk decoder keeps tabs/newlines escaped, one input per line
PROVOST_WORKSPACE="$UWS" "$PROVOST" --min-confidence 101 <<<$'p\tq\nsecond line' >/dev/null 2>&1
check "unsorted decode escapes embedded tabs/newlines" 'p\tq\nsecond line' \
    "$(PROVOST_WORKSPACE="$UWS" "$PROVOST" show unsorted 2>&1)"

# rm: delete a dataset, prune its provenance rows, and (by default) purge the
# captures that fed it — all committed, with the git history preserved.
# --no-purge keeps the captures.
RMWS="$(mktemp -d)/.rm"
PROVOST_WORKSPACE="$RMWS" "$PROVOST" run --name kv-pairs printf 'a=1, b=2\n' >/dev/null 2>&1        # capture c0001
PROVOST_WORKSPACE="$RMWS" "$PROVOST" run --name free printf '   total used free\nMem: 100 40 60\n' >/dev/null 2>&1  # c0002
rm_missing="$(PROVOST_WORKSPACE="$RMWS" "$PROVOST" rm -f nope 2>&1 || true)"
check "rm refuses a missing dataset" "no such dataset: nope" "$rm_missing"
# --no-purge: dataset + provenance go, but the source capture is kept
rm_out="$(PROVOST_WORKSPACE="$RMWS" "$PROVOST" rm -f --no-purge kv-pairs 2>&1)"
check "rm reports the deletion" "deleted kv-pairs" "$rm_out"
check "rm removes the dataset file" "0" "$(ls "$RMWS/datasets" 2>/dev/null | grep -c '^kv-pairs.tsv$' || true)"
check "rm prunes the dataset's provenance rows" "0" \
    "$(tail -n +2 "$RMWS/provenance.tsv" | grep -cw 'kv-pairs' || true)"
check "rm keeps other datasets' provenance rows" "1" \
    "$(tail -n +2 "$RMWS/provenance.tsv" | grep -cw 'free' || true)"
check "rm --no-purge keeps the source capture" "true" \
    "$([[ -d "$RMWS/captures/c0001" ]] && echo true)"
# default (purge on): also drops the capture dir that fed the removed dataset
PROVOST_WORKSPACE="$RMWS" "$PROVOST" rm -f free >/dev/null 2>&1
check "rm purges the source capture dir by default" "true" \
    "$([[ ! -d "$RMWS/captures/c0002" ]] && echo true)"
check "rm commits the deletion (history preserved)" "rm: deleted" \
    "$(git -C "$RMWS" log -1 --format=%s 2>&1)"
# capture ids are monotonic: after the purge of c0002 the next capture is
# c0003, never a reused c0002 (which would overwrite history/provenance)
reuse_out="$(PROVOST_WORKSPACE="$RMWS" "$PROVOST" run --name after printf 'x=1, y=2\n' 2>&1)"
check "capture ids are never reused after an rm purge" "c0003:" "$reuse_out"

# async is used only when INTERACTIVE: a bare inject from a script (stderr not
# a terminal, PROVOST_ASYNC unset) now runs in the foreground.
DEFWS="$(mktemp -d)/.defasync"
def_out="$(printf 'x=1, y=2\n' | env -u PROVOST_ASYNC PROVOST_WORKSPACE="$DEFWS" "$PROVOST" 2>&1)"
check "non-interactive bare inject is synchronous" "dataset" "$def_out"
check_not "non-interactive bare inject does not background" "queued (async" "$def_out"
# the result is visible to the very next command — no race
check "sync default: next command sees the capture" "kv-pairs" "$(PROVOST_WORKSPACE="$DEFWS" "$PROVOST" ls 2>&1)"
# --sync forces the foreground path (prints the resulting dataset inline)
sync_out="$(printf 'p=1, q=2\n' | env -u PROVOST_ASYNC PROVOST_WORKSPACE="$DEFWS" "$PROVOST" --sync 2>&1)"
check "--sync forces the foreground path" "dataset" "$sync_out"
if command -v script >/dev/null 2>&1 && script -qec true /dev/null >/dev/null 2>&1; then
    tty_out="$(script -qec "printf 'x=1\n' | env -u PROVOST_ASYNC PROVOST_WORKSPACE=$(printf '%q' "$DEFWS") bash $(printf '%q' "$PROVOST")" /dev/null 2>&1 || true)"
    check "interactive (TTY) inject defaults to background" "queued (async" "$tty_out"
    tty_help="$(script -qec "env PROVOST_WORKSPACE=$(printf '%q' "$DEFWS") bash $(printf '%q' "$PROVOST")" /dev/null 2>&1 < /dev/null || true)"
    check "bare 'provost' on a TTY prints help instead of blocking" "turn command output into data" "$tty_help"
else
    echo "  skip interactive TTY checks (no usable 'script')"
fi

# --async: inject returns immediately and the capture lands in the background.
# Also a concurrency guard — several detached ingests must not collide on row #s
# (regression guard for the _lock $BASHPID fix; $$ is wrong in the async subshell).
AWS="$(mktemp -d)/.async"
async_out="$(printf '              total   used   free\nMem:  100 40 60\n' | PROVOST_WORKSPACE="$AWS" "$PROVOST" --async 2>&1)"
check "async injection reports it queued in the background" "queued (async" "$async_out"
# fire a few more without waiting, then poll for all of them to land
for i in 1 2 3 4; do printf "k=v%s\n" "$i" | PROVOST_WORKSPACE="$AWS" "$PROVOST" --async >/dev/null 2>&1; done
async_landed=0
# 200 x 0.2s = 40s. A CI runner hosting many parallel jobs has taken >20s to
# land 5 detached ingests (one shard timed out at 100 tries while its twin
# passed); a real async breakage still fails -- zero rows stays zero forever.
for _try in $(seq 1 200); do
    rows=0
    [[ -f "$AWS/provenance.tsv" ]] && rows=$(($(wc -l < "$AWS/provenance.tsv") - 1))
    [[ "$rows" -ge 5 ]] && { async_landed=1; break; }
    sleep 0.2
done
check "async captures land in the background store" "1" "$async_landed"
async_dups=$(tail -n +2 "$AWS/provenance.tsv" | cut -f1 | sort | uniq -d | wc -l | tr -d ' ')
check "no duplicate row indices across async captures" "0" "$async_dups"
# the spool dirs of successful background captures are cleaned up
check "async spool dirs removed after success" "0" \
    "$(grep -rlF "k=v1" "${TMPDIR:-/tmp}"/provost-async.* 2>/dev/null | grep -c . || true)"

# A FAILED background capture must not vanish: it is logged in the store, the
# next command warns, and 'provost log --failed' shows (and acknowledges) it.
FWS="$(mktemp -d)/.asyncfail"
printf 'a=1, b=2\n' | PROVOST_WORKSPACE="$FWS" "$PROVOST" >/dev/null 2>&1   # initialise the store
mkdir "$FWS/.lock"; printf 'otherhost\t1\t0\t%s\n' "$(date +%s)" > "$FWS/.lock/owner"   # a live foreign lock
printf 'c=3, d=4\n' | PROVOST_WORKSPACE="$FWS" PROVOST_LOCK_TIMEOUT=1 "$PROVOST" --async >/dev/null 2>&1
for _try in $(seq 1 100); do [[ -s "$FWS/.async-failures.log" ]] && break; sleep 0.2; done
rm -rf "$FWS/.lock"
check "background failure is recorded in the store's failure log" "store is locked" "$(cat "$FWS/.async-failures.log" 2>&1)"
warn_out="$(PROVOST_WORKSPACE="$FWS" "$PROVOST" ls 2>&1)"
check "next invocation warns about the failed background capture" "background capture(s) failed" "$warn_out"
check "doctor lists failed background captures" "store is locked" "$(PROVOST_WORKSPACE="$FWS" "$PROVOST" doctor 2>&1 || true)"
failed_out="$(PROVOST_WORKSPACE="$FWS" "$PROVOST" log --failed 2>&1)"
check "log --failed shows the failure and its kept spool" "spool:" "$failed_out"
check_not "warning stops once the failure has been seen" "background capture(s) failed" \
    "$(PROVOST_WORKSPACE="$FWS" "$PROVOST" ls 2>&1)"
check "failure log is not committed (gitignored)" "0" \
    "$(git -C "$FWS" ls-files | grep -c 'async-failures' || true)"

# --- git core: run captures a command as a commit; restore brings it back ---
check "workspace is a git repo" "true" "$([[ -d "$WS/.git" ]] && echo true)"

run_out="$("$PROVOST" run printf 'CONTAINER   COMMAND\nweb  "/entry web"\ndb  "/entry db"\n' 2>&1)"
check "run captures a command (docker-ps)" "docker-ps" "$run_out"
check "run names the dataset after the command" "dataset 'printf'" "$run_out"

log_out="$("$PROVOST" log 2>&1)"
check "log lists the run capture with its command" "printf" "$log_out"

# a capture id is tagged as a real git commit
tags="$(git -C "$WS" tag 2>&1)"
check "capture is a tagged git commit" "capture-c" "$tags"

# restore an earlier capture, then return to latest
restore_out="$("$PROVOST" restore c0001 2>&1)"
check "restore brings a capture back up" "brought up c0001" "$restore_out"
# while detached, a capture would be orphaned — refused with a clear hint
detached_out="$(printf 'z=1, w=2\n' | "$PROVOST" 2>&1 || true)"
check "capture is refused while a capture is restored (detached)" "provost restore latest" "$detached_out"
check "the refused capture exits non-zero" "1" "$(printf 'z=1\n' | rc_of "$PROVOST")"
latest_out="$("$PROVOST" restore latest 2>&1)"
check "restore latest returns to the tip" "latest" "$latest_out"
check "restore rejects a malformed capture id" "2" "$(rc_of "$PROVOST" restore ../../etc)"

# --- concurrency: parallel writers to a fresh shared store stay consistent ---
CWS="$(mktemp -d)/shared"
for i in 1 2 3 4 5 6; do ( PROVOST_WORKSPACE="$CWS" "$PROVOST" run printf "k=v$i\n" >/dev/null 2>&1 ) & done
wait
dup="$(tail -n +2 "$CWS/provenance.tsv" 2>/dev/null | cut -f1 | sort | uniq -d | wc -l | tr -d ' ')"
n="$(tail -n +2 "$CWS/provenance.tsv" 2>/dev/null | wc -l | tr -d ' ')"
check "6 concurrent captures all recorded" "6" "$n"
check "no duplicate row indices under concurrency" "0" "$dup"
check "6 concurrent captures got 6 distinct capture ids" "6" "$(find "$CWS/captures" -mindepth 1 -maxdepth 1 -type d -name 'c*' | wc -l | tr -d ' ')"
check "the store lock is never committed" "0" "$(git -C "$CWS" ls-files | grep -c '^\.lock' || true)"
check "the store has a .gitignore for runtime files" ".lock" "$(cat "$CWS/.gitignore" 2>&1)"

# --- store lock: stale-lock rules --------------------------------------------
LWS="$(mktemp -d)/.lockt"
printf 'a=1, b=2\n' | PROVOST_WORKSPACE="$LWS" "$PROVOST" >/dev/null 2>&1
# same host, dead pid → stale → broken
mkdir "$LWS/.lock"; printf '%s\t%s\t0\t%s\n' "$LOCK_HOST" "$(dead_pid)" "$(date +%s)" > "$LWS/.lock/owner"
check "a same-host lock whose pid is gone is broken" "0" \
    "$(printf 'a=2\n' | PROVOST_WORKSPACE="$LWS" PROVOST_LOCK_TIMEOUT=2 rc_of "$PROVOST")"
# same host, LIVE pid (even one we may not signal) → respected
sleep 30 & live=$!
mkdir "$LWS/.lock"; printf '%s\t%s\t0\t%s\n' "$LOCK_HOST" "$live" "$(date +%s)" > "$LWS/.lock/owner"
lk_out="$(printf 'a=3\n' | PROVOST_WORKSPACE="$LWS" PROVOST_LOCK_TIMEOUT=1 "$PROVOST" 2>&1 || true)"
check "a same-host lock with a live pid is respected" "store is locked" "$lk_out"
kill "$live" 2>/dev/null || true; wait "$live" 2>/dev/null || true
rm -rf "$LWS/.lock"
# another host, fresh → can't check its pid → respected
mkdir "$LWS/.lock"; printf 'elsewhere.example/pid:[1]\t%s\t0\t%s\n' "$(dead_pid)" "$(date +%s)" > "$LWS/.lock/owner"
check "a fresh lock from another host is respected" "1" \
    "$(printf 'a=4\n' | PROVOST_WORKSPACE="$LWS" PROVOST_LOCK_TIMEOUT=1 rc_of "$PROVOST")"
check "restore takes the store lock too" "store is locked" \
    "$(PROVOST_WORKSPACE="$LWS" PROVOST_LOCK_TIMEOUT=1 "$PROVOST" restore latest 2>&1 || true)"
check "export takes the store lock too" "store is locked" \
    "$(PROVOST_WORKSPACE="$LWS" PROVOST_LOCK_TIMEOUT=1 "$PROVOST" export "$(mktemp -d)/x.bundle" 2>&1 || true)"
rm -rf "$LWS/.lock"
# another host, older than PROVOST_LOCK_MAX_AGE → stale → broken
mkdir "$LWS/.lock"; printf 'elsewhere.example/pid:[1]\t1\t0\t%s\n' "$(( $(date +%s) - 7200 ))" > "$LWS/.lock/owner"
check "a lock older than PROVOST_LOCK_MAX_AGE is broken" "0" \
    "$(printf 'a=5\n' | PROVOST_WORKSPACE="$LWS" PROVOST_LOCK_TIMEOUT=2 rc_of "$PROVOST")"
# a legacy (pre-owner-file) lock whose pid is gone is broken
mkdir "$LWS/.lock"; dead_pid > "$LWS/.lock/pid"
check "a legacy pid-file lock whose pid is gone is broken" "0" \
    "$(printf 'a=6\n' | PROVOST_WORKSPACE="$LWS" PROVOST_LOCK_TIMEOUT=2 rc_of "$PROVOST")"
check "no lock is left behind after captures" "false" "$([[ -e "$LWS/.lock" ]] && echo true || echo false)"

# --- Stage B: controlled directories route captures locally -----------------
GH="$(mktemp -d)/global"
PROJ="$(mktemp -d)/proj"; mkdir -p "$PROJ/sub"; echo hi > "$PROJ/file.txt"
ctl_out="$(cd "$PROJ" && PROVOST_HOME="$GH" PROVOST_WORKSPACE="" "$PROVOST" control 2>&1)"
check "control marks a directory" "controlling" "$ctl_out"
# capture from a SUBDIR must route to the project instance, not the global store
( cd "$PROJ/sub" && PROVOST_HOME="$GH" PROVOST_WORKSPACE="" "$PROVOST" run printf 'CONTAINER  COMMAND\nweb  "/x"\n' >/dev/null 2>&1 )
check "capture from subdir lands in the controlled instance" "printf" "$(ls "$PROJ/.provost/datasets" 2>&1)"
check "capture from subdir did NOT touch the global store" "0" "$(find "$GH/datasets" -type f 2>/dev/null | wc -l | tr -d ' ')"
check "directory context manifest was captured" "file.txt" "$(cat "$PROJ/.provost/context/manifest.tsv" 2>&1)"
# every capture in a controlled dir refreshes the snapshot (it used to die
# silently on an unset variable and never run after 'control')
echo later > "$PROJ/added-later.txt"
( cd "$PROJ" && PROVOST_HOME="$GH" PROVOST_WORKSPACE="" "$PROVOST" run printf 'k=v\n' >/dev/null 2>&1 )
check "each capture in a controlled dir updates the context snapshot" "added-later.txt" \
    "$(cat "$PROJ/.provost/context/manifest.tsv" 2>&1)"
check "the refreshed snapshot is committed with the capture" "added-later.txt" \
    "$(git -C "$PROJ/.provost" show HEAD:context/manifest.tsv 2>&1)"
# ... and commits the directory's files themselves, tagged files-<id>: the
# directory's .gitignore is honoured, a file over PROVOST_FILES_MAX_SIZE is
# only listed, and a run with nothing changed reuses the previous commit.
printf 'ignored/\n' > "$PROJ/.gitignore"; mkdir -p "$PROJ/ignored"; echo junk > "$PROJ/ignored/x"
head -c 2048 /dev/zero > "$PROJ/big.bin"
( cd "$PROJ" && PROVOST_HOME="$GH" PROVOST_WORKSPACE="" PROVOST_FILES_MAX_SIZE=1024 "$PROVOST" run printf 'k=v\n' >/dev/null 2>&1 )
fl="$(git -C "$PROJ/.provost" ls-tree -r --name-only files-c0003 2>&1)"
check "a run commits the controlled directory's files" "added-later.txt" "$fl"
check "and their contents" "later" "$(git -C "$PROJ/.provost" show files-c0003:added-later.txt 2>&1)"
check_not "the directory's .gitignore is honoured" "ignored/x" "$fl"
check_not "a file over PROVOST_FILES_MAX_SIZE is not committed" "big.bin" "$fl"
check "but it is still listed in the manifest" "big.bin" "$(git -C "$PROJ/.provost" show capture-c0003:context/manifest.tsv 2>&1)"
check_not "the store itself never goes in" ".provost" "$fl"
( cd "$PROJ" && PROVOST_HOME="$GH" PROVOST_WORKSPACE="" PROVOST_FILES_MAX_SIZE=1024 "$PROVOST" run printf 'k=v\n' >/dev/null 2>&1 )
check "a run with no file changes reuses the previous files commit" "$(git -C "$PROJ/.provost" rev-parse files-c0003)" "$(git -C "$PROJ/.provost" rev-parse files-c0004 2>&1)"
echo changed > "$PROJ/added-later.txt"
( cd "$PROJ" && PROVOST_HOME="$GH" PROVOST_WORKSPACE="" PROVOST_FILES_MAX_SIZE=1024 "$PROVOST" run printf 'k=v\n' >/dev/null 2>&1 )
check "each files commit's parent is the previous run's" "$(git -C "$PROJ/.provost" rev-parse files-c0004)" "$(git -C "$PROJ/.provost" rev-parse files-c0005^ 2>&1)"
check "so git shows what changed between runs" "added-later.txt" "$(git -C "$PROJ/.provost" diff --stat files-c0004 files-c0005 2>&1)"
check "the store's own tree holds no copy of the files" "" "$(git -C "$PROJ/.provost" status --porcelain 2>&1)"
check_not "nor does its commit" "added-later.txt" "$(git -C "$PROJ/.provost" ls-tree -r --name-only HEAD | grep -v '^context/' || true)"
( cd "$PROJ" && PROVOST_HOME="$GH" PROVOST_WORKSPACE="" PROVOST_FILES_MAX_SIZE=0 "$PROVOST" run printf 'k=v\n' >/dev/null 2>&1 )
check "PROVOST_FILES_MAX_SIZE=0 keeps no files" "no" "$(git -C "$PROJ/.provost" rev-parse -q --verify files-c0006 >/dev/null && echo yes || echo no)"
inst_out="$(PROVOST_HOME="$GH" PROVOST_WORKSPACE="" "$PROVOST" instances 2>&1)"
check "instances lists the controlled dir" "$PROJ" "$inst_out"
# re-controlling a dir the registry already lists does not duplicate it
rm -f "$PROJ/.provost/CONTROLLED"
( cd "$PROJ" && PROVOST_HOME="$GH" PROVOST_WORKSPACE="" "$PROVOST" control >/dev/null 2>&1 )
check "control does not duplicate a registry entry" "1" "$(grep -c "^$PROJ	" "$GH/instances.tsv" || true)"
# uncontrol matches the directory literally, not as a regex ('a.b' ≠ 'aXb')
RX="$(mktemp -d)"; mkdir -p "$RX/a.b" "$RX/aXb"
PROVOST_HOME="$GH" PROVOST_WORKSPACE="" "$PROVOST" control "$RX/aXb" >/dev/null 2>&1
PROVOST_HOME="$GH" PROVOST_WORKSPACE="" "$PROVOST" control "$RX/a.b" >/dev/null 2>&1
PROVOST_HOME="$GH" PROVOST_WORKSPACE="" "$PROVOST" uncontrol "$RX/a.b" >/dev/null 2>&1
check "uncontrol removes only its own directory (fixed-string match)" "$RX/aXb" "$(cat "$GH/instances.tsv")"
check_not "uncontrol removed the released directory" "$RX/a.b	" "$(cat "$GH/instances.tsv")"

# --- Stage C: export / import round-trip preserves datasets + provenance ----
BUNDLE="$(mktemp -d)/store.bundle"
exp_out="$("$PROVOST" export "$BUNDLE" 2>&1)"
check "export writes a bundle" "exported store" "$exp_out"
check "bundle file exists" "true" "$([[ -f "$BUNDLE" ]] && echo true)"
DEST="$(mktemp -d)/imported"
imp_out="$(PROVOST_WORKSPACE="" "$PROVOST" import "$BUNDLE" "$DEST" 2>&1)"
check "import reconstitutes the store" "imported" "$imp_out"
check "imported store lists the free dataset" "free" "$(PROVOST_WORKSPACE="$DEST" "$PROVOST" ls 2>&1)"
# provenance survives the move: row #1's original source is browsable in the copy
check "imported store preserves row #1 source" "Mem" "$(PROVOST_WORKSPACE="$DEST" "$PROVOST" source 1 2>&1)"
# Importing from an ordinary directory (not inside any git repository), with
# a relative bundle path: 'git bundle verify' refuses to run outside a
# repository, which once made every such import fail as "not a valid bundle".
NOREPO="$(mktemp -d)"; cp "$BUNDLE" "$NOREPO/store.bundle"
nr_out="$(cd "$NOREPO" && GIT_CEILING_DIRECTORIES="$NOREPO/.." PROVOST_WORKSPACE="" "$PROVOST" import store.bundle copy 2>&1)"
check "import works from a directory that is not a git repository" "imported" "$nr_out"
check "and the copy is a working store" "free" "$(PROVOST_WORKSPACE="$NOREPO/copy" "$PROVOST" ls 2>&1)"
printf 'not a bundle\n' > "$NOREPO/junk.bundle"
check "a file that is not a bundle is still refused" "not a valid provost export bundle" "$(cd "$NOREPO" && "$PROVOST" import junk.bundle junk 2>&1 || true)"
check "and leaves no destination behind" "absent" "$([[ -e "$NOREPO/junk" ]] || echo absent)"

# --- plugin strategies + metadata prologue (deframe integration) -----------
# An external project's strategies reach detection via --plugin-dir (or
# $PROVOST_PLUGIN_DIR) — no ~/.config/provost/strategies symlink required.
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
plug_out="$("$PROVOST" --plugin-dir "$PLUG" "$FRAMES_IN" 2>&1)"
check "--plugin-dir strategy wins the parse" "dataset 'frames'" "$plug_out"
check "plugin parse carries its confidence" "conf 95" "$plug_out"
plugcap="$(ls "$WS/captures" | sort | tail -1)"
check "capture meta records the plugin dir" "$PLUG" "$(cat "$WS/captures/$plugcap/meta.tsv")"
plug_env_out="$(PROVOST_PLUGIN_DIR="$PLUG" "$PROVOST" run --sync -- cat "$FRAMES_IN" 2>&1)"
check "PROVOST_PLUGIN_DIR reaches 'run' detection too" "strategy frames" "$plug_env_out"
badplug_out="$("$PROVOST" --plugin-dir /nonexistent/nowhere "$FRAMES_IN" 2>&1 || true)"
check "--plugin-dir validates the directory up front" "plugin strategy dir not found" "$badplug_out"

# Line coverage: a multi-section report that the ranked parse would cut to one
# section is filed whole by the engine's rescue parser (kv-report), and the
# capture records its line coverage; a capture still filed under 60% of its
# lines says so.
COV_IN="$(mktemp)"
printf 'version: 2024.3.2 linux-x64\nactivated: yes\nshims_on_path: no\n\nbuild_info:\n  Target: x86_64-unknown-linux-gnu\n  Profile: release\n\nconfig_files:\n  ~/.config/mise/config.toml\n  ~/projects/api/.tool-versions\n\ntoolset:\n  node@20.11.1\n  python@3.12.2\n  terraform@1.7.4\n' > "$COV_IN"
cov_out="$("$PROVOST" --name covrep "$COV_IN" 2>&1)"
check "a multi-section report is filed whole (rescue parser)" "strategy kv-report" "$cov_out"
check "the capture reports its line coverage" "coverage 100%" "$cov_out"
covcap="$(ls "$WS/captures" | sort | tail -1)"
check "capture meta records the coverage" "coverage	100" "$(cat "$WS/captures/$covcap/meta.tsv")"
check "list items reach the dataset" "terraform@1.7.4" "$("$PROVOST" show covrep 2>&1)"
printf 'Volume   Files   Size   Status\nvol-a    12      1.0    OK\nvol-b    13      2.0    OK\nvol-c    14      3.0    WARN\nvol-d    15      4.0    OK\nvol-e    16      5.0    OK\nvol-f    17      6.0    OK\n\nElapsed time:   01:00:12\nExit code:      0\nNext run:       2026-07-12 01:00\nOperator name:  ops team\nPool name:      main pool\nRetention:      7 days\n' > "$COV_IN"
# The quality gate holds a generic parse under 80% coverage back for triage,
# with the reason; with the gate off it is filed, and the low-coverage note
# says how little of the input reached the dataset. (--no-auto-multi: this
# input segments cleanly, see AUTO-MULTI below.)
lowcov_out="$("$PROVOST" --name lowcov --no-auto-multi "$COV_IN" 2>&1)"
check "the quality gate holds a low-coverage parse for triage" "low-coverage (" "$lowcov_out"
check "a gated capture lands in the triage bucket" "queued in 'unsorted'" "$lowcov_out"
check "triage shows the gated capture" "Retention" "$("$PROVOST" triage 2>&1)"
lowcov_out="$("$PROVOST" --name lowcov --min-coverage 0 "$COV_IN" 2>&1)"
check "--min-coverage 0 turns the gate off; the low-coverage note remains" "of the input's lines reached 'lowcov'" "$lowcov_out"
lowcov_out="$(PROVOST_MIN_COVERAGE=0 "$PROVOST" --name lowcov2 "$COV_IN" 2>&1)"
check "PROVOST_MIN_COVERAGE=0 turns the gate off too" "→ dataset 'lowcov2'" "$lowcov_out"
check "--min-coverage rejects a value over 100" "2" "$(rc_of "$PROVOST" --min-coverage 101 "$COV_IN")"
# AUTO-MULTI: before holding the parse, provost segments the input; a table and
# a key/value block that each pass the gate, and together keep every line, are
# filed as two datasets instead of being held.
AWS="$(mktemp -d)/.automulti"
am_out="$(PROVOST_WORKSPACE="$AWS" "$PROVOST" --sync "$COV_IN" 2>&1)"
check "auto-multi files a gated parse as segments" "→ 2 datasets" "$am_out"
check "the ok line says it segmented, and why" "segmented: the single parse was low-coverage (" "$am_out"
am_meta="$(cat "$AWS/captures/c0001/meta.tsv")"
check "meta records the auto-multi segmentation" "auto_multi	segmented (split): low-coverage" "$am_meta"
check "meta records the held single parse" "single_coverage	" "$am_meta"
check "meta records the parts' joint coverage" "coverage	100" "$am_meta"
check "meta records each part's coverage" "dataset_coverage	" "$am_meta"
check "a nameless segment is named by its strategy" "key-value" "$(ls "$AWS/datasets")"
# With a NAME, the part that reads the single parse's columns keeps NAME, so a
# capture that passes the gate and one that segments share one dataset.
printf 'Volume   Files   Size   Status\nvol-a    12      1.0    OK\nvol-b    13      2.0    OK\nvol-c    14      3.0    WARN\nvol-d    15      4.0    OK\nvol-e    16      5.0    OK\nvol-f    17      6.0    OK\n\nElapsed time:   01:00:12\n' > "$COV_IN.small"
PROVOST_WORKSPACE="$AWS" "$PROVOST" --sync --name volrep "$COV_IN.small" >/dev/null 2>&1
am_out="$(PROVOST_WORKSPACE="$AWS" "$PROVOST" --sync --name volrep "$COV_IN" 2>&1)"
check "with a NAME the other parts are NAME.strategy" "volrep.key-value" "$am_out"
check "the part matching the single parse continues dataset NAME" "vol-f" \
    "$(PROVOST_WORKSPACE="$AWS" "$PROVOST" show volrep 2>&1 | tail -1)"
check "both captures' table rows share dataset NAME" "2" \
    "$(grep -c 'vol-f' "$AWS/datasets/volrep.tsv")"
rm -f "$COV_IN.small"
am_out="$(PROVOST_WORKSPACE="$AWS" PROVOST_AUTO_MULTI=0 "$PROVOST" --sync "$COV_IN" 2>&1)"
check "PROVOST_AUTO_MULTI=0 holds the capture as before" "queued in 'unsorted'" "$am_out"
check "PROVOST_AUTO_MULTI must be 0 or 1" "2" "$(PROVOST_AUTO_MULTI=2 rc_of "$PROVOST" --sync "$COV_IN")"
# A split into trivial fragments (five datasets of 1-2 lines from a 9-line
# input) is declined: the capture is held, with the reason.
printf 'Region: eu-west-1\nZone: a\n\nID    STATE\ni-1   running\n\nMODE=fast\nRETRY=3\n\nname,size\nalpha,1\n\nlast check 2026-10-19 ok\n' > "$COV_IN.frag"
am_out="$(PROVOST_WORKSPACE="$AWS" "$PROVOST" --sync "$COV_IN.frag" 2>&1)"
check "a split into fragments is declined and held" "segmenting it did not help: the parts are fragments" "$am_out"
rm -f "$COV_IN.frag"

# LAYOUT MODEL (--model / PROVOST_MODEL=1): a capture the gate still holds
# after AUTO-MULTI gets the learned layout model's table, filed only when that
# table passes the same gate. Off by default. Needs python3.
check "PROVOST_MODEL must be 0 or 1" "2" "$(PROVOST_MODEL=2 rc_of "$PROVOST" --sync "$COV_IN")"
check "--model is documented" "--model" "$("$PROVOST" inject --help 2>&1)"
if command -v python3 >/dev/null 2>&1; then
    LM_IN="$HERE/benchmark/round3/inputs/005-cmake-cache-advanced-help.txt"
    LWS="$(mktemp -d)/.model"
    lm_out="$(PROVOST_WORKSPACE="$LWS" "$PROVOST" --sync "$LM_IN" 2>&1)"
    check "without --model the gated capture is held" "queued in 'unsorted'" "$lm_out"
    lm_out="$(PROVOST_WORKSPACE="$LWS" "$PROVOST" --sync --model "$LM_IN" 2>&1)"
    check "--model files the layout model's table when it passes the gate" "strategy layout-model" "$lm_out"
    check "the ok line says why the model was used" "the layout model's table passes the gate" "$lm_out"
    lm_meta="$(cat "$LWS/captures/c0002/meta.tsv")"
    check "meta records the layout model" "layout_model	filed: the engine's parse was low-coverage" "$lm_meta"
    check "meta keeps the held parse's strategy" "single_strategy	block-records" "$lm_meta"
    check "the model's values are cut from the input" "FILEPATH=/usr/bin/ar" "$(cat "$LWS/datasets/layout-model.tsv")"
    # PROVOST_LAYOUT_LM names a tiny-LM model (ml/train_lm.py or ml/export_lm.py);
    # with no model there, or no runtime for it, the trees label exactly as before.
    LWS3="$(mktemp -d)/.lmfallback"
    lm_out="$(PROVOST_WORKSPACE="$LWS3" PROVOST_LAYOUT_LM="$(mktemp -d)/no-model" "$PROVOST" --sync --model "$LM_IN" 2>&1)"
    check "with PROVOST_LAYOUT_LM naming no model, --model falls back to the trees" "strategy layout-model" "$lm_out"
    # PROVOST_LAYOUT_LM=0 keeps the trees even where a provost-model package is
    # installed; a PROVOST_PYTHON that is not there declines like no python3.
    LWS4="$(mktemp -d)/.lmzero"
    lm_out="$(PROVOST_WORKSPACE="$LWS4" PROVOST_LAYOUT_LM=0 "$PROVOST" --sync --model "$LM_IN" 2>&1)"
    check "PROVOST_LAYOUT_LM=0: --model labels with the trees" "strategy layout-model" "$lm_out"
    LWS5="$(mktemp -d)/.lmnopy"
    lm_out="$(PROVOST_WORKSPACE="$LWS5" PROVOST_PYTHON=/nonexistent/python3 "$PROVOST" --sync --model "$LM_IN" 2>&1)"
    check_not "a missing PROVOST_PYTHON: the layout model declines" "strategy layout-model" "$lm_out"
    # Declined: the model's table would keep too little; held as before, with why.
    printf '%s\n' '-- Cache values' '// Upper bound on bins per run' 'BINPACK_MAX_BINS:STRING=64' '' \
        '// Collect allocation statistics' 'BINPACK_WITH_STATS:BOOL=ON' '' '// Path to a program.' \
        'CMAKE_ADDR2LINE:FILEPATH=/usr/bin/addr2line' '' '// Path to a program.' 'CMAKE_AR:FILEPATH=/usr/bin/ar' '' \
        '// Flags used by the C compiler during all build types.' 'CMAKE_C_FLAGS:STRING=' '' \
        '// Enable/Disable output of compile commands during generation.' 'CMAKE_EXPORT_COMPILE_COMMANDS:BOOL=ON' \
        > "$COV_IN.small2"
    lm_out="$(PROVOST_WORKSPACE="$LWS" PROVOST_MODEL=1 "$PROVOST" --sync "$COV_IN.small2" 2>&1)"
    check "a model table that fails the gate is declined" "the layout model did not help:" "$lm_out"
    check "the model also tries segmenting a declined capture itself" "segmenting it itself:" "$lm_out"
    rm -f "$COV_IN.small2"
fi
rm -f "$COV_IN"

# LLM TEMPLATES (--llm / PROVOST_LLM=1): a capture the gate holds is parsed by
# a template Claude wrote for the tool, stored in the store or shipped with
# provost; with an API key and no fitting template, Claude is asked to write
# one. The API here is tests/fake_anthropic.py: no network, no key, no cost.
check "PROVOST_LLM must be 0 or 1" "2" "$(PROVOST_LLM=2 rc_of "$PROVOST" --sync "$HERE/../extract/samples/llm-template/basic.txt")"
check "--llm is documented" "--llm" "$("$PROVOST" inject --help 2>&1)"
if command -v python3 >/dev/null 2>&1; then
    LT_SAMPLE="$HERE/../extract/samples/llm-template/basic.txt"
    LT_IN="$HERE/benchmark/round3/inputs/005-cmake-cache-advanced-help.txt"
    LTD="$(mktemp -d)"; LTWS="$LTD/.llm"
    # a shipped template wins over the engine's generic parse of its tool
    lt_out="$(PROVOST_WORKSPACE="$LTWS" "$PROVOST" --sync --llm "$LT_SAMPLE" 2>&1)"
    check "a shipped template reads its tool's output" "mcstatus.players  #1..9  (strategy llm-template" "$lt_out"
    check "the template's second block is a dataset too" "mcstatus.status" "$lt_out"
    check "meta records the template" "llm_template	filed by template mcstatus.json" "$(cat "$LTWS/captures/c0001/meta.tsv")"
    # held, no key, no template: held as before, with why
    lt_out="$(PROVOST_WORKSPACE="$LTWS" "$PROVOST" --sync --llm --name cmake-cache "$LT_IN" 2>&1)"
    check "with no template and no key the capture is held" "queued in 'unsorted'" "$lt_out"
    check "the held line says the key is missing" "no API key to have Claude write one" "$lt_out"
    # learn: Claude (the fake API) writes a template, provost checks it, files, keeps it
    printf '%s' '{"id":"msg_1","type":"message","role":"assistant","model":"claude-opus-5-5","stop_reason":"end_turn","usage":{"input_tokens":1,"output_tokens":1},"content":[{"type":"text","text":"{\"format\": 1, \"tool\": \"cmake-cache\", \"detect\": \"^[A-Za-z0-9_.-]+:(?:STRING|BOOL|FILEPATH|PATH|INTERNAL|STATIC)=\", \"skip\": [\"^-- \", \"^// \"], \"blocks\": [{\"name\": \"entries\", \"kind\": \"table\", \"line\": \"^(?P<name>[A-Za-z0-9_.-]+):(?P<type>[A-Z]+)=(?P<value>.*)$\"}]}"}]}' > "$LTD/reply.json"
    python3 "$HERE/fake_anthropic.py" "$LTD/port" "$LTD/log" "$LTD/reply.json" & LT_PID=$!
    for _ in $(seq 1 50); do [[ -s "$LTD/port" ]] && break; sleep 0.1; done
    LT_URL="http://127.0.0.1:$(cat "$LTD/port")"
    lt_out="$(PROVOST_WORKSPACE="$LTWS" PROVOST_LLM_BASE_URL="$LT_URL" PROVOST_LLM_API_KEY=k-test \
        "$PROVOST" --sync --llm --name cmake-cache "$LT_IN" 2>&1)"
    check "--llm files a held capture with the template Claude wrote" "cmake-cache  #" "$lt_out"
    check "the lines it set aside that carry words are filed beside it" "cmake-cache.notes" "$lt_out"
    check "the ok line says a new template was written" "read by a new template Claude wrote (llm-templates/cmake-cache.json)" "$lt_out"
    check "the new template is committed with the capture" "llm-templates/cmake-cache.json" "$(git -C "$LTWS" show --stat HEAD 2>&1)"
    check "the template's values are cut from the input" "CMAKE_AR	FILEPATH	/usr/bin/ar" "$(cat "$LTWS/datasets/cmake-cache.tsv")"
    lt_req="$(head -n 1 "$LTD/log")"
    check "the request names the API version" '"anthropic-version": "2026-10-21"' "${lt_req,,}"
    check "the request sends the key" '"x-api-key": "k-test"' "${lt_req,,}"
    check "the request asks for refusal fallbacks" '"fallbacks": "default"' "$lt_req"
    check "the request names the model" '"model": "claude-opus-5-5"' "$lt_req"
    kill "$LT_PID" 2>/dev/null || true; wait "$LT_PID" 2>/dev/null || true
    # offline: the next capture of the tool is parsed by the stored template, no API
    lt_out="$(PROVOST_WORKSPACE="$LTWS" PROVOST_LLM_BASE_URL="http://127.0.0.1:9" PROVOST_LLM_API_KEY=k-test \
        "$PROVOST" --sync --llm --name cmake-cache "$LT_IN" 2>&1)"
    check "the next capture uses the stored template, offline" "read by template cmake-cache.json" "$lt_out"
    check "the API was called once in all" "1" "$(wc -l < "$LTD/log" | tr -d ' ')"
    # a refusal: held, with the category
    printf '%s' '{"id":"msg_2","type":"message","role":"assistant","model":"claude-opus-5-5","stop_reason":"refusal","stop_details":{"type":"refusal","category":"cyber","explanation":"x"},"usage":{"input_tokens":1,"output_tokens":0},"content":[]}' > "$LTD/reply.json"
    rm -f "$LTD/port"
    python3 "$HERE/fake_anthropic.py" "$LTD/port" "$LTD/log" "$LTD/reply.json" & LT_PID=$!
    for _ in $(seq 1 50); do [[ -s "$LTD/port" ]] && break; sleep 0.1; done
    LT_URL="http://127.0.0.1:$(cat "$LTD/port")"
    printf 'Region: eu-west-1\nZone: a\n\nID    STATE\ni-1   running\n\nMODE=fast\nRETRY=3\n\nname,size\nalpha,1\n\nlast check 2026-10-19 ok\n' > "$LTD/held.txt"
    lt_out="$(PROVOST_WORKSPACE="$LTWS" PROVOST_LLM_BASE_URL="$LT_URL" PROVOST_LLM_API_KEY=k-test \
        "$PROVOST" --sync --llm --name other-tool "$LTD/held.txt" 2>&1)"
    kill "$LT_PID" 2>/dev/null || true; wait "$LT_PID" 2>/dev/null || true
    check "a refusal leaves the capture held" "queued in 'unsorted'" "$lt_out"
    check "the held line names the refusal" "the model declined this capture (refusal: cyber)" "$lt_out"
    check_not "no template is kept after a refusal" "other-tool" "$(ls "$LTWS/llm-templates")"
    # LLM-FIRST: a GENERIC parse the gate passed is not trusted over a template
    # for the tool. With a key, Claude is asked before the heuristic is filed;
    # the template wins when it keeps the input's data lines (its own skip
    # lines aside). A title the heuristic took for data is decoration here.
    printf 'Volumes on host alpha\nNAME     SIZE   USED   MOUNT\ndata     100G   40G    /srv/data\nbackup   2T     1.5T   /srv/backup\nscratch  500G   12G    /scratch\n' > "$LTD/vol.txt"
    printf '%s' '{"id":"msg_3","type":"message","role":"assistant","model":"claude-opus-5-5","stop_reason":"end_turn","usage":{"input_tokens":1,"output_tokens":1},"content":[{"type":"text","text":"{\"format\": 1, \"tool\": \"volumes\", \"detect\": \"^NAME\\\\s+SIZE\\\\s+USED\\\\s+MOUNT$\", \"skip\": [\"^Volumes on host \"], \"blocks\": [{\"name\": \"volumes\", \"kind\": \"table\", \"header\": \"^NAME\\\\s+SIZE\", \"line\": \"^(?P<name>\\\\S+)\\\\s+(?P<size>[\\\\d.]+[KMGT]?)\\\\s+(?P<used>[\\\\d.]+[KMGT]?)\\\\s+(?P<mount>/\\\\S*)$\"}]}"}]}' > "$LTD/reply.json"
    rm -f "$LTD/port" "$LTD/log"
    python3 "$HERE/fake_anthropic.py" "$LTD/port" "$LTD/log" "$LTD/reply.json" & LT_PID=$!
    for _ in $(seq 1 50); do [[ -s "$LTD/port" ]] && break; sleep 0.1; done
    LT_URL="http://127.0.0.1:$(cat "$LTD/port")"
    lt_out="$(PROVOST_WORKSPACE="$LTWS" PROVOST_LLM_BASE_URL="$LT_URL" PROVOST_LLM_API_KEY=k-test \
        "$PROVOST" --sync --llm --name volumes "$LTD/vol.txt" 2>&1)"
    kill "$LT_PID" 2>/dev/null || true; wait "$LT_PID" 2>/dev/null || true
    check "a generic parse the gate passed is offered to Claude first" "1" "$(wc -l < "$LTD/log" | tr -d ' ')"
    check "the template Claude wrote wins over the heuristic" "was passed over (the engine read it as aligned-columns, coverage 100%): a template Claude wrote for this tool fits; read by a new template Claude wrote (llm-templates/volumes.json)" "$lt_out"
    check "the template's rows are filed" "backup	2T	1.5T	/srv/backup" "$(cat "$LTWS/datasets/volumes.tsv")"
    check "meta records the template over the heuristic" "llm_template	filed by a new template Claude wrote (llm-templates/volumes.json)" "$(cat "$LTWS/captures/c0006/meta.tsv")"
    # the next capture of the tool: the stored template, offline, no API
    lt_out="$(PROVOST_WORKSPACE="$LTWS" PROVOST_LLM_BASE_URL="http://127.0.0.1:9" PROVOST_LLM_API_KEY=k-test \
        "$PROVOST" --sync --llm --name volumes "$LTD/vol.txt" 2>&1)"
    check "a stored template beats the heuristic offline" "read by template volumes.json" "$lt_out"
    # REPAIR: a later capture shows a kind of line the stored template has not
    # met (a swap volume). With a key, the template, the capture it was
    # written from and this one go to Claude once; the extension is kept only
    # if it still reads the earlier capture, and replaces the store's copy.
    printf 'Volumes on host beta\nNAME     SIZE   USED   MOUNT\ndata     200G   80G    /srv/data\nswap     8G     -      [SWAP]\nlogs     50G    5G     /var/log\n' > "$LTD/vol2.txt"
    check "a new kind of line is a miss" "1 unread line(s) of a kind it has not met" "$(python3 "$HERE/../extract/llm/template.py" misses "$LTWS/llm-templates/volumes.json" "$LTD/vol2.txt")"
    sed 's/alpha/gamma-7/' "$LTD/vol.txt" > "$LTD/vol1b.txt"
    check "another host in the banner is not" "[]" "[$(python3 "$HERE/../extract/llm/template.py" misses "$LTWS/llm-templates/volumes.json" "$LTD/vol1b.txt")]"
    printf '%s' '{"id":"msg_5","type":"message","role":"assistant","model":"claude-opus-5-5","stop_reason":"end_turn","usage":{"input_tokens":1,"output_tokens":1},"content":[{"type":"text","text":"{\"format\": 1, \"tool\": \"volumes\", \"detect\": \"^NAME\\\\s+SIZE\\\\s+USED\\\\s+MOUNT$\", \"skip\": [\"^Volumes on host \"], \"blocks\": [{\"name\": \"volumes\", \"kind\": \"table\", \"header\": \"^NAME\\\\s+SIZE\", \"line\": \"^(?P<name>\\\\S+)\\\\s+(?P<size>[\\\\d.]+[KMGT]?)\\\\s+(?P<used>[\\\\d.]+[KMGT]?|-)\\\\s+(?P<mount>/\\\\S*|\\\\[SWAP\\\\])$\"}]}"}]}' > "$LTD/reply.json"
    rm -f "$LTD/port" "$LTD/log"
    python3 "$HERE/fake_anthropic.py" "$LTD/port" "$LTD/log" "$LTD/reply.json" & LT_PID=$!
    for _ in $(seq 1 50); do [[ -s "$LTD/port" ]] && break; sleep 0.1; done
    LT_URL="http://127.0.0.1:$(cat "$LTD/port")"
    lt_out="$(PROVOST_WORKSPACE="$LTWS" PROVOST_LLM_BASE_URL="$LT_URL" PROVOST_LLM_API_KEY=k-test \
        "$PROVOST" --sync --llm --name volumes "$LTD/vol2.txt" 2>&1)"
    kill "$LT_PID" 2>/dev/null || true; wait "$LT_PID" 2>/dev/null || true
    check "a stored template that meets a new kind of line is extended" "read by template volumes.json, which Claude extended for 1 unread line(s) of a kind it has not met (llm-templates/volumes.json)" "$lt_out"
    check "the extension reads the new line" "swap	8G	-	[SWAP]" "$(cat "$LTWS/datasets/volumes.tsv")"
    check "the repair was one API call" "1" "$(wc -l < "$LTD/log" | tr -d ' ')"
    check "the request carries the capture the template was written from" "Earlier capture 1" "$(cat "$LTD/log")"
    check "the extended template keeps both captures" "2" "$(python3 -c 'import json, sys; print(len(json.load(open(sys.argv[1]))["examples"]))' "$LTWS/llm-templates/volumes.json")"
    lt_out="$(PROVOST_WORKSPACE="$LTWS" PROVOST_LLM_BASE_URL="http://127.0.0.1:9" PROVOST_LLM_API_KEY=k-test \
        "$PROVOST" --sync --llm --name volumes "$LTD/vol2.txt" 2>&1)"
    check "the next capture like it is read offline" "read by template volumes.json." "$lt_out"
    # an extension that no longer reads an earlier capture is refused (after
    # one more try), and the stored template is used as it was
    printf 'NAME     SIZE   USED   MOUNT\n' > "$LTD/vol3.txt"
    for i in 1 2 3 4 5 6 7 8 9 10; do printf 'd%s       %sG    1G     /srv/d%s\n' "$i" "$i" "$i" >> "$LTD/vol3.txt"; done
    printf 'tmp      1G     0      tmpfs (noexec)\n' >> "$LTD/vol3.txt"
    printf '%s' '{"id":"msg_6","type":"message","role":"assistant","model":"claude-opus-5-5","stop_reason":"end_turn","usage":{"input_tokens":1,"output_tokens":1},"content":[{"type":"text","text":"{\"format\": 1, \"tool\": \"volumes\", \"detect\": \"^NAME\\\\s+SIZE\", \"skip\": [\"^Volumes on host \"], \"blocks\": [{\"name\": \"volumes\", \"kind\": \"table\", \"header\": \"^NAME\\\\s+SIZE\", \"line\": \"^(?P<name>\\\\S+)\\\\s+(?P<size>\\\\S+)\\\\s+(?P<used>\\\\S+)\\\\s+(?P<mount>/\\\\S*|tmpfs.*)$\"}]}"}]}' > "$LTD/reply.json"
    rm -f "$LTD/port" "$LTD/log"
    python3 "$HERE/fake_anthropic.py" "$LTD/port" "$LTD/log" "$LTD/reply.json" & LT_PID=$!
    for _ in $(seq 1 50); do [[ -s "$LTD/port" ]] && break; sleep 0.1; done
    LT_URL="http://127.0.0.1:$(cat "$LTD/port")"
    lt_out="$(PROVOST_WORKSPACE="$LTWS" PROVOST_LLM_BASE_URL="$LT_URL" PROVOST_LLM_API_KEY=k-test \
        "$PROVOST" --sync --llm --name volumes "$LTD/vol3.txt" 2>&1)"
    kill "$LT_PID" 2>/dev/null || true; wait "$LT_PID" 2>/dev/null || true
    check "a refused extension had one more try" "2" "$(wc -l < "$LTD/log" | tr -d ' ')"
    check "the stored template is used as it was" "read by template volumes.json (Claude could not extend it for 1 unread line(s) of a kind it has not met" "$lt_out"
    check "and says why" "on earlier capture 2 it no longer reads 1 line(s) the template read" "$lt_out"
    check "the store keeps the template it had" "2" "$(python3 -c 'import json, sys; print(len(json.load(open(sys.argv[1]))["examples"]))' "$LTWS/llm-templates/volumes.json")"
    # a reply that leaves the template as it was (the new line is a note,
    # not data) is recorded as such, and the capture is remembered
    { printf 'NAME     SIZE   USED   MOUNT\n'; for i in 1 2 3 4 5 6 7 8 9 10; do printf 'd%s       %sG    1G     /srv/d%s\n' "$i" "$i" "$i"; done; printf '(snapshot taken at 12:00)\n'; } > "$LTD/vol4.txt"
    python3 -c 'import json, sys; t = json.load(open(sys.argv[1])); t.pop("examples"); print(json.dumps({"id": "msg_7", "type": "message", "role": "assistant", "model": "claude-opus-5-5", "stop_reason": "end_turn", "usage": {"input_tokens": 1, "output_tokens": 1}, "content": [{"type": "text", "text": json.dumps(t)}]}))' "$LTWS/llm-templates/volumes.json" > "$LTD/reply.json"
    rm -f "$LTD/port" "$LTD/log"
    python3 "$HERE/fake_anthropic.py" "$LTD/port" "$LTD/log" "$LTD/reply.json" & LT_PID=$!
    for _ in $(seq 1 50); do [[ -s "$LTD/port" ]] && break; sleep 0.1; done
    LT_URL="http://127.0.0.1:$(cat "$LTD/port")"
    lt_out="$(PROVOST_WORKSPACE="$LTWS" PROVOST_LLM_BASE_URL="$LT_URL" PROVOST_LLM_API_KEY=k-test \
        "$PROVOST" --sync --llm --name volumes "$LTD/vol4.txt" 2>&1)"
    kill "$LT_PID" 2>/dev/null || true; wait "$LT_PID" 2>/dev/null || true
    check "an unchanged reply is said to be one" "read by template volumes.json, which Claude checked for 1 unread line(s) of a kind it has not met and left as it was" "$lt_out"
    check "and the capture is remembered" "3" "$(python3 -c 'import json, sys; print(len(json.load(open(sys.argv[1]))["examples"]))' "$LTWS/llm-templates/volumes.json")"
    check "so it is not sent again" "[]" "[$(python3 "$HERE/../extract/llm/template.py" misses "$LTWS/llm-templates/volumes.json" "$LTD/vol4.txt")]"
    # without --llm the heuristic is filed as before
    lt_out="$(PROVOST_WORKSPACE="$LTWS" "$PROVOST" --sync --name volumes "$LTD/vol.txt" 2>&1)"
    check "without --llm the heuristic is filed" "strategy aligned-columns" "$lt_out"
    # with no key and no template (a fresh store), a generic parse the gate
    # passed is filed as it was, quietly; meta.tsv records why
    lt_out="$(PROVOST_WORKSPACE="$LTD/.fresh" "$PROVOST" --sync --llm --name other-vols "$LTD/vol.txt" 2>&1)"
    check "no key: the passed heuristic is filed as it was" "strategy aligned-columns" "$lt_out"
    check_not "no key: no LLM note on a filed heuristic" "no LLM template helped" "$lt_out"
    check "meta says why no template was used" "llm_template	declined: no stored template fits; no API key" "$(cat "$LTD/.fresh/captures/c0001/meta.tsv")"
    # NOTES: a template that sets prose aside as decoration may now beat a
    # CATCH-ALL parse (text-lines keeps every line): the lines it skips that
    # carry words are filed in NAME.notes, so none is lost
    printf 'The quick brown fox jumps over the lazy dog near the river bank.\nEvery morning the ferry leaves the harbour at six and returns at noon.\nNobody counted the gulls, though the keeper swore there were hundreds.\nRain came late in the season and the orchard did poorly that year.\nThe mill wheel still turns when the sluice is open, which is rarely.\nVisitors are asked to keep to the path and to close the gate.\nSummary of moorings:\nNAME     LENGTH\nkestrel  12m\nosprey   9m\n' > "$LTD/prose.txt"
    printf '%s' '{"id":"msg_4","type":"message","role":"assistant","model":"claude-opus-5-5","stop_reason":"end_turn","usage":{"input_tokens":1,"output_tokens":1},"content":[{"type":"text","text":"{\"format\": 1, \"tool\": \"moorings\", \"detect\": \"^NAME\\\\s+LENGTH$\", \"skip\": [\"^[A-Z].*[.:]$\"], \"blocks\": [{\"name\": \"moorings\", \"kind\": \"table\", \"header\": \"^NAME\\\\s+LENGTH$\", \"line\": \"^(?P<name>[a-z]+)\\\\s+(?P<length>\\\\d+m)$\"}]}"}]}' > "$LTD/reply.json"
    rm -f "$LTD/port"
    python3 "$HERE/fake_anthropic.py" "$LTD/port" "$LTD/log" "$LTD/reply.json" & LT_PID=$!
    for _ in $(seq 1 50); do [[ -s "$LTD/port" ]] && break; sleep 0.1; done
    LT_URL="http://127.0.0.1:$(cat "$LTD/port")"
    lt_out="$(PROVOST_WORKSPACE="$LTD/.fresh" PROVOST_LLM_BASE_URL="$LT_URL" PROVOST_LLM_API_KEY=k-test \
        "$PROVOST" --sync --llm --name moorings "$LTD/prose.txt" 2>&1)"
    check "a template that sets prose aside beats text-lines" "moorings  #" "$lt_out"
    check "the prose is filed beside its table" "moorings.notes" "$lt_out"
    check "each note keeps its line, why it was set aside and its text" "1	skipped	The quick brown fox jumps over the lazy dog near the river bank." "$(cat "$LTD/.fresh/datasets/moorings.notes.tsv")"
    check "the template is kept" "moorings.json" "$(ls "$LTD/.fresh/llm-templates" 2>/dev/null)"
    # but a template that cannot READ most of what it does not call
    # decoration still loses to text-lines (its unread lines are notes too,
    # yet a parser for 3 lines of 10 is not a parser for the tool)
    printf '%s' '{"id":"msg_4b","type":"message","role":"assistant","model":"claude-opus-5-5","stop_reason":"end_turn","usage":{"input_tokens":1,"output_tokens":1},"content":[{"type":"text","text":"{\"format\": 1, \"tool\": \"moorings\", \"detect\": \"^NAME\\\\s+LENGTH$\", \"blocks\": [{\"name\": \"moorings\", \"kind\": \"table\", \"header\": \"^NAME\\\\s+LENGTH$\", \"line\": \"^(?P<name>[a-z]+)\\\\s+(?P<length>\\\\d+m)$\"}]}"}]}' > "$LTD/reply.json"
    lt_out="$(PROVOST_WORKSPACE="$LTD/.fresh2" PROVOST_LLM_BASE_URL="$LT_URL" PROVOST_LLM_API_KEY=k-test \
        "$PROVOST" --sync --llm --name moorings "$LTD/prose.txt" 2>&1)"
    kill "$LT_PID" 2>/dev/null || true; wait "$LT_PID" 2>/dev/null || true
    check "a template that reads too little does not replace text-lines" "strategy text-lines" "$lt_out"
    check "meta says how much it read" "Claude's template does not fit this capture (it covers 30% of the lines)" "$(cat "$LTD/.fresh2/captures/c0001/meta.tsv")"
    check_not "such a template is not kept" "moorings" "$(ls "$LTD/.fresh2/llm-templates" 2>/dev/null)"
    # FORMAT 2: a template that is a small Python parser, for records that
    # span lines (ip-addr.json ships with provost), run in the sandbox
    lt_out="$(PROVOST_WORKSPACE="$LTWS" "$PROVOST" --sync --llm "$HERE/../extract/samples/llm-template/nested.txt" 2>&1)"
    check "a shipped parser template reads multi-line records" "read by template ip-addr.json" "$lt_out"
    check "the parser's blocks are the capture's datasets" "ip-addr.addresses" "$lt_out"
    check "a record is built from several lines" "enp3s0	inet	10.20.30.7/24	global	85211sec	85211sec	10.20.30.255	dynamic,noprefixroute" "$(cat "$LTWS/datasets/ip-addr.addresses.tsv")"
    check "a parser that reaches outside the box is refused" "imports os" "$(printf '{"format": 2, "tool": "x", "detect": "^a", "parser": "import os\\ndef parse(l): return []"}' > "$LTD/bad.json"; python3 "$HERE/../extract/llm/template.py" apply "$LTD/bad.json" "$LTD/vol.txt" 2>&1)"
fi

# The engine's legacy .provostrc layer is OFF under provost (PROVOST_NO_RC=1): a
# .provostrc in the CWD cannot reconfigure a capture. A probe strategy records
# what the engine process saw.
PROBE_DIR="$(mktemp -d)/probe"; mkdir -p "$PROBE_DIR"
cat > "$PROBE_DIR/probe.sh" <<'EOS'
#!/bin/bash
## Name: probe
## Description: smoke-test probe — records the engine's environment
## Version: 1.0
## Priority: 10
strategy_detect () {
    printf '%s|%s\n' "${PROVOST_NO_RC:-unset}" "${SMOKE_RC_PROBE:-unset}" > "$SMOKE_PROBE_OUT"
    _STRATEGY_CONFIDENCE=0; return 1
}
strategy_extract () { :; }
EOS
RCDIR="$(mktemp -d)"; printf 'SMOKE_RC_PROBE=leaked\n' > "$RCDIR/.provostrc"
export SMOKE_PROBE_OUT="$RCDIR/probe.out"
( cd "$RCDIR" && printf 'a=1, b=2\n' | "$PROVOST" --plugin-dir "$PROBE_DIR" >/dev/null 2>&1 ) || true
check "engines run with PROVOST_NO_RC=1 (.provostrc not loaded)" "1|unset" "$(cat "$SMOKE_PROBE_OUT" 2>&1)"
check "the .provostrc loader honours PROVOST_NO_RC=1" "unset" \
    "$(cd "$RCDIR" && PROVOST_NO_RC=1 bash -c 'source "$1"; provost_rc_load; echo "${SMOKE_RC_PROBE:-unset}"' _ "$HERE/../lib/provost_rc.sh" 2>&1)"
unset SMOKE_PROBE_OUT

# A leading '#%' prologue is capture context, not data: peeled before
# detection (generic parsers stay uncorrupted), stored as context.txt, and
# 'provost source' still shows the input verbatim.
pro_out="$(printf '#%% source: deframe\n#%% frame: 7\n              total        used        free      shared  buff/cache   available\nMem:           15943        2456        9876         123        3610       13234\nSwap:           2047           0        2047\n' | "$PROVOST" 2>&1)"
check "'#%' prologue does not corrupt detection (body still 'free')" "dataset 'free'" "$pro_out"
procap="$(ls "$WS/captures" | sort | tail -1)"
check "prologue stored with the capture as context.txt" "#% frame: 7" "$(cat "$WS/captures/$procap/context.txt" 2>&1)"
check "capture meta records the context" "context" "$(cat "$WS/captures/$procap/meta.tsv")"
prorow="$(sed -n 's/.*rows #\([0-9]*\)\..*/\1/p' <<< "$pro_out")"; prorow="${prorow%%$'\n'*}"
check "source of a prologue capture is verbatim (header included)" "#% source: deframe" "$("$PROVOST" source "$prorow" 2>&1)"

# '#%' after the first data line is data, not context — nothing is peeled.
printf 'alias ll='\''ls -alF'\''\n#%% not-a-prologue\n' | "$PROVOST" >/dev/null 2>&1 || true
midcap="$(ls "$WS/captures" | sort | tail -1)"
check "mid-file '#%' is data — no context recorded" "0" "$(ls "$WS/captures/$midcap/context.txt" 2>/dev/null | grep -c . || true)"

# --multi: one input that holds several datasets (a banner, a key/value block
# and a table) files each of them separately under ONE capture, instead of
# letting a single winner drop the rest.
MULTI_IN="$(mktemp)"
printf 'Linux 5.15.0-91-generic (host01) \t07/07/2026 \t_x86_64_\t(8 CPU)\n\navg-cpu:  %%user   %%nice %%system %%iowait  %%steal   %%idle\n           4.21    0.00    1.83    0.42    0.00   93.54\n\nDevice            r/s     w/s     rkB/s     wkB/s   rrqm/s   wrqm/s   %%rrqm   %%wrqm  r_await  w_await\nsda             12.34    8.91   1024.50    512.30     0.42     1.83    3.29   17.03     0.84     1.20\nsdb              3.21    2.10    256.40    128.20     0.10     0.45    3.02   17.65     0.62     0.95\n' > "$MULTI_IN"
multi_out="$("$PROVOST" --sync --multi "$MULTI_IN" 2>&1)"
check "--multi files several datasets from one input" "3 datasets" "$multi_out"
multicap="$(ls "$WS/captures" | sort | tail -1)"
multimeta="$(cat "$WS/captures/$multicap/meta.tsv")"
check "multi capture meta records the dataset count" "datasets	3" "$multimeta"
check "multi capture meta records each dataset's rows" "dataset_rows" "$multimeta"
check "multi datasets share one capture (one stored input)" "1" \
    "$(ls "$WS/captures/$multicap/output.txt" | grep -c .)"
# The two same-strategy tables differ in shape, so the store's variant rule
# keeps them apart rather than welding them together.
check "same-strategy datasets split into a variant" "aligned-columns.v2" "$multimeta"
multirow="$(sed -n 's/.*rows #\([0-9]*\)\..*/\1/p' <<< "$multi_out")"; multirow="${multirow%%$'\n'*}"
check "a multi-capture row still traces back to its input" "original source" \
    "$("$PROVOST" source "$multirow" 2>&1)"
# Without --multi the same input keeps the one-winner behaviour.
# (Its one-winner parse keeps a fraction of the report, so the quality gate
# would hold it back; turn the gate off to see the single-dataset filing.)
single_out="$("$PROVOST" --sync --min-coverage 0 --min-consistency 0 "$MULTI_IN" 2>&1)"
check "default capture is still single-dataset" "→ dataset" "$single_out"
# With the gate on, auto-multi tries the split and declines it (the avg-cpu
# block keeps half its own lines), so the capture is held with that reason.
held_out="$("$PROVOST" --sync "$MULTI_IN" 2>&1)"
check "a declined segmentation is held for triage" "queued in 'unsorted'" "$held_out"
check "the hold says why segmenting did not help" "segmenting it did not help: part" "$held_out"
check "meta records the declined segmentation" "auto_multi	declined: part" \
    "$(cat "$WS/captures/$(ls "$WS/captures" | sort | tail -1)/meta.tsv")"

# rm of ONE dataset of a --multi capture keeps the capture (it still feeds the
# others) and drops the name from its meta; removing the rest then purges it.
MRM="$(mktemp -d)/.multirm"
PROVOST_WORKSPACE="$MRM" "$PROVOST" --multi "$MULTI_IN" >/dev/null 2>&1
mrm_ds="$(awk -F'\t' '$1=="dataset"{print $2}' "$MRM/captures/c0001/meta.tsv")"
mrm_first="${mrm_ds%%,*}"
PROVOST_WORKSPACE="$MRM" "$PROVOST" rm -f "$mrm_first" >/dev/null 2>&1
check "rm of one --multi dataset keeps the shared capture" "true" "$([[ -d "$MRM/captures/c0001" ]] && echo true)"
check "the shared capture's meta records the removed dataset" "removed_datasets	$mrm_first" \
    "$(cat "$MRM/captures/c0001/meta.tsv" 2>&1)"
IFS=',' read -r -a mrm_rest <<< "${mrm_ds#*,}"
PROVOST_WORKSPACE="$MRM" "$PROVOST" rm -f "${mrm_rest[@]}" >/dev/null 2>&1
check "rm of the last datasets of a --multi capture purges it" "false" \
    "$([[ -d "$MRM/captures/c0001" ]] && echo true || echo false)"

# ============================================================================
# Hardening / regression checks
# ============================================================================

# Large captures: >~3000 rows used to die silently with exit 141 (SIGPIPE from
# `printf "$tsv" | head -1` under pipefail).
BIG="$(mktemp)"; awk 'BEGIN { print "id,name,value"; for (i = 1; i <= 3500; i++) printf "%d,n%d,%d\n", i, i, i * 7 }' > "$BIG"
BWS="$(mktemp -d)/.big"
big_rc=0; big_out="$(PROVOST_WORKSPACE="$BWS" "$PROVOST" --sync "$BIG" 2>&1)" || big_rc=$?
check "a 3500-row capture succeeds (no silent SIGPIPE exit)" "0" "$big_rc"
check "a 3500-row capture files every row" "#1..3500" "$big_out"
check "a 3500-row capture records provenance for every row" "3501" "$(wc -l < "$BWS/provenance.tsv" | tr -d ' ')"

# Monotonic capture ids survive an old store without the counter file: the id
# is seeded from the highest capture ever used (tags / history), not a count.
MIG="$(mktemp -d)/.mig"
for i in 1 2 3; do PROVOST_WORKSPACE="$MIG" "$PROVOST" run --name "m$i" printf "k$i=v, x=1\n" >/dev/null 2>&1; done
PROVOST_WORKSPACE="$MIG" "$PROVOST" rm -f m3 >/dev/null 2>&1           # purges c0003
# Make it look like a store from an older provost: no .gitignore, no counter,
# and a committed .lock (the old init committed its own lock).
rm -f "$MIG/.gitignore" "$MIG/.next_capture_id"
mkdir "$MIG/.lock"; dead_pid > "$MIG/.lock/pid"
tgit "$MIG" add -f -A >/dev/null 2>&1; tgit "$MIG" commit -q -m "simulate an old store" >/dev/null 2>&1
check "setup: the simulated old store tracks .lock" "1" "$(git -C "$MIG" ls-files | grep -c '^\.lock/' || true)"
mig_out="$(PROVOST_WORKSPACE="$MIG" "$PROVOST" run --name m4 printf 'k4=v, x=1\n' 2>&1)"
check "migrated store continues capture ids after the max ever used" "c0004:" "$mig_out"
check "migration untracks a committed .lock" "0" "$(git -C "$MIG" ls-files | grep -c '^\.lock' || true)"
check "migration adds the store .gitignore" "provost store .gitignore" "$(cat "$MIG/.gitignore" 2>&1)"

# Git failures are reported, never swallowed: no "ok" without a commit.
GWS="$(mktemp -d)/.gitfail"
printf 'a=1, b=2\n' | PROVOST_WORKSPACE="$GWS" "$PROVOST" >/dev/null 2>&1
: > "$GWS/.git/index.lock"                                  # git add will now fail
gf_rc=0; gf_out="$(printf 'c=3, d=4\n' | PROVOST_WORKSPACE="$GWS" "$PROVOST" 2>&1)" || gf_rc=$?
rm -f "$GWS/.git/index.lock"
check "a failed git commit exits non-zero" "1" "$gf_rc"
check "a failed git commit shows git's own error" "index.lock" "$gf_out"
check_not "a failed git commit does not report ok" " ok " "$gf_out"
# A shared store owned by another user works (git safe.directory); needs root
# to hand the store to another uid.
if [[ "$(id -u)" == 0 ]]; then
    chown -R 4242:4242 "$GWS"
    check "a store owned by another user still captures (safe.directory)" "dataset" \
        "$(printf 'e=5, f=6\n' | PROVOST_WORKSPACE="$GWS" "$PROVOST" 2>&1)"
else
    echo "  skip foreign-owned store check (needs root)"
fi

# Path traversal: dataset names and capture ids are validated.
TWS="$(mktemp -d)/deep/.trav"
printf 'a=1, b=2\n' | PROVOST_WORKSPACE="$TWS" "$PROVOST" >/dev/null 2>&1
VICTIM="$(dirname "$(dirname "$TWS")")/victim.tsv"; echo keep > "$VICTIM"
check "rm refuses a path-traversal dataset name (exit 2)" "2" "$(PROVOST_WORKSPACE="$TWS" rc_of "$PROVOST" rm -f ../../victim)"
check "the traversal target is untouched" "keep" "$(cat "$VICTIM" 2>&1)"
check "show refuses a path-traversal name" "invalid dataset name" "$(PROVOST_WORKSPACE="$TWS" "$PROVOST" show ../../victim 2>&1 || true)"
check "stats refuses a path-traversal name" "invalid dataset name" "$(PROVOST_WORKSPACE="$TWS" "$PROVOST" stats ../../victim 2>&1 || true)"
check "--name refuses a path-traversal name" "invalid dataset name" \
    "$(printf 'a=1\n' | PROVOST_WORKSPACE="$TWS" "$PROVOST" --name ../../victim 2>&1 || true)"
printf '99\tkv-pairs\t../../../etc\n' >> "$TWS/provenance.tsv"
check "source refuses a tampered capture id" "invalid capture id" "$(PROVOST_WORKSPACE="$TWS" "$PROVOST" source 99 2>&1 || true)"

# Code comes only from the install dir: engine/transform files planted in the
# data store (writable by a shared store's other members) are never run.
EH="$(mktemp -d)/evilhome"; mkdir -p "$EH/transform" "$EH/extract" "$EH/analyze"
MARK="$(mktemp -d)/pwned"
printf 'touch %q\n' "$MARK.transform" > "$EH/transform/melt.sh"
printf 'touch %q\n' "$MARK.extract" > "$EH/extract/provost-extract"
printf 'touch %q\n' "$MARK.analyze" > "$EH/analyze/provost-analyze"
ev_out="$(printf 'a=1, b=2\n' | env -u PROVOST_WORKSPACE PROVOST_HOME="$EH" "$PROVOST" 2>&1)"
env -u PROVOST_WORKSPACE PROVOST_HOME="$EH" "$PROVOST" stats kv-pairs >/dev/null 2>&1 || true
check "a store-planted engine/transform is never executed" "none" \
    "$(ls "$MARK".* 2>/dev/null || echo none)"
check "capture still works with the bundled engine" "dataset 'kv-pairs'" "$ev_out"

# Numeric settings are validated before any arithmetic touches them.
NWS="$(mktemp -d)/.num"; PWN="$(mktemp -d)/pwned"
check "PROVOST_MIN_CONFIDENCE with code is refused (exit 2)" "2" \
    "$(PROVOST_WORKSPACE="$NWS" PROVOST_MIN_CONFIDENCE="HOME[\$(touch $PWN)]" rc_of "$PROVOST" ls)"
check "...and the embedded command never ran" "false" "$([[ -e "$PWN" ]] && echo true || echo false)"
for v in PROVOST_LOCK_TIMEOUT PROVOST_RECONCILE_OVERLAP PROVOST_MAX_INPUT PROVOST_LOCK_MAX_AGE PROVOST_QUIET; do
    check "$v must be numeric (exit 2)" "2" "$(rc_of env PROVOST_WORKSPACE="$NWS" "$v=x[\$(touch $PWN)]" "$PROVOST" ls)"
done
check "none of the invalid settings executed code" "false" "$([[ -e "$PWN" ]] && echo true || echo false)"
check "--min-confidence must be numeric (exit 2)" "2" "$(printf 'a=1\n' | PROVOST_WORKSPACE="$NWS" rc_of "$PROVOST" --min-confidence 'x[1]')"
check "PROVOST_RECONCILE_OVERLAP range is enforced" "at most" \
    "$(PROVOST_WORKSPACE="$NWS" PROVOST_RECONCILE_OVERLAP=500 "$PROVOST" ls 2>&1 || true)"

# Dataset naming: 'run' names after the command, looking through wrappers.
NMWS="$(mktemp -d)/.names"
nm_out="$(PROVOST_WORKSPACE="$NMWS" "$PROVOST" run timeout 5 env A=1 nice -n 1 printf 'a=1, b=2\n' 2>&1)"
check "run looks through timeout/env/nice to name the dataset" "dataset 'printf'" "$nm_out"
check "the strategy is still recorded in meta" "strategy	kv-pairs" "$(cat "$NMWS/captures/c0001/meta.tsv")"
nm_out="$(printf 'a=1, b=2\n' | PROVOST_WORKSPACE="$NMWS" "$PROVOST" run xargs echo 2>&1)"
check "xargs is not a wrapper" "dataset 'xargs'" "$nm_out"
nm_out="$(PROVOST_WORKSPACE="$NMWS" "$PROVOST" run --name mine printf 'a=1, b=2\n' 2>&1)"
check "run --name overrides the dataset name" "dataset 'mine'" "$nm_out"
nm_out="$(printf 'a=1, b=2\n' | PROVOST_WORKSPACE="$NMWS" "$PROVOST" --name injected 2>&1)"
check "inject --name overrides the dataset name" "dataset 'injected'" "$nm_out"
if command -v df >/dev/null 2>&1; then
    PROVOST_WORKSPACE="$NMWS" "$PROVOST" run df -P >/dev/null 2>&1 || true
    check "the documented 'provost run df ...; provost show df' works" "Filesystem" \
        "$(PROVOST_WORKSPACE="$NMWS" "$PROVOST" show df 2>&1)"
fi

# run honours PROVOST_MAX_INPUT like inject does.
MX="$(mktemp -d)/.max"
mx_out="$(PROVOST_WORKSPACE="$MX" PROVOST_MAX_INPUT=10 "$PROVOST" run printf 'a=0123456789abcdef\n' 2>&1 || true)"
check "run refuses output larger than PROVOST_MAX_INPUT" "too large" "$mx_out"
check "nothing is captured for oversized run output" "0" "$(find "$MX/captures" -mindepth 1 2>/dev/null | wc -l | tr -d ' ')"

# meta.tsv 'command' is shell-quoted and TSV-safe (tabs/newlines escaped).
QWS="$(mktemp -d)/.quote"
PROVOST_WORKSPACE="$QWS" "$PROVOST" run --name q printf 'k=%s, j=%s\n' 'two words' $'tab\there' >/dev/null 2>&1
qmeta="$QWS/captures/c0001/meta.tsv"
check "meta.tsv stays two columns per line with tabs in args" "0" "$(awk -F'\t' 'NF != 2' "$qmeta" | grep -c . || true)"
check "meta command keeps argument boundaries (quoted)" "'two words'" "$(cat "$qmeta")"
check "meta command escapes a tab" "\$'tab\\there'" "$(cat "$qmeta")"
check "log shows the quoted command" "'two words'" "$(PROVOST_WORKSPACE="$QWS" "$PROVOST" log 2>/dev/null)"

# Store paths with spaces and quotes.
SPH="$(mktemp -d)/my st'ore"
sp_out="$(env -u PROVOST_WORKSPACE PROVOST_HOME="$SPH" "$PROVOST" run --name sp printf 'a=1, b=2\n' 2>&1)"
check "a store path with a space and a quote captures" "dataset 'sp'" "$sp_out"
check "log works in a store path with a space and a quote" "printf" "$(env -u PROVOST_WORKSPACE PROVOST_HOME="$SPH" "$PROVOST" log 2>&1)"
check "source works in a store path with a space and a quote" "a=1, b=2" "$(env -u PROVOST_WORKSPACE PROVOST_HOME="$SPH" "$PROVOST" source 1 2>&1)"
SPB="$(mktemp -d)/b u'n.bundle"
env -u PROVOST_WORKSPACE PROVOST_HOME="$SPH" "$PROVOST" export "$SPB" >/dev/null 2>&1
SPD="$(mktemp -d)/im port'ed"
spi_out="$(env -u PROVOST_WORKSPACE "$PROVOST" import "$SPB" "$SPD" 2>&1)"
check "import hint shell-quotes the destination (printf %q)" "PROVOST_WORKSPACE=$(printf '%q' "$SPD")" "$spi_out"
check "rm works in a store path with a space and a quote" "deleted sp" "$(env -u PROVOST_WORKSPACE PROVOST_HOME="$SPH" "$PROVOST" rm -f sp 2>&1)"

# Help / CLI polish: help → stdout + exit 0; usage errors → stderr + exit 2.
short_help="$("$PROVOST" help 2>/dev/null)"
check "help prints to stdout" "CAPTURE" "$short_help"
check "help exits 0" "0" "$(rc_of "$PROVOST" help)"
check "--help prints to stdout" "CAPTURE" "$("$PROVOST" --help 2>/dev/null)"
check "-h prints to stdout" "CAPTURE" "$("$PROVOST" -h 2>/dev/null)"
check "the short help fits a screen (50 lines or fewer)" "yes" "$([[ $(wc -l <<< "$short_help") -le 50 ]] && echo yes || echo "no: $(wc -l <<< "$short_help") lines")"
check "the short help points at the advanced help" "provost help advanced" "$short_help"
help_out="$("$PROVOST" help advanced 2>/dev/null)"
check "help advanced prints the full reference" "SETTINGS (environment)" "$help_out"
check "help all is the same" "SETTINGS (environment)" "$("$PROVOST" help all 2>/dev/null)"
check "--help advanced too" "SETTINGS (environment)" "$("$PROVOST" --help advanced 2>/dev/null)"
check "help advanced exits 0" "0" "$(rc_of "$PROVOST" help advanced)"
# (the help prints the install directory; measure it as a short placeholder,
# so a checkout under a long path does not fail the check)
check "no help line is wider than 79 columns" "0" "$(printf '%s\n%s\n' "$short_help" "$help_out" \
    | sed "s|$(cd "$HERE/.." && pwd)|/opt/provost|g" | awk 'length($0) > 79' | wc -l | tr -d ' ')"
for v in run batch listen search source diff files prev next restore control export rm doctor; do
    check "help advanced lists '$v'" "provost $v" "$help_out"
done
check_not "help no longer claims reconciliation is missing" "Not yet" "$help_out"
check "help cites the real design doc" "docs/0001-rename-and-simplification.md" "$help_out"
check "unknown command suggests the right one" "unknown command 'stat' (did you mean 'stats'?)" "$("$PROVOST" stat 2>&1 || true)"
check "unknown command exits 2" "2" "$(rc_of "$PROVOST" stat)"
check "'show' with no name is a clean usage error" "usage: provost show" "$("$PROVOST" show 2>&1 || true)"
check "'show' with no name exits 2" "2" "$(rc_of "$PROVOST" show)"
check "unknown option exits 2" "2" "$(rc_of "$PROVOST" rm --bogus x)"
for sub in run batch rm show stats log restore source next prev files diff search listen unlisten; do
    check "'$sub --help' prints its own usage to stdout" "usage: provost $sub" "$("$PROVOST" "$sub" --help 2>/dev/null)"
done
check "inject --help prints the inject usage" "cmd | provost" "$("$PROVOST" --sync --help 2>/dev/null)"
# every user-facing PROVOST_* setting is documented in help and the man page
MAN="$HERE/../man/provost.1"
while IFS= read -r v; do
    case "$v" in PROVOST_VERSION|PROVOST_ROOT|PROVOST_WORKSPACE_EXPLICIT|PROVOST_STORE_KIND|PROVOST_TEMP_DIR \
        |PROVOST_NO_RC|PROVOST_ANALYZE_SUPPRESS_AWK_WARNING|PROVOST_MULTI_TEXT_DIR \
        |PROVOST_LM_ENGINE_WIDE|PROVOST_LM_ENGINE_META|PROVOST_LM_RECORDS|PROVOST_LLM_RECORDS) continue ;; esac  # set for the engines, not by users
    check "help documents $v" "$v" "$help_out"
    check "man page documents $v" "$v" "$(cat "$MAN")"
done < <(grep -o 'PROVOST_[A-Z_]*' "$PROVOST" | sort -u)

# A store whose .git/config others can write must not smuggle in settings that
# make git run programs (filters, pagers, includes…): safe.directory is lifted.
T="$(mktemp -d)"
VWS="$T/vetstore"
printf 'Filesystem Size Used\n/dev/sda1 50G 20G\n' | PROVOST_WORKSPACE="$VWS" "$PROVOST" --sync >/dev/null 2>&1
check "own, private store config is trusted" "0" "$(PROVOST_WORKSPACE="$VWS" rc_of "$PROVOST" ls)"
chmod g+w "$VWS/.git/config"
check "group-writable config with only git's own keys is still trusted" "0" "$(PROVOST_WORKSPACE="$VWS" rc_of "$PROVOST" ls)"
git config --file "$VWS/.git/config" filter.evil.clean "touch $T/pwned-filter"
vet_out="$(PROVOST_WORKSPACE="$VWS" "$PROVOST" ls 2>&1 || true)"
check "group-writable config with a filter driver is refused" "refusing to use the store" "$vet_out"
check "refusal names the offending key" "filter.evil.clean" "$vet_out"
printf 'a,b\n1,2\n' | PROVOST_WORKSPACE="$VWS" "$PROVOST" --sync >/dev/null 2>&1 || true
check "no capture runs git in a refused store" "no" "$([[ -e "$T/pwned-filter" ]] && echo yes || echo no)"

# Store format 2: an old store's datasets lose the engine's `total_entries`
# record-count column on the next write (reads never rewrite the store); a non-integer column of that name is data
# and stays; new stores start at format 3.
MWS="$(mktemp -d)/.migrate"
printf 'Filesystem Size Used\n/dev/sda1 50G 20G\n/dev/sdb1 10G 1G\n' | PROVOST_WORKSPACE="$MWS" "$PROVOST" --sync >/dev/null 2>&1
check "new store records format 3" "3" "$(cat "$MWS/.store_format" 2>/dev/null)"
mds="$(ls "$MWS/datasets" | head -1)"
awk -F'\t' -v OFS='\t' 'NR==1{print $0, "total_entries"; next} {print $0, 2}' "$MWS/datasets/$mds" > "$MWS/x" && mv "$MWS/x" "$MWS/datasets/$mds"
printf 'a\ttotal_entries\nx\tnot-a-count\n' > "$MWS/datasets/keep.tsv"
rm -f "$MWS/.store_format"
tgit "$MWS" add -A >/dev/null 2>&1; tgit "$MWS" commit -qm "simulate an old store" >/dev/null 2>&1
printf 'k=v\nj=w\n' | PROVOST_WORKSPACE="$MWS" "$PROVOST" --sync >/dev/null 2>&1   # the next write migrates
check_not "migration drops the record-count column" "total_entries" "$(head -1 "$MWS/datasets/$mds")"
check "migration keeps the dataset's rows" "sdb1" "$(cat "$MWS/datasets/$mds")"
check "a non-count total_entries column is kept" "total_entries" "$(head -1 "$MWS/datasets/keep.tsv")"
check "migrated store records format 3" "3" "$(cat "$MWS/.store_format" 2>/dev/null)"
check "migration is committed" "store format 3" "$(tgit "$MWS" log --format=%s)"
check_not "a store that already has the capture column is not given it twice" "_capture" "$(head -1 "$MWS/datasets/$mds")"

# Store format 3: every dataset row carries the capture it came from, after
# '#'. An older store's datasets get the column on the next write, filled in
# from provenance.tsv; a data column already named `capture` is kept and the
# added one is `_capture`.
CWS="$(mktemp -d)/.capcol"
printf 'Filesystem Size Used\n/dev/sda1 50G 20G\n/dev/sdb1 10G 1G\n' | PROVOST_WORKSPACE="$CWS" "$PROVOST" --sync --name df >/dev/null 2>&1
printf 'Filesystem Size Used\n/dev/sda1 50G 21G\n' | PROVOST_WORKSPACE="$CWS" "$PROVOST" --sync --name df >/dev/null 2>&1
check "a dataset's second column is the capture" "#	capture	n	Filesystem" "$(head -1 "$CWS/datasets/df.tsv")"
check "each row names the capture it came from" "3	c0002	1	/dev/sda1" "$(cat "$CWS/datasets/df.tsv")"
check "show prints the capture column" "c0001" "$(PROVOST_WORKSPACE="$CWS" "$PROVOST" show df 2>&1)"
printf 'capture value\nx 1\n' | PROVOST_WORKSPACE="$CWS" "$PROVOST" --sync --name own >/dev/null 2>&1
check "a data column named capture keeps its name beside _capture" "#	_capture	n	capture	value" "$(head -1 "$CWS/datasets/own.tsv")"
printf 'held\n' | PROVOST_WORKSPACE="$CWS" "$PROVOST" --sync --min-confidence 101 >/dev/null 2>&1
check "triage shows the capture of a held input" "c0004" "$(PROVOST_WORKSPACE="$CWS" "$PROVOST" triage 2>/dev/null)"
for f in "$CWS"/datasets/*.tsv; do cut -f1,3- "$f" > "$CWS/x" && mv "$CWS/x" "$f"; done   # back to format 2
echo 2 > "$CWS/.store_format"
tgit "$CWS" add -A >/dev/null 2>&1; tgit "$CWS" commit -qm "simulate a format-2 store" >/dev/null 2>&1
check "triage still decodes a format-2 bucket" "held" "$(PROVOST_WORKSPACE="$CWS" "$PROVOST" triage 2>/dev/null)"
printf 'Filesystem Size Used\n/dev/sdc1 5G 2G\n' | PROVOST_WORKSPACE="$CWS" "$PROVOST" --sync --name df >/dev/null 2>&1
check "migration fills each old row's capture from provenance" "$(printf '1\tc0001\t1\t/dev/sda1\n2\tc0001\t2\t/dev/sdb1\n3\tc0002\t1\t/dev/sda1')" "$(cat "$CWS/datasets/df.tsv")"
check "and the new rows carry theirs" "6	c0005	1	/dev/sdc1" "$(cat "$CWS/datasets/df.tsv")"
check "migration names a clashing column _capture" "#	_capture	n	capture	value" "$(head -1 "$CWS/datasets/own.tsv")"
check "migration covers the triage bucket" "5	c0004	" "$(cat "$CWS/datasets/unsorted.tsv")"
check "the format-3 store records it" "3" "$(cat "$CWS/.store_format")"

# Browsing runs: show --capture / --at, source by capture id, next / prev,
# and log while restored. All read from git; the store stays where it is
# except under next / prev / restore.
BWS="$(mktemp -d)/.browse"
for st in PASS FAIL PASS; do printf 'TEST STATUS\nt1 PASS\nt2 %s\n' "$st" | PROVOST_WORKSPACE="$BWS" "$PROVOST" --sync --name tests >/dev/null 2>&1; done
printf 'a=1\n' | PROVOST_WORKSPACE="$BWS" "$PROVOST" --sync --name other >/dev/null 2>&1
bs="$(PROVOST_WORKSPACE="$BWS" "$PROVOST" show tests --capture c2 2>&1 | sq)"
check "show --capture keeps that capture's rows" "4 c0002 2 t2 FAIL" "$bs"
check_not "and only those" "c0001" "$bs"
check "--capture takes a bare number too" "c0002" "$(PROVOST_WORKSPACE="$BWS" "$PROVOST" show tests --capture 2 2>&1)"
bs="$(PROVOST_WORKSPACE="$BWS" "$PROVOST" show tests --at c0002 2>&1 | sq)"
check "show --at reads the dataset as it stood after that capture" "4 c0002 2 t2 FAIL" "$bs"
check_not "and nothing filed after it" "c0003" "$bs"
check "show --at an unknown capture is refused" "no such capture: c0099" "$(PROVOST_WORKSPACE="$BWS" "$PROVOST" show tests --at 99 2>&1 || true)"
check "show --capture with no rows says so" "no rows in 'other' from capture c0001" "$(PROVOST_WORKSPACE="$BWS" "$PROVOST" show other --capture 1 2>&1)"
bs="$(PROVOST_WORKSPACE="$BWS" "$PROVOST" source c0002 2>&1)"
check "source ID shows that capture's output" "t2 FAIL" "$bs"
check "and its details" "row_ids: 3-4" "$bs"
check "source #N still means a row" "row #3" "$(PROVOST_WORKSPACE="$BWS" "$PROVOST" source 3 2>&1)"
PROVOST_WORKSPACE="$BWS" "$PROVOST" prev >/dev/null 2>&1
check "prev from the latest brings up the capture before it" "c0003" "$(tgit "$BWS" describe --tags --exact-match HEAD 2>&1)"
PROVOST_WORKSPACE="$BWS" "$PROVOST" prev >/dev/null 2>&1
check "prev again steps back one more" "c0002" "$(tgit "$BWS" describe --tags --exact-match HEAD 2>&1)"
check "while restored, show is the store as it was" "4 c0002" "$(PROVOST_WORKSPACE="$BWS" "$PROVOST" show tests 2>&1 | sq)"
bs="$(PROVOST_WORKSPACE="$BWS" "$PROVOST" log 2>&1)"
check "log still lists every capture while restored" "c0004" "$bs"
check "and says where the store is" "restored to c0002" "$bs"
check "source reaches a capture after the restored one" "a=1" "$(PROVOST_WORKSPACE="$BWS" "$PROVOST" source c0004 2>&1)"
PROVOST_WORKSPACE="$BWS" "$PROVOST" prev >/dev/null 2>&1
check "prev at the first capture stays there" "already at the first capture" "$(PROVOST_WORKSPACE="$BWS" "$PROVOST" prev 2>&1)"
for _ in 1 2 3; do PROVOST_WORKSPACE="$BWS" "$PROVOST" next >/dev/null 2>&1; done
check "next steps forward to the last capture" "c0004" "$(tgit "$BWS" describe --tags --exact-match HEAD 2>&1)"
PROVOST_WORKSPACE="$BWS" "$PROVOST" next >/dev/null 2>&1
check "next past the last returns to the latest" "main" "$(tgit "$BWS" symbolic-ref --short HEAD 2>&1)"
check "next at the latest says so" "already at the latest" "$(PROVOST_WORKSPACE="$BWS" "$PROVOST" next 2>&1)"

# diff: the rows two captures filed, compared without provost's own columns.
bs="$(PROVOST_WORKSPACE="$BWS" "$PROVOST" diff tests 2>&1)"
check "diff NAME compares that dataset's last two captures" "c0002 → c0003" "$bs"
check "a row only the earlier capture has is -" "  - t2	FAIL" "$bs"
check "a row only the later one has is +" "  + t2	PASS" "$bs"
check "rows both have are counted" "(1 row the same)" "$bs"
check "diff A alone compares it with the capture before it" "c0001 → c0002" "$(PROVOST_WORKSPACE="$BWS" "$PROVOST" diff c2 2>&1)"
check "a dataset only one capture filed is named" "other: only in c0004 (1 row)" "$(PROVOST_WORKSPACE="$BWS" "$PROVOST" diff 2>&1)"
check "the same rows read as no change" "tests: no change (2 rows)" "$(PROVOST_WORKSPACE="$BWS" "$PROVOST" diff 1 3 2>&1)"

# files + diff in a controlled directory: each run's files, and what changed.
FH="$(mktemp -d)/home"; FP="$(mktemp -d)/proj"; mkdir -p "$FP"
( cd "$FP" && PROVOST_HOME="$FH" PROVOST_WORKSPACE="" "$PROVOST" control >/dev/null 2>&1
  echo 'v = 1' > m.py; printf 'TEST STATUS\nt1 PASS\n' > r.txt
  PROVOST_HOME="$FH" PROVOST_WORKSPACE="" "$PROVOST" run cat r.txt >/dev/null 2>&1
  echo 'v = 2' > m.py; printf 'TEST STATUS\nt1 FAIL\n' > r.txt; echo x > new.txt
  PROVOST_HOME="$FH" PROVOST_WORKSPACE="" "$PROVOST" run cat r.txt >/dev/null 2>&1 )
fr () { ( cd "$FP" && PROVOST_HOME="$FH" PROVOST_WORKSPACE="" "$PROVOST" "$@" 2>&1 ); }
check "files lists the latest run's files" "new.txt" "$(fr files)"
check_not "files ID lists that run's" "new.txt" "$(fr files c1)"
check "files ID PATH prints the file as it was" "v = 1" "$(fr files c1 m.py)"
fr files c1 --to "$FP/../out1" >/dev/null
check "files ID --to writes the run's files out" "v = 1" "$(cat "$FP/../out1/m.py" 2>&1)"
check "--to refuses a directory that is not empty" "is not an empty directory" "$(fr files c1 --to "$FP" || true)"
check "files of an unknown capture is refused" "no such capture: c0009" "$(fr files c9 || true)"
check "files of a capture that kept none says why" "capture c0001 kept no files" "$(PROVOST_WORKSPACE="$BWS" "$PROVOST" files c1 2>&1 || true)"
bs="$(fr diff)"
check "diff lists the files that changed" "new.txt" "$bs"
check "with the dataset rows" "  + t1	FAIL" "$bs"
check "diff -- PATH shows that file's changes" "+v = 2" "$(fr diff c1 c2 -- m.py)"

# search: git grep over the store's rows, outputs and run files.
bs="$(PROVOST_WORKSPACE="$BWS" "$PROVOST" search FAIL 2>&1 | sq)"
check "search finds the matching rows, named by dataset" "tests (1 row)" "$bs"
check "under the dataset's header" "# capture n TEST STATUS" "$bs"
check "with the row itself" "4 c0002 2 t2 FAIL" "$bs"
check "search -i ignores case" "tests (5 rows)" "$(PROVOST_WORKSPACE="$BWS" "$PROVOST" search -i pass 2>&1)"
check "search NAME limits it to that dataset" "no dataset rows match 'a'" "$(PROVOST_WORKSPACE="$BWS" "$PROVOST" search -w a tests 2>&1)"
check "a capture id finds that capture's rows" "other (1 row)" "$(PROVOST_WORKSPACE="$BWS" "$PROVOST" search c0004 2>&1)"
check "search --at reads the store as it stood then" "no dataset rows match 'FAIL' at c0001" "$(PROVOST_WORKSPACE="$BWS" "$PROVOST" search FAIL --at 1 2>&1)"
check "search --output finds a line of captured output" "c0004 1 a=1" "$(PROVOST_WORKSPACE="$BWS" "$PROVOST" search --output 'a=' 2>&1 | sq)"
check "-e takes a pattern that starts with a dash" "no dataset rows match '-x'" "$(PROVOST_WORKSPACE="$BWS" "$PROVOST" search -e -x 2>&1)"
check "search --files searches the latest run's files" "m.py:1:v = 2" "$(fr search --files 'v =')"
check "--files --at searches that run's" "m.py:1:v = 1" "$(fr search --files 'v =' --at 1)"

# --show and listen: the output is shown as always and filed too.
LWS2="$(mktemp -d)/.listen"; LCFG="$(mktemp -d)"; LBIN="$(mktemp -d)"
printf '#!/bin/sh\necho "TEST STATUS"; echo "t1 PASS"; echo "t2 $1"; exit 3\n' > "$LBIN/mytest"; chmod +x "$LBIN/mytest"
bs="$(PROVOST_WORKSPACE="$LWS2" "$PROVOST" run --show "$LBIN/mytest" FAIL 2>/dev/null; echo "rc=$?")"
check "run --show prints the command's output" "t2 FAIL" "$bs"
check "and keeps its exit status" "rc=3" "$bs"
check "and files it" "t2 FAIL" "$(PROVOST_WORKSPACE="$LWS2" "$PROVOST" show mytest 2>&1 | sq)"
check "inject --show passes the input through" "x y" "$(printf 'x y\n1 2\n' | PROVOST_WORKSPACE="$LWS2" "$PROVOST" --show --name teed 2>/dev/null)"
check "and files it" "teed" "$(PROVOST_WORKSPACE="$LWS2" "$PROVOST" ls 2>&1)"
lr () { env XDG_CONFIG_HOME="$LCFG" HOME="$LCFG" PATH="$LBIN:$PATH" PROVOST_WORKSPACE="$LWS2" "$PROVOST" "$@" 2>&1; }
check "listen says how to load it" "listen.sh" "$(lr listen mytest)"
check "listen with no CMD lists the commands" "mytest" "$(lr listen)"
check "listening twice is a no-op" "already listening on: mytest" "$(lr listen mytest)"
check "a shell builtin is refused" "is a shell builtin" "$(lr listen cd || true)"
check "provost itself is refused" "cannot listen on itself" "$(lr listen provost || true)"
bs="$(env XDG_CONFIG_HOME="$LCFG" PATH="$LBIN:$PATH" PROVOST_WORKSPACE="$LWS2" bash -c '. "$XDG_CONFIG_HOME/provost/listen.sh"; mytest PASS; echo "rc=$?"' 2>/dev/null)"
check "a listened command shows its output" "t2 PASS" "$bs"
check "keeps its exit status" "rc=3" "$bs"
check "and is filed each time it runs" "t2 PASS" "$(PROVOST_WORKSPACE="$LWS2" "$PROVOST" show mytest 2>&1 | sq)"
check "unlisten stops it" "stopped listening on: mytest" "$(lr unlisten mytest)"
check "and the list is empty" "listening on nothing" "$(lr listen)"

# batch: many inputs, one commit, a capture each; and '#%' context as columns.
BTWS="$(mktemp -d)/.batch"; BTD="$(mktemp -d)"
for h in web01 web02 db01; do printf '#%% host=%s rack=r1 note\nName,Load\n%s,0.5\n' "$h" "$h" > "$BTD/$h.txt"; done
: > "$BTD/empty.txt"
bt () { PROVOST_WORKSPACE="$BTWS" "$PROVOST" "$@" 2>&1; }
bout="$(bt batch --context-columns --name load "$BTD/web01.txt" "$BTD/empty.txt" "$BTD/web02.txt" "$BTD/db01.txt"; echo "rc=$?")"
check "batch files each input as a capture of its own" "captures c0001..c0003, one commit; 1 empty" "$bout"
check "an empty input is skipped, and said" "empty.txt: empty -- nothing captured." "$bout"
check "batch exits 0 when every input was captured" "rc=0" "$bout"
check "batch makes one commit for all of them" "2" "$(tgit "$BTWS" rev-list --count HEAD)"
check "the commit names the captures and the rows" "batch: 3 capture(s) c0001..c0003 (3 rows)" "$(tgit "$BTWS" log -1 --format=%s)"
check "each capture is tagged" "capture-c0001 capture-c0002 capture-c0003" "$(tgit "$BTWS" tag | sort | tr '\n' ' ')"
check "each is logged with source batch" "batch" "$(bt log | sq | awk '$1 == "c0002" { print $3 }')"
bshow="$(bt show load | sq)"
check "context columns come after # and capture" "# capture host rack n Name Load" "$bshow"
check "ids follow the order the inputs were named" "2 c0002 web02 r1 1 web02 0.5" "$bshow"
check "each row carries its own input's context" "3 c0003 db01 r1 1 db01 0.5" "$bshow"
check_not "a word that is not key=value is not a column" "note" "$bshow"
check "source still returns each input on its own" "db01,0.5" "$(bt source c0003)"
check_not "...and only that input" "web01" "$(bt source c0003)"
check "meta.tsv records the batch" "batch	c0001..c0003" "$(cat "$BTWS/captures/c0002/meta.tsv")"
check "...and each capture's input" "web02.txt" "$(cat "$BTWS/captures/c0002/meta.tsv")"
check "...and which columns came from its context" "context_columns	host=host,rack=rack" "$(cat "$BTWS/captures/c0002/meta.tsv")"
printf '#%% host=h1 Load=9\nhost,Load\nweb,0.5\n' > "$BTD/clash.txt"
bt batch -q --context-columns --name clash "$BTD/clash.txt" >/dev/null || true
check "a data column keeps its name; the context one takes a '_'" "# capture _host _Load n host Load" "$(bt show clash | sq)"
check "...and meta.tsv says which is which" "context_columns	host=_host,Load=_Load" "$(cat "$BTWS/captures/c0004/meta.tsv")"
printf '#%% capture=zz\nName,Load\nx,1\n' > "$BTD/capkey.txt"
bt batch -q --context-columns --name capkey "$BTD/capkey.txt" >/dev/null || true
check "a context key named capture never takes the capture column" "# capture _capture n Name Load" "$(bt show capkey | sq)"
printf '#%% host=plain\nName,Load\nx,1\n' > "$BTD/plain.txt"
bt batch -q --name plain "$BTD/plain.txt" >/dev/null || true
check_not "without --context-columns the context is no column" "plain" "$(bt show plain | sq)"
PROVOST_CONTEXT_COLUMNS=1 bt batch -q --name envcc "$BTD/plain.txt" >/dev/null || true
check "PROVOST_CONTEXT_COLUMNS=1 is the flag" "# capture host n Name Load" "$(bt show envcc | sq)"
printf '#%% host=piped\nName,Load\nx,1\n' | PROVOST_WORKSPACE="$BTWS" "$PROVOST" --context-columns --name pipedcc >/dev/null 2>&1 || true
check "--context-columns works on piped input too" "piped 1 x 1" "$(bt show pipedcc | sq)"
bt batch -q --context-columns --min-confidence 101 "$BTD/plain.txt" >/dev/null || true
check "a held capture stays one raw column" "# capture raw" "$(bt show unsorted | sq)"
check "PROVOST_CONTEXT_COLUMNS must be 0 or 1 (exit 2)" "2" "$(PROVOST_WORKSPACE="$BTWS" PROVOST_CONTEXT_COLUMNS=yes rc_of "$PROVOST" ls)"
nout="$(bt batch --name n1 "$BTD/web01.txt" --name n2 "$BTD/web02.txt")"
check "--name applies to the files after it" "dataset 'n1'" "$nout"
check "...until the next --name" "dataset 'n2'" "$nout"
printf 'fa\t%s\n# a comment\n\n%s\n' "$BTD/web01.txt" "$BTD/web02.txt" > "$BTD/list"
fout="$(bt batch --name fb --from "$BTD/list")"
check "--from reads NAME<TAB>PATH lines" "dataset 'fa'" "$fout"
check "...and PATH lines, under --name" "dataset 'fb'" "$fout"
check "--from - reads the list from stdin" "dataset 'fs'" "$(printf 'fs\t%s\n' "$BTD/db01.txt" | PROVOST_WORKSPACE="$BTWS" "$PROVOST" batch --from - 2>&1)"
before="$(tgit "$BTWS" rev-list --count HEAD)"
check "a missing input refuses the whole batch" "no such file" "$(bt batch "$BTD/web01.txt" "$BTD/nosuch.txt" || true)"
check "...and nothing is filed" "same" "$([[ "$(tgit "$BTWS" rev-list --count HEAD)" == "$before" ]] && echo same || echo changed)"
head -c 3000 /dev/zero | tr '\0' x > "$BTD/big.txt"
oout="$(PROVOST_MAX_INPUT=2000 bt batch --name ov "$BTD/web01.txt" "$BTD/big.txt"; echo "rc=$?")"
check "an oversized input is reported" "big.txt: too large" "$oout"
check "...the rest are filed" "dataset 'ov'" "$oout"
check "...and batch exits 1" "rc=1" "$oout"
J1="$(mktemp -d)/.j1"; J8="$(mktemp -d)/.j8"
PROVOST_WORKSPACE="$J1" "$PROVOST" batch -q -j 1 --context-columns --name load "$BTD/web01.txt" "$BTD/web02.txt" "$BTD/db01.txt" >/dev/null 2>&1 || true
PROVOST_WORKSPACE="$J8" "$PROVOST" batch -q -j 8 --context-columns --name load "$BTD/web01.txt" "$BTD/web02.txt" "$BTD/db01.txt" >/dev/null 2>&1 || true
check "-j 1 and -j 8 file the same rows" "same" "$(cmp -s "$J1/datasets/load.tsv" "$J8/datasets/load.tsv" && echo same || echo differ)"
# Detection reuse: the rest of a name's inputs are read the way its first
# was, when that gives the same table -- and the rows are the same as without
for h in r1 r2 r3 r4; do printf 'load1: 0.%s\nconns: 1%s\n' "${h#r}" "${h#r}" > "$BTD/$h.txt"; done
printf 'ssh: connect to host r5 port 22: Connection refused\n' > "$BTD/r5.txt"
RU0="$(mktemp -d)/.ru0"; RU1="$(mktemp -d)/.ru1"
PROVOST_BATCH_REUSE=0 PROVOST_WORKSPACE="$RU0" "$PROVOST" batch -q --name kv "$BTD"/r?.txt >/dev/null 2>&1 || true
PROVOST_WORKSPACE="$RU1" "$PROVOST" batch -q --name kv "$BTD"/r?.txt >/dev/null 2>&1 || true
check "detection reuse files the same rows as without it" "same" "$( (diff -r "$RU0/datasets" "$RU1/datasets" >/dev/null && echo same) || echo differ)"
check "the inputs after the first record the reused detection" "detection	reused (" "$(cat "$RU1/captures/c0003/meta.tsv")"
check_not "the first input of a name is detected itself" "detection	" "$(cat "$RU1/captures/c0001/meta.tsv")"
check_not "an input the hint does not fit is detected from scratch" "detection	" "$(cat "$RU1/captures/c0005/meta.tsv")"
check_not "PROVOST_BATCH_REUSE=0 detects every input" "detection	" "$(cat "$RU0"/captures/*/meta.tsv)"
# Several names in one batch (a fleet's answers to several commands): each
# name's first input is parsed side by side, and gives its own name's hint
for h in m1 m2 m3; do printf 'host,load\n%s,0.%s\n' "$h" "${h#m}" > "$BTD/$h.csv"; done
RM1="$(mktemp -d)/.rm1"; RMJ="$(mktemp -d)/.rmj"
for ws in "$RM1:1" "$RMJ:8"; do
    PROVOST_WORKSPACE="${ws%:*}" "$PROVOST" batch -q -j "${ws#*:}" --name kv "$BTD"/r[1-4].txt --name csv "$BTD"/m?.csv >/dev/null 2>&1 || true
done
check "several names: -j 1 and -j 8 file the same rows" "same" "$( (diff -r "$RM1/datasets" "$RMJ/datasets" >/dev/null && echo same) || echo differ)"
check "several names: each name's own hint is reused" "reused (" "$(cat "$RMJ/captures/c0006/meta.tsv")"
check "several names: ...and the first name's too" "reused (" "$(cat "$RMJ/captures/c0002/meta.tsv")"
check "--llm parses one input at a time" "parses one input at a time" "$(bt batch --llm -j 4 --name llmone "$BTD/web01.txt")"
check "batch with no files is a usage error (exit 2)" "2" "$(PROVOST_WORKSPACE="$BTWS" rc_of "$PROVOST" batch)"
check "batch refuses --async (exit 2)" "2" "$(PROVOST_WORKSPACE="$BTWS" rc_of "$PROVOST" batch --async "$BTD/web01.txt")"
check "--jobs must be a number (exit 2)" "2" "$(PROVOST_WORKSPACE="$BTWS" rc_of "$PROVOST" batch -j x "$BTD/web01.txt")"

echo "smoke: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
