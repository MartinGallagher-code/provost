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
      PROVOST_LLM PROVOST_LLM_MODEL PROVOST_LLM_API_KEY PROVOST_LLM_BASE_URL ANTHROPIC_API_KEY \
      PROVOST_LLM_API PROVOST_LLM_OFFLINE PROVOST_LLM_ALLOW_HOSTS \
      PROVOST_MANIFEST_PROFILE PROVOST_MANIFEST_STRICT PROVOST_REDACT PROVOST_ENV PROVOST_ENV_VARS \
      PROVOST_OVERSIZE PROVOST_ARTIFACT_DIR \
      PROVOST_SIGN PROVOST_SIGNING_KEY PROVOST_OPERATOR PROVOST_OBJECT_FORMAT PROVOST_ALLOWED_SIGNERS \
      LOADEDMODULES SLURM_JOB_ID SLURM_JOBID SLURM_JOB_NODELIST SLURM_NODELIST SLURM_CLUSTER_NAME SLURM_JOB_PARTITION
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
# own_pg CMD... -- run CMD as a job in a process group of its own, as a shell at a
# terminal would, so a signal to "its group" reaches it and not this suite
# The job starts with SIGINT at its default, as a job at a terminal does: a
# shell started with SIGINT ignored (as CI's runner has started this suite
# since 2026-11-09) passes the ignore on, and a signal ignored when bash starts
# cannot be trapped, so provost's own INT handling would go untested (PV-035).
# GNU env's --default-signal does it; elsewhere, python3; else as it comes.
if env --default-signal=INT true >/dev/null 2>&1; then
    SIGDFL=(env --default-signal=INT)
elif command -v python3 >/dev/null 2>&1; then
    SIGDFL=(python3 -c 'import os, signal, sys; signal.signal(signal.SIGINT, signal.SIG_DFL); os.execvp(sys.argv[1], sys.argv[1:])')
else
    SIGDFL=()
fi
own_pg () { ( set -m; ${SIGDFL[@]+"${SIGDFL[@]}"} "$@" 2>&3 & wait $! ) 3>&2 2>/dev/null; }
# git on a test store with a throwaway identity (the smoke's own git use).
tgit () { git -C "$1" -c user.name=smoke -c user.email=smoke@localhost -c commit.gpgsign=false "${@:2}"; }
# The lock owner "host" string provost writes for this machine.
LOCK_HOST="${HOSTNAME:-$(uname -n)}"
_ns="$(readlink /proc/self/ns/pid 2>/dev/null || true)"; LOCK_HOST="$LOCK_HOST${_ns:+/$_ns}"
# A pid that is certainly gone.
dead_pid () { sleep 0 & local p=$!; wait "$p" 2>/dev/null || true; echo "$p"; }

# --- parts: the checks run as independent groups, in parallel ---------------
# Every check below sits in a part (`if _part NAME; then ... fi`). A part keeps
# its own stores and reads nothing another part sets, except the default
# workspace $WS, so every block that uses $WS is in the one part ("core").
# With more than one job this script runs itself once per part
# (PROVOST_SMOKE_PART=NAME), each with a fresh $WS and PROVOST_HOME, holds
# each part's output, prints it whole in file order, and adds up the counts.
# PROVOST_TEST_JOBS=1 runs every part in this one process, top to bottom.
_part () { [[ -z "${PROVOST_SMOKE_PART:-}" || "$PROVOST_SMOKE_PART" == "$1" ]]; }
# git's version, as MAJOR*1000+MINOR (2.34 -> 2034), for checks that need a
# newer git than provost itself does (PV-027).
GITV="$(git --version 2>/dev/null | awk '{ split($3, v, "."); print v[1] * 1000 + v[2] }')"
# Variants (PV-027): the core part again, on a SHA-256 store (core@sha256)
# and with every commit and capture tag SSH-signed (core@signed). Each runs
# as a part of its own; a git too old for one says so and passes nothing.
SMOKE_VARIANTS=(core@sha256 core@signed)
case "${PROVOST_SMOKE_VARIANT:-}" in
    "") ;;
    sha256)
        if (( GITV < 2029 )); then
            echo "  skip core@sha256: git $(git --version | awk '{ print $3 }') cannot make a SHA-256 repository (2.29 or later can)"
            echo "smoke: 0 passed, 0 failed"; exit 0
        fi
        echo "  (core part, re-run on a SHA-256 store)"
        export PROVOST_OBJECT_FORMAT=sha256 ;;
    signed)
        if (( GITV < 2034 )) || ! command -v ssh-keygen >/dev/null 2>&1; then
            echo "  skip core@signed: SSH signing needs git 2.34 or later and ssh-keygen"
            echo "smoke: 0 passed, 0 failed"; exit 0
        fi
        echo "  (core part, re-run with every commit and capture tag SSH-signed)"
        _vk="$(mktemp -d)"; ssh-keygen -q -t ed25519 -N '' -C smoke -f "$_vk/key" </dev/null
        printf 'smoke@test %s\n' "$(cat "$_vk/key.pub")" > "$_vk/allowed"
        export PROVOST_SIGN=ssh PROVOST_SIGNING_KEY="$_vk/key" PROVOST_ALLOWED_SIGNERS="$_vk/allowed" ;;
    *) echo "smoke: unknown variant '$PROVOST_SMOKE_VARIANT'" >&2; exit 2 ;;
esac
export PROVOST_HOME="${WS%/.provost}/home"
JOBS="${PROVOST_TEST_JOBS:-$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}"
if ! [[ "$JOBS" =~ ^[1-9][0-9]*$ ]]; then
    echo "PROVOST_TEST_JOBS must be a positive integer (got '$JOBS')" >&2; exit 2
fi
if [[ -z "${PROVOST_SMOKE_PART:-}" && $JOBS -gt 1 ]]; then
    # A check outside every part would run once per part: refuse that.
    loose="$(awk '/^if _part /{d=1;next} d>0&&/^if /{d++} d>0&&/^fi$/{d--;next}
                  d==0&&/^[[:space:]]*check(_not)? "/{printf " %d", NR}' "${BASH_SOURCE[0]}")"
    if [[ -n "$loose" ]]; then
        echo "smoke: checks outside an 'if _part NAME; then ... fi' block (lines$loose)" >&2; exit 2
    fi
    PARTS=()
    while read -r p; do PARTS+=("$p"); done < <(sed -n 's/^if _part \([a-z0-9-]*\); then$/\1/p' "${BASH_SOURCE[0]}" | awk '!seen[$0]++')
    PARTS+=("${SMOKE_VARIANTS[@]}")
    PW="$(mktemp -d "${TMPDIR:-/tmp}/provost-smoke.XXXXXX")"
    trap 'rm -rf "$PW"' EXIT
    _has_wait_n=0
    (( BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 3) )) && _has_wait_n=1
    for i in "${!PARTS[@]}"; do
        _pv=""; [[ "${PARTS[$i]}" == *@* ]] && _pv="${PARTS[$i]#*@}"
        ( rc=0; t0=$SECONDS; PROVOST_SMOKE_PART="${PARTS[$i]%@*}" PROVOST_SMOKE_VARIANT="$_pv" bash "${BASH_SOURCE[0]}" > "$PW/$i.log" 2>&1 || rc=$?
          echo "$((SECONDS - t0))" > "$PW/$i.t"
          echo "$rc" > "$PW/$i.rc.tmp" && mv "$PW/$i.rc.tmp" "$PW/$i.rc" ) &
        while [[ "$(jobs -rp | wc -l)" -ge "$JOBS" ]]; do
            if [[ $_has_wait_n -eq 1 ]]; then wait -n 2>/dev/null || true; else sleep 0.1; fi
        done
    done
    wait
    slow=0
    for i in "${!PARTS[@]}"; do
        [[ "$(cat "$PW/$i.t")" -gt "$(cat "$PW/$slow.t")" ]] && slow=$i
        grep -v '^smoke: [0-9]* passed, [0-9]* failed$' "$PW/$i.log" || true
        line="$(grep '^smoke: [0-9]* passed, [0-9]* failed$' "$PW/$i.log" | tail -1 || true)"
        if [[ -z "$line" ]]; then
            # The part stopped before its summary (set -e, a crash): what it
            # did not run cannot be counted, so the run fails.
            echo "  FAIL part '${PARTS[$i]}' stopped early (exit $(cat "$PW/$i.rc"))"
            fail=$((fail+1)); continue
        fi
        read -r _ p _ f _ <<< "$line"
        pass=$((pass+p)); fail=$((fail+f))
    done
    echo "(${#PARTS[@]} parts on $JOBS jobs; the longest, ${PARTS[$slow]}, took $(cat "$PW/$slow.t")s)"
    echo "smoke: $pass passed, $fail failed"
    [[ $fail -eq 0 ]]; exit
fi

if _part core; then
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
fi

if _part recon-unsorted; then
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
check "show unsorted --tsv decodes too, one input per line" $'c0002\tp\\tq\\nsecond line' \
    "$(PROVOST_WORKSPACE="$UWS" "$PROVOST" show unsorted --tsv 2>&1)"
fi

if _part rm; then
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
free_before="$(cat "$RMWS/datasets/free.tsv")"
rm_purge_out="$(PROVOST_WORKSPACE="$RMWS" "$PROVOST" rm -f free 2>&1)"
check "rm purges the source capture dir by default" "true" \
    "$([[ ! -d "$RMWS/captures/c0002" ]] && echo true)"
# what it says about getting the data back is true: follow it (PV-016)
check "rm says where the deleted data still is" "git's history (the commit before this one) still holds what was there" "$rm_purge_out"
check_not "rm does not promise restore reaches a purged capture" "restore" "$rm_purge_out"
check "the commit before rm's holds the deleted dataset" "$free_before" \
    "$(git -C "$RMWS" show HEAD~1:datasets/free.tsv 2>&1)"
check "a purged capture is gone for restore, as rm implies" "no such capture" \
    "$(PROVOST_WORKSPACE="$RMWS" "$PROVOST" restore c0002 2>&1 || true)"
check "rm commits the deletion (history preserved)" "rm: deleted" \
    "$(git -C "$RMWS" log -1 --format=%s 2>&1)"
# capture ids are monotonic: after the purge of c0002 the next capture is
# c0003, never a reused c0002 (which would overwrite history/provenance)
reuse_out="$(PROVOST_WORKSPACE="$RMWS" "$PROVOST" run --name after printf 'x=1, y=2\n' 2>&1)"
check "capture ids are never reused after an rm purge" "c0003:" "$reuse_out"
fi

if _part rm-capture; then
# rm --capture: captures, and the rows they filed in every dataset they fed;
# a dataset left with no rows goes too. One commit; their tags go; ids are
# still never reused.
RCWS="$(mktemp -d)/.rmc"
rcp () { PROVOST_WORKSPACE="$RCWS" "$PROVOST" "$@"; }
rcp run --name t printf 'a b\n1 2\n3 4\n' >/dev/null 2>&1   # c0001 -> t
rcp run --name t printf 'a b\n5 6\n' >/dev/null 2>&1        # c0002 -> t
rcp run --name u printf 'x,y\n9,9\n' >/dev/null 2>&1        # c0003 -> u
check "rm --capture refuses a missing capture" "no such capture: c0009" "$(rcp rm -f --capture c0009 2>&1 || true)"
check "rm --capture refuses dataset names beside it (exit 2)" "2" "$(PROVOST_WORKSPACE="$RCWS" rc_of "$PROVOST" rm -f t --capture 1)"
check "rm --capture refuses a malformed id (exit 2)" "2" "$(PROVOST_WORKSPACE="$RCWS" rc_of "$PROVOST" rm -f --capture x1)"
check "rm --capture asks first, and no means no" "nothing deleted" "$(echo n | rcp rm --capture 2 2>&1)"
check "rm --capture: an answered no keeps the capture" "true" "$([[ -d "$RCWS/captures/c0002" ]] && echo true)"
rmc_out="$(rcp rm -f --capture c0002,3 2>&1)"
check "rm --capture reports the captures and their rows" "deleted 2 capture(s) (c0002 c0003) and the 2 row(s)" "$rmc_out"
check "rm --capture keeps the rows of the captures it was not given" "c0001" "$(cut -f2 "$RCWS/datasets/t.tsv")"
check_not "rm --capture drops the rows a capture filed" "c0002" "$(cut -f2 "$RCWS/datasets/t.tsv")"
check "rm --capture removes a dataset left with no rows" "true" "$([[ ! -f "$RCWS/datasets/u.tsv" ]] && echo true)"
check "rm --capture prunes their provenance rows" "0" "$(tail -n +2 "$RCWS/provenance.tsv" | grep -c 'c000[23]' || true)"
check "rm --capture removes the capture dirs" "true" "$([[ ! -d "$RCWS/captures/c0002" && ! -d "$RCWS/captures/c0003" ]] && echo true)"
check "rm --capture removes their tags" "capture-c0001" "$(git -C "$RCWS" tag | tr '\n' ' ')"
check_not "rm --capture leaves no tag of a deleted capture" "capture-c0002" "$(git -C "$RCWS" tag | tr '\n' ' ')"
check "rm --capture is one commit" "rm: deleted 2 capture(s) [c0002 c0003], pruned 2 row(s), emptied 1 dataset(s) [u]" "$(git -C "$RCWS" log -1 --format=%s)"
check "rm --capture leaves the store clean" "clean" "$( [[ -z "$(git -C "$RCWS" status --porcelain)" ]] && echo clean)"
check "capture ids are never reused after rm --capture" "c0004:" "$(rcp run --name t printf 'a b\n7 8\n' 2>&1)"
# A data column named `capture` (provost's becomes `_capture`) or `#` is the
# tool's own: a value in it that matches a deleted capture or row must not
# take another capture's rows with it.
RCWS2="$(mktemp -d)/.rmc2"
rcq () { PROVOST_WORKSPACE="$RCWS2" "$PROVOST" "$@"; }
rcq run --name d printf 'capture,val\nc0009,1\n' >/dev/null 2>&1          # c0001 -> d
rcq run --name d printf 'capture,val\nc0001,2\nc0001,3\n' >/dev/null 2>&1 # c0002 -> d
rcq run --name h printf 'x,#\na,1\n' >/dev/null 2>&1                      # c0003 -> h
rcq run --name h printf 'x,#\nb,3\nc,4\n' >/dev/null 2>&1                 # c0004 -> h
rcq rm -f --capture 1,3 >/dev/null 2>&1
check "rm --capture keeps rows whose data column 'capture' names a deleted capture" "[c0002 c0002]" \
    "[$(tail -n +2 "$RCWS2/datasets/d.tsv" | cut -f2 | tr '\n' ' ' | sed 's/ $//')]"
check "rm --capture keeps rows whose data column '#' names a deleted row" "[b c]" \
    "[$(tail -n +2 "$RCWS2/datasets/h.tsv" | cut -f4 | tr '\n' ' ' | sed 's/ $//')]"
# A rewrite that fails part way changes nothing: an awk that refuses the
# second dataset must leave the first one, and the whole tree, untouched.
RCWS3="$(mktemp -d)/.rmc3"; RCFB="$(mktemp -d)"
printf '#!/usr/bin/env bash\nfor a in "$@"; do [ "$a" = ds=v ] && exit 7; done\nexec %q "$@"\n' "$(command -v awk)" > "$RCFB/awk"
chmod +x "$RCFB/awk"
rcr () { PROVOST_WORKSPACE="$RCWS3" "$PROVOST" "$@"; }
rcr run --name t printf 'a b\n1 2\n' >/dev/null 2>&1   # c0001 -> t
rcr run --name v printf 'a b\n3 4\n' >/dev/null 2>&1   # c0002 -> v
check "rm --capture: a failed rewrite says nothing was deleted" "nothing deleted" \
    "$(PATH="$RCFB:$PATH" rcr rm -f --capture 1,2 2>&1 || true)"
check "rm --capture: a failed rewrite leaves the store as it was" "clean t.tsv" \
    "$( [[ -z "$(git -C "$RCWS3" status --porcelain)" ]] && echo clean) $(ls "$RCWS3/datasets" | grep -x t.tsv)"
# ...and so does a move into the store that fails part way: what was moved
# is put back. No scratch directory is left behind either way.
RCFB2="$(mktemp -d)"
printf '#!/usr/bin/env bash\ncase "$1" in */.rm.*/prov) exit 7 ;; esac\nexec %q "$@"\n' "$(command -v mv)" > "$RCFB2/mv"
chmod +x "$RCFB2/mv"
check "rm --capture: a failed move puts the store back" "put back as it was" \
    "$(PATH="$RCFB2:$PATH" rcr rm -f --capture 1,2 2>&1 || true)"
check "rm --capture: after a failed move the store is as it was" "clean t.tsv v.tsv" \
    "$( [[ -z "$(git -C "$RCWS3" status --porcelain)" ]] && echo clean) $(ls "$RCWS3/datasets" | tr '\n' ' ' | sed 's/ $//')"
check "rm --capture leaves no scratch directory behind" "0" "$(find "$RCWS3/datasets" -name '.rm.*' | wc -l | tr -d ' ')"
# Killed while rewriting: the store as it was, the lock released, and its
# scratch directory gone with it.
RCFB3="$(mktemp -d)"
printf '#!/usr/bin/env bash\nfor a in "$@"; do [ "$a" = ds=v ] && { kill -TERM "$PPID"; sleep 1; exit 7; }; done\nexec %q "$@"\n' "$(command -v awk)" > "$RCFB3/awk"
chmod +x "$RCFB3/awk"
check "rm --capture killed part way exits 143" "143" "$(PATH="$RCFB3:$PATH" PROVOST_WORKSPACE="$RCWS3" rc_of "$PROVOST" rm -f --capture 1,2)"
check "rm --capture killed part way leaves the store, and no scratch dir" "clean 0" \
    "$( [[ -z "$(git -C "$RCWS3" status --porcelain)" ]] && echo clean) $(find "$RCWS3/datasets" -name '.rm.*' | wc -l | tr -d ' ')"
check "rm --capture killed part way releases the lock" "deleted 2 capture(s)" "$(rcr rm -f --capture 1,2 2>&1)"
# Provenance is the record: a reconciled dataset can hold a data value in
# provost's capture position (a later capture brought a `capture` column),
# and only provenance says whose row is whose.
RCWS4="$(mktemp -d)/.rmc4"
rcs () { PROVOST_WORKSPACE="$RCWS4" "$PROVOST" "$@"; }
rcs run --name d printf 'a,b,c\n1,2,3\n' >/dev/null 2>&1                 # c0001 -> d
rcs run --name d printf 'capture,a,b,c\nc0001,4,5,6\n' >/dev/null 2>&1   # c0002 -> d, reconciled
rcs rm -f --capture 1 >/dev/null 2>&1
check "rm --capture goes by provenance where the capture column disagrees" "[2]" \
    "[$(tail -n +2 "$RCWS4/datasets/d.tsv" 2>/dev/null | cut -f1 | tr '\n' ' ' | sed 's/ $//')]"
# Without provenance, provost's capture column is what is left to go by.
RCWS5="$(mktemp -d)/.rmc5"
rct () { PROVOST_WORKSPACE="$RCWS5" "$PROVOST" "$@"; }
rct run --name d printf 'a,b\n1,2\n' >/dev/null 2>&1    # c0001 -> d
rct run --name d printf 'a,b\n3,4\n' >/dev/null 2>&1    # c0002 -> d
rm -f "$RCWS5/provenance.tsv"
rct rm -f --capture 1 >/dev/null 2>&1
check "rm --capture with no provenance goes by provost's capture column" "[c0002]" \
    "[$(tail -n +2 "$RCWS5/datasets/d.tsv" 2>/dev/null | cut -f2 | tr '\n' ' ' | sed 's/ $//')]"
# Killed while moving into the store: the signal is held until the
# deletion is committed (not left half done), and then sets the exit status.
RCWS6="$(mktemp -d)/.rmc6"; RCFB4="$(mktemp -d)"
rcu () { PROVOST_WORKSPACE="$RCWS6" "$PROVOST" "$@"; }
rcu run --name t printf 'a b\n1 2\n' >/dev/null 2>&1   # c0001 -> t
rcu run --name t printf 'a b\n3 4\n' >/dev/null 2>&1   # c0002 -> t
printf '#!/usr/bin/env bash\ncase "$1" in */.rm.*/prov) kill -TERM -- "$(pg=$(ps -o pgid= -p $$ | tr -d " "); p=$PPID; while q=$(ps -o pgid= -p $p | tr -d " "); [ "$q" = "$pg" ]; do p=$(ps -o ppid= -p $p | tr -d " "); done; echo "-$q")" ;; esac\nexec %q "$@"\n' "$(command -v mv)" > "$RCFB4/mv"
chmod +x "$RCFB4/mv"
rcu_rc="$(PATH="$RCFB4:$PATH" PROVOST_WORKSPACE="$RCWS6" rc_of own_pg "$PROVOST" rm -f --capture 1)"
check "rm --capture killed while moving exits 143 once committed" "143" "$rcu_rc"
check "rm --capture killed while moving still completes, committed" "clean c0002" \
    "$( [[ -z "$(git -C "$RCWS6" status --porcelain)" ]] && echo clean) $(tail -n +2 "$RCWS6/datasets/t.tsv" | cut -f2 | sort -u | tr '\n' ' ' | sed 's/ $//')"
# A dataset deleted while rm --capture waits at its prompt (before it takes
# the lock) is skipped, not an error.
rcu run --name w printf 'a b\n5 6\n' >/dev/null 2>&1   # c0003 -> w
rcu run --name w printf 'a b\n7 8\n' >/dev/null 2>&1   # c0004 -> w
# The deletion waits for the prompt (up to 10 s): sent any earlier, it could
# land while rm --capture is still reading the datasets, which under load
# (the parts run in parallel) it did.
gone_err="$(mktemp)"
gone_out="$( { for _ in $(seq 100); do grep -q 'Proceed?' "$gone_err" && break; sleep 0.1; done
               rcu rm -f --no-purge w >/dev/null 2>&1; echo y; } | rcu rm --capture 3 2>&1 | tee "$gone_err" || true)"
check "rm --capture skips a dataset deleted while it waited" "deleted 1 capture(s) (c0003)" "$gone_out"
check "rm --capture after a dataset went while it waited leaves the store clean" "clean" \
    "$( [[ -z "$(git -C "$RCWS6" status --porcelain)" ]] && echo clean)"
# A failure after the datasets are moved (removing a capture dir, here)
# puts the whole store back from HEAD: rows, provenance, dirs and tags.
RCWS7="$(mktemp -d)/.rmc7"; RCFB5="$(mktemp -d)"
rcv () { PROVOST_WORKSPACE="$RCWS7" "$PROVOST" "$@"; }
rcv run --name d printf 'a b\n1 2\n' >/dev/null 2>&1   # c0001 -> d
rcv run --name d printf 'a b\n3 4\n' >/dev/null 2>&1   # c0002 -> d
rcv run --name e printf 'x y\n9 9\n' >/dev/null 2>&1   # c0003 -> e
printf '#!/usr/bin/env bash\nfor a in "$@"; do case "$a" in */captures/c0001) exit 7 ;; esac; done\nexec %q "$@"\n' "$(command -v rm)" > "$RCFB5/rm"
chmod +x "$RCFB5/rm"
check "rm --capture: a late failure puts the store back" "put back as it was" \
    "$(PATH="$RCFB5:$PATH" rcv rm -f --capture 1,3 2>&1 || true)"
check "rm --capture: after a late failure, store, dirs and tags as they were" "clean e.tsv c0001 c0003 3" \
    "$( [[ -z "$(git -C "$RCWS7" status --porcelain)" ]] && echo clean) $(ls "$RCWS7/datasets" | grep -x e.tsv) $(ls "$RCWS7/captures" | grep -x c0001) $(ls "$RCWS7/captures" | grep -x c0003) $(git -C "$RCWS7" tag | wc -l | tr -d ' ')"
# A hangup (an ssh session dropping) while it applies: held like INT/TERM.
printf '#!/usr/bin/env bash\ncase "$1" in */.rm.*/prov) kill -HUP -- "$(pg=$(ps -o pgid= -p $$ | tr -d " "); p=$PPID; while q=$(ps -o pgid= -p $p | tr -d " "); [ "$q" = "$pg" ]; do p=$(ps -o ppid= -p $p | tr -d " "); done; echo "-$q")" ;; esac\nexec %q "$@"\n' "$(command -v mv)" > "$RCFB5/mv"
chmod +x "$RCFB5/mv"; rm -f "$RCFB5/rm"
rch_rc="$(PATH="$RCFB5:$PATH" PROVOST_WORKSPACE="$RCWS7" rc_of own_pg "$PROVOST" rm -f --capture 1,3)"
check "rm --capture hung up while applying commits, then exits 129" "129 clean d.tsv" \
    "$rch_rc $( [[ -z "$(git -C "$RCWS7" status --porcelain)" ]] && echo clean) $(ls "$RCWS7/datasets" | tr '\n' ' ' | sed 's/ $//')"
# A commit that fails puts the store back, and the tags stay.
printf '#!/usr/bin/env bash\nfor a in "$@"; do [ "$a" = commit ] && exit 7; done\nexec %q "$@"\n' "$(command -v git)" > "$RCFB5/git"
chmod +x "$RCFB5/git"; rm -f "$RCFB5/mv"
check "rm --capture: a failed commit puts the store back" "put back as it was" \
    "$(PATH="$RCFB5:$PATH" rcv rm -f --capture 2 2>&1 || true)"
check "rm --capture: a failed commit keeps the tags and the capture" "clean capture-c0002 c0002" \
    "$( [[ -z "$(git -C "$RCWS7" status --porcelain)" ]] && echo clean) $(git -C "$RCWS7" tag | grep -x capture-c0002) $(ls "$RCWS7/captures" | grep -x c0002)"
# It will not start over uncommitted changes to what it would touch (they
# could not be put back), and says so.
printf '#\tcapture\tn\ta\tb\n' >> "$RCWS7/datasets/d.tsv"
check "rm --capture refuses over uncommitted changes" "uncommitted changes" "$(rcv rm -f --capture 2 2>&1 || true)"
git -C "$RCWS7" checkout -q -- datasets
# Anything else uncommitted in the store is not this commit's, and is left
# as it was: an edited .provostrc, an untracked file.
RCWS8="$(mktemp -d)/.rmc8"; RCFB6="$(mktemp -d)"
rcw () { PROVOST_WORKSPACE="$RCWS8" "$PROVOST" "$@"; }
rcw run --name t printf 'a b\n1 2\n' >/dev/null 2>&1   # c0001 -> t
rcw run --name t printf 'a b\n3 4\n' >/dev/null 2>&1   # c0002 -> t
rcw run --name u printf 'x y\n5 6\n' >/dev/null 2>&1   # c0003 -> u
echo 'min_confidence=0.1' >> "$RCWS8/.provostrc"; echo 'notes' > "$RCWS8/notes.txt"
rcw rm -f --capture 2 >/dev/null 2>&1
check_not "rm --capture commits only what it deleted" "notes.txt" "$(git -C "$RCWS8" show --stat --format= HEAD)"
check "rm --capture leaves other uncommitted changes as they were" "[ M .provostrc|?? notes.txt]" \
    "[$(git -C "$RCWS8" status --porcelain | sort | tr '\n' '|' | sed 's/|$//')]"
# ...and a hand edit to a dataset it does not touch still stops it.
git -C "$RCWS8" checkout -q -- .provostrc; rm -f "$RCWS8/notes.txt"
rcw rm -f --no-purge u >/dev/null 2>&1
printf '99\tc0009\t1\tUSER\tEDIT\n' >> "$RCWS8/datasets/t.tsv"
check "rm --capture refuses over an edited dataset it would not touch" "uncommitted changes" "$(rcw rm -f --capture 3 2>&1 || true)"
git -C "$RCWS8" checkout -q -- datasets
# A git add that fails puts the store back too.
printf '#!/usr/bin/env bash\nfor a in "$@"; do [ "$a" = add ] && exit 7; done\nexec %q "$@"\n' "$(command -v git)" > "$RCFB6/git"
chmod +x "$RCFB6/git"
check "rm --capture: a failed git add puts the store back" "put back as it was" "$(PATH="$RCFB6:$PATH" rcw rm -f --capture 1 2>&1 || true)"
check "rm --capture: after a failed git add the store is clean" "clean" "$( [[ -z "$(git -C "$RCWS8" status --porcelain)" ]] && echo clean)"
# Interrupted while committing (the commit then fails): put back, and the
# exit status says it was interrupted.
printf '#!/usr/bin/env bash\nfor a in "$@"; do [ "$a" = commit ] && { kill -INT -- "$(pg=$(ps -o pgid= -p $$ | tr -d " "); p=$PPID; while q=$(ps -o pgid= -p $p | tr -d " "); [ "$q" = "$pg" ]; do p=$(ps -o ppid= -p $p | tr -d " "); done; echo "-$q")"; exit 1; }; done\nexec %q "$@"\n' "$(command -v git)" > "$RCFB6/git"
check "rm --capture interrupted in the commit is put back, exit 130" "130 clean" \
    "$(PATH="$RCFB6:$PATH" PROVOST_WORKSPACE="$RCWS8" rc_of own_pg "$PROVOST" rm -f --capture 1) $( [[ -z "$(git -C "$RCWS8" status --porcelain)" ]] && echo clean)"
# Tags it could not delete are reported as still there, not as gone.
printf '#!/usr/bin/env bash\nfor a in "$@"; do [ "$a" = update-ref ] && exit 7; done\nexec %q "$@"\n' "$(command -v git)" > "$RCFB6/git"
tag_out="$(PATH="$RCFB6:$PATH" rcw rm -f --capture 1 2>&1)"
check "rm --capture says when its tags could not go" "tags are still there" "$tag_out"
check_not "rm --capture does not claim the tags went when they did not" "tags went with them" "$tag_out"
# Something someone already staged is not swept into its commit either.
rcw run --name s printf 'a b\n1 1\n' >/dev/null 2>&1   # c0004 -> s
echo 'staged' > "$RCWS8/staged.txt"; git -C "$RCWS8" add staged.txt
rcw rm -f --capture 3 >/dev/null 2>&1 || true
check_not "rm --capture does not commit what was staged beside it" "staged.txt" "$(git -C "$RCWS8" show --stat --format= HEAD)"
check "rm --capture leaves a staged file staged" "A  staged.txt" "$(git -C "$RCWS8" status --porcelain)"
tgit "$RCWS8" commit -qm 'stray' >/dev/null 2>&1 || true
# A Ctrl-C (which reaches every process in the group) while it puts the
# store back does not stop the put-back: its git runs with INT ignored. The
# stand-in git sends itself INT before it checks out; it survives only if
# INT is ignored.
printf '#!/usr/bin/env bash\nfor a in "$@"; do [ "$a" = commit ] && exit 1; [ "$a" = checkout ] && kill -INT $$; done\nexec %q "$@"\n' "$(command -v git)" > "$RCFB6/git"
PATH="$RCFB6:$PATH" rcw rm -f --capture 4 >/dev/null 2>&1 || true
check "rm --capture's put-back survives a Ctrl-C" "[]" "[$(git -C "$RCWS8" status --porcelain | tr '\n' '|')]"
# A put-back that git itself fails once (a Ctrl-C that reached it) is
# tried again, and the store ends as it was.
printf '#!/usr/bin/env bash\nfor a in "$@"; do [ "$a" = commit ] && exit 1; [ "$a" = checkout ] && [ ! -e %q/once ] && { : > %q/once; exit 1; }; done\nexec %q "$@"\n' "$RCFB6" "$RCFB6" "$(command -v git)" > "$RCFB6/git"
check "rm --capture tries the put-back again" "put back as it was" "$(PATH="$RCFB6:$PATH" rcw rm -f --capture 4 2>&1 || true)"
check "rm --capture: after a retried put-back the store is clean" "[]" "[$(git -C "$RCWS8" status --porcelain | tr '\n' '|')]"
# A commit that lands although git then fails is a deletion, said as one.
printf '#!/usr/bin/env bash\nfor a in "$@"; do [ "$a" = commit ] && { %q "$@"; exit 1; }; done\nexec %q "$@"\n' "$(command -v git)" "$(command -v git)" > "$RCFB6/git"
landed_out="$(PATH="$RCFB6:$PATH" rcw rm -f --capture 4 2>&1 || true)"
check "rm --capture: a commit that landed is reported as done" "deleted 1 capture(s) (c0004)" "$landed_out"
check "rm --capture: a commit that landed takes the tag too" "[]" "[$(git -C "$RCWS8" tag | grep -x capture-c0004 || true)]"
# The tag hint is a command that can be pasted as it is.
rcw run --name s printf 'a b\n2 2\n' >/dev/null 2>&1   # c0005 -> s
printf '#!/usr/bin/env bash\nfor a in "$@"; do [ "$a" = update-ref ] && exit 7; done\nexec %q "$@"\n' "$(command -v git)" > "$RCFB6/git"
check "rm --capture's tag hint ends with the tag" "[tag -d capture-c0005]" \
    "[$(PATH="$RCFB6:$PATH" rcw rm -f --capture 5 2>&1 | grep 'could not delete their tags' | sed 's/.*\(tag -d .*\)$/\1/')]"
git -C "$RCWS8" tag -d capture-c0005 >/dev/null 2>&1 || true
# With no dataset tracked yet, a dataset file it would rewrite is still
# covered: untracked, it stops the deletion.
RCWS9="$(mktemp -d)/.rmc9"
rcx () { PROVOST_WORKSPACE="$RCWS9" "$PROVOST" "$@"; }
rcx run --name t printf 'a b\n1 2\n' >/dev/null 2>&1   # c0001 -> t
rcx run --name t printf 'a b\n3 4\n' >/dev/null 2>&1   # c0002 -> t
cp "$RCWS9/datasets/t.tsv" "$RCWS9/t.keep"; rcx rm -f --no-purge t >/dev/null 2>&1; mv "$RCWS9/t.keep" "$RCWS9/datasets/t.tsv"
check "rm --capture refuses over an untracked dataset it would rewrite" "uncommitted changes" "$(rcx rm -f --capture 1 2>&1 || true)"
check "rm --capture leaves an untracked dataset as it was" "2" "$(tail -n +2 "$RCWS9/datasets/t.tsv" | wc -l | tr -d ' ')"
# ...and untracked files are seen whatever status.showUntrackedFiles says.
mv "$RCWS9/datasets/t.tsv" "$RCWS9/t.keep"; git -C "$RCWS9" config status.showUntrackedFiles no
echo notes > "$RCWS9/captures/c0001/notes.txt"
check "rm --capture sees untracked files under showUntrackedFiles=no" "uncommitted changes" "$(rcx rm -f --capture 2 2>&1 || true)"
# Another git holding the store's index (a shell prompt's git status, an
# editor): refused before anything changes...
RCWS10="$(mktemp -d)/.rmc10"; RCFB7="$(mktemp -d)"
rcz () { PROVOST_WORKSPACE="$RCWS10" "$PROVOST" "$@"; }
rcz run --name t printf 'a b\n1 2\n' >/dev/null 2>&1   # c0001 -> t
rcz run --name t printf 'a b\n3 4\n' >/dev/null 2>&1   # c0002 -> t
: > "$RCWS10/.git/index.lock"
check "rm --capture refuses while another git holds the index" "another git is using the store" "$(rcz rm -f --capture 1 2>&1 || true)"
check "rm --capture refused over index.lock changes nothing" "[]" "[$(git -C "$RCWS10" status --porcelain 2>/dev/null | tr '\n' '|')]"
rm -f "$RCWS10/.git/index.lock"
# ...and one that takes the index part way is waited out by the put-back.
printf '#!/usr/bin/env bash\nfor a in "$@"; do [ "$a" = add ] && { : > %q; ( sleep 0.3; rm -f %q ) & exit 1; }; done\nexec %q "$@"\n' "$RCWS10/.git/index.lock" "$RCWS10/.git/index.lock" "$(command -v git)" > "$RCFB7/git"
chmod +x "$RCFB7/git"
check "rm --capture's put-back waits out a git holding the index" "put back as it was" "$(PATH="$RCFB7:$PATH" rcz rm -f --capture 1 2>&1 || true)"
sleep 0.4
check "rm --capture: after waiting out the index the store is clean" "[]" "[$(git -C "$RCWS10" status --porcelain | tr '\n' '|')]"
# Interrupted while deleting the tags: it finishes them, says so, and then
# exits 130.
printf '#!/usr/bin/env bash\nfor a in "$@"; do [ "$a" = update-ref ] && kill -INT -- "$(pg=$(ps -o pgid= -p $$ | tr -d " "); p=$PPID; while q=$(ps -o pgid= -p $p | tr -d " "); [ "$q" = "$pg" ]; do p=$(ps -o ppid= -p $p | tr -d " "); done; echo "-$q")"; done\nexec %q "$@"\n' "$(command -v git)" > "$RCFB7/git"
tagint_out="$(PATH="$RCFB7:$PATH" PROVOST_WORKSPACE="$RCWS10" own_pg "$PROVOST" rm -f --capture 1 2>&1; echo "rc=$?")"
check "rm --capture interrupted in the tag phase still deletes the tags, then exits 130" "rc=130 []" \
    "$(printf '%s' "$tagint_out" | tail -n 1) [$(git -C "$RCWS10" tag | grep -x capture-c0001 || true)]"
check "rm --capture interrupted in the tag phase still says what it deleted" "deleted 1 capture(s) (c0001)" "$tagint_out"
# A commit whose git is killed after moving HEAD (the index not yet
# written): done, and the store left clean, its index HEAD's.
printf '#!/usr/bin/env bash
for a in "$@"; do [ "$a" = commit ] && { %q "$@"; %q -C %q read-tree HEAD~1 2>/dev/null; exit 130; }; done
exec %q "$@"
' "$(command -v git)" "$(command -v git)" "$RCWS10" "$(command -v git)" > "$RCFB7/git"
check "rm --capture: a commit killed after landing is done" "deleted 1 capture(s) (c0002)" "$(PATH="$RCFB7:$PATH" rcz rm -f --capture 2 2>&1 || true)"
check "rm --capture: after a commit killed after landing the store is clean" "[]" "[$(git -C "$RCWS10" status --porcelain | tr '\n' '|')]"
# The shell that took the lock killed outright while its commit runs: the
# lock stays live until the commit is done (the next provost waits), and
# the deletion is its own commit, not swept into the next one.
RCWS11="$(mktemp -d)/.rmc11"; RCFB8="$(mktemp -d)"
rck () { PROVOST_WORKSPACE="$RCWS11" "$PROVOST" "$@"; }
rck run --name t printf 'a b\n1 2\n' >/dev/null 2>&1   # c0001 -> t
rck run --name t printf 'a b\n3 4\n' >/dev/null 2>&1   # c0002 -> t
printf '#!/usr/bin/env bash\nfor a in "$@"; do [ "$a" = commit ] && { : > %q/at-commit; sleep 1.5; }; done\nexec %q "$@"\n' "$RCFB8" "$(command -v git)" > "$RCFB8/git"
chmod +x "$RCFB8/git"
PATH="$RCFB8:$PATH" PROVOST_WORKSPACE="$RCWS11" "$PROVOST" rm -f --capture 2 >/dev/null 2>&1 &
rck_pid=$!
for _ in $(seq 1 100); do [[ -e "$RCFB8/at-commit" ]] && break; sleep 0.1; done   # kill it in its commit, not before
kill -KILL "$rck_pid" 2>/dev/null || true; wait "$rck_pid" 2>/dev/null || true
PROVOST_LOCK_TIMEOUT=10 rck run --name u printf 'x y\n5 6\n' >/dev/null 2>&1
check "rm --capture whose shell was killed still commits on its own" "[rm: deleted 1 capture(s) [c0002], pruned 1 row(s)]" \
    "[$(git -C "$RCWS11" log -2 --format=%s | tail -n 1)]"
check "...and the next capture waited for it, its commit its own" "capture c0003" "$(git -C "$RCWS11" log -1 --format=%s)"
check_not "...which did not take the deletion with it" "captures/c0002" "$(git -C "$RCWS11" show --stat --format= HEAD)"
# The child killed outright just after its commit landed: done, said so,
# and the lock released (not left under the dead child's pid).
rck run --name t printf 'a b\n7 8\n' >/dev/null 2>&1   # c0004 -> t
printf '#!/usr/bin/env bash\nfor a in "$@"; do [ "$a" = commit ] && { %q "$@"; kill -KILL $PPID; exit 0; }; done\nexec %q "$@"\n' "$(command -v git)" "$(command -v git)" > "$RCFB8/git"
chmod +x "$RCFB8/git"
dead_out="$(PATH="$RCFB8:$PATH" rck rm -f --capture 4 2>&1 || true)"
check "rm --capture whose child died after landing says it deleted" "deleted 1 capture(s) (c0004)" "$dead_out"
check "rm --capture whose child died leaves no lock" "no" "$([[ -e "$RCWS11/.lock" ]] && echo yes || echo no)"
check "rm --capture whose child died before its tags says they are still there" "tags are still there" "$dead_out"
git -C "$RCWS11" tag -d capture-c0004 >/dev/null 2>&1 || true; rm -f "$RCFB8/git"
# A lock another provost has taken meanwhile (here: broken as stale by
# age) is not handed back over nor removed by rm --capture's child.
printf '#!/usr/bin/env bash\nfor a in "$@"; do [ "$a" = commit ] && { printf "otherhost\\t1\\t0\\t1\\n" > %q/.lock/owner; }; done\nexec %q "$@"\n' "$RCWS11" "$(command -v git)" > "$RCFB8/git"
chmod +x "$RCFB8/git"
PATH="$RCFB8:$PATH" rck rm -f --capture 3 >/dev/null 2>&1 || true
check "rm --capture leaves another provost's lock alone" "[otherhost	1	0	1]" "[$(cat "$RCWS11/.lock/owner" 2>/dev/null)]"
rm -rf "$RCWS11/.lock"; rm -f "$RCFB8/git"
# A lock broken and taken from it before it changed anything (here a stand-in
# git, at rm's first add, swaps the owner record as another provost would):
# it stops there, nothing deleted.
rck run --name t printf 'a b\n9 9\n' >/dev/null 2>&1   # c0005 -> t
printf '#!/usr/bin/env bash\nfor a in "$@"; do [ "$a" = status ] && printf "otherhost\\t1\\t0\\t1\\n" > %q/.lock/owner; done\nexec %q "$@"\n' "$RCWS11" "$(command -v git)" > "$RCFB8/git"
chmod +x "$RCFB8/git"
taken_out="$(PATH="$RCFB8:$PATH" rck rm -f --capture 5 2>&1 || true)"
check "rm --capture stops when its lock was taken from it" "nothing deleted" "$taken_out"
check_not "rm --capture whose lock was taken does not say it put anything back" "put back" "$taken_out"
check "rm --capture whose lock was taken changed nothing" "yes []" \
    "$([[ -d "$RCWS11/captures/c0005" ]] && echo yes) [$(git -C "$RCWS11" status --porcelain | tr '\n' '|')]"
rm -rf "$RCWS11/.lock"; rm -f "$RCFB8/git"
check_not "rm --capture whose child died after landing prints no raw error" "No such file" "$dead_out"
# A lock-break mutex left behind (a provost interrupted while breaking a
# stale lock) does not stop rm --capture for good: one over a minute old
# is cleared, as _lock_break itself would.
rck run --name t printf 'a b\n6 6\n' >/dev/null 2>&1   # c0006 -> t
mkdir "$RCWS11/.lock.break"; touch -d '2 hours ago' "$RCWS11/.lock.break" 2>/dev/null || touch -t 200001010000 "$RCWS11/.lock.break"
check "rm --capture clears an abandoned lock-break mutex" "deleted 1 capture(s) (c0006)" "$(rck rm -f --capture 6 2>&1 || true)"
check "...and leaves none behind" "no" "$([[ -e "$RCWS11/.lock.break" ]] && echo yes || echo no)"
# One that cannot be removed (here: not empty) is waited out, not spun on:
# it gives up within seconds, nothing deleted, and says what is in the way.
rck run --name t printf 'a b\n6 7\n' >/dev/null 2>&1   # c0007 -> t
mkdir -p "$RCWS11/.lock.break/x"; touch -d '2 hours ago' "$RCWS11/.lock.break" 2>/dev/null || touch -t 200001010000 "$RCWS11/.lock.break"
stuck_s=$SECONDS; stuck_out="$(rck rm -f --capture 7 2>&1 || true)"; stuck_s=$((SECONDS - stuck_s))
check "rm --capture gives up on a lock-break mutex it cannot clear" "lock-break mutex" "$stuck_out"
check "...within seconds, nothing deleted" "yes yes" "$( (( stuck_s < 15 )) && echo yes) $([[ -d "$RCWS11/captures/c0007" ]] && echo yes)"
rm -rf "$RCWS11/.lock.break"
# What made it fail is shown, not swallowed.
printf '#!/usr/bin/env bash\ncase "$1" in */.rm.*/prov) echo "mv: No space left on device" >&2; exit 1 ;; esac\nexec %q "$@"\n' "$(command -v mv)" > "$RCFB8/mv"
rm -f "$RCFB8/git"; chmod +x "$RCFB8/mv"
check "rm --capture shows why it failed" "No space left on device" "$(PATH="$RCFB8:$PATH" rck rm -f --capture 1 2>&1 || true)"
# Rows are counted by record: a dataset without a final newline.
rcw run --name n printf 'a b\n7 8\n' >/dev/null 2>&1   # c0006 -> n
rcw run --name n printf 'a b\n9 9\n' >/dev/null 2>&1   # c0007 -> n
printf '%s' "$(cat "$RCWS8/datasets/n.tsv")" > "$RCWS8/datasets/n.tsv"; tgit "$RCWS8" commit -qam 'no final newline' >/dev/null 2>&1
check "rm --capture counts a row in a dataset without a final newline" "the 1 row(s) they filed" "$(rcw rm -f --capture 7 2>&1)"
# The prompt counts the rows that will go, provenance or not.
check "rm --capture's prompt counts rows found without provenance" "the 1 row(s) they filed" \
    "$(rm -f "$RCWS7/provenance.tsv"; tgit "$RCWS7" commit -qam 'drop provenance' >/dev/null 2>&1; echo n | rcv rm --capture 2 2>&1)"
fi

if _part async; then
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
fi

if _part core; then
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
fi

if _part concurrency; then
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
fi

if _part lock; then
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
fi

if _part control; then
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
# rm --capture takes a capture's files-<id> tag with it (its files are no
# longer served), and leaves the others' alone.
PROVOST_WORKSPACE="$PROJ/.provost" "$PROVOST" rm -f --capture 5 >/dev/null 2>&1
check "rm --capture deletes the capture's files tag" "no yes" \
    "$(git -C "$PROJ/.provost" rev-parse -q --verify files-c0005 >/dev/null && echo yes || echo no) $(git -C "$PROJ/.provost" rev-parse -q --verify files-c0004 >/dev/null && echo yes || echo no)"
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
fi

if _part core; then
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
# PV-013, on spent benchmark inputs: a tool-specific parser reading a part
# must keep the gate's coverage of it (round 4's 048 was filed wrong when
# git-annex-list read a pytest rule line at 50%); a positional table is filed
# when nothing shows a lost header (137: 'Speed : 259,207 Bytes/sec.' rows),
# and declined for box chrome (round 2's 102), a header-like line right above
# it (round 3's 115: the header sat over a rule line) or rows shredded into
# words (round 4's 031).
BR="$HERE/benchmark"
am_out="$(PROVOST_WORKSPACE="$AWS" "$PROVOST" --sync "$BR/round4/inputs/048-pytest-ra-report.txt" 2>&1)"
check "a tool-specific parser under the gate's coverage sinks the split" \
    "git-annex-list, a tool-specific parser) keeps 50% of its lines" "$am_out"
am_out="$(PROVOST_WORKSPACE="$AWS" "$PROVOST" --sync "$BR/round4/inputs/137-windows-robocopy-log.txt" 2>&1)"
check "a headerless positional part no longer sinks the split" "→ 6 datasets" "$am_out"
am_out="$(PROVOST_WORKSPACE="$AWS" "$PROVOST" --sync "$BR/round2/inputs/102-aws-ec2-describe-key-pairs-table.txt" 2>&1)"
check "a positional part of box chrome is still declined" "positional columns only: box chrome read as cells" "$am_out"
am_out="$(PROVOST_WORKSPACE="$AWS" "$PROVOST" --sync "$BR/round3/inputs/115-cisco-show-spanning-tree-vlan.txt" 2>&1)"
check "a positional part under a cut-off header is still declined" \
    "positional columns only: a header-like line sits right above it" "$am_out"
am_out="$(PROVOST_WORKSPACE="$AWS" "$PROVOST" --sync "$BR/round4/inputs/031-jstack-thread-dump.txt" 2>&1)"
check "a positional part of prose split into words is still declined" \
    "positional columns only: its cells are mostly empty" "$am_out"

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
fi

if _part llm; then
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
    # after a template Claude writes or extends comes the judge's review, and
    # after one it writes that sets aside lines carrying words, first its skip
    # audit (answered here with the same template: its skips judged
    # decoration): the fake API answers a list of replies in order (lt_then
    # FILE REPLY...)
    LT_PASS='{"id":"msg_j","type":"message","role":"assistant","model":"claude-opus-5-5","stop_reason":"end_turn","usage":{"input_tokens":1,"output_tokens":1},"content":[{"type":"text","text":"{\"verdict\": \"PASS\"}"}]}'
    lt_then () { local f="$1"; shift
        python3 -c 'import json, sys; print(json.dumps([json.load(open(sys.argv[1]))] + [json.loads(a) for a in sys.argv[2:]]))' "$f" "$@" > "$f.seq" && mv "$f.seq" "$f"; }
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
    lt_then "$LTD/reply.json" "$(cat "$LTD/reply.json")" "$LT_PASS"
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
    # SKIP AUDIT: the template sets aside lines that carry words (`-- ...`,
    # `// ...`), so learn showed Claude their count and a sample once; the
    # kinds it left in skip are recorded as judged decoration. Then THE
    # JUDGE reviewed what the template makes of the capture.
    check "the API was called three times in all: learn, its skip audit, then its review" "3" "$(wc -l < "$LTD/log" | tr -d ' ')"
    check "the audit shows what the template sets aside" "carry words or numbers, as decoration (skip)" "$(sed -n 2p "$LTD/log")"
    check "the review is the judge's" "Reviewing what a parsing template makes of a capture" "$(sed -n 3p "$LTD/log")"
    check "the kinds Claude left in skip are judged decoration" ", 0 set aside of a kind not judged" "$(python3 "$HERE/../extract/llm/template.py" audit "$LTWS/llm-templates/cmake-cache.json" "$LT_IN")"
    check "meta records the skip audit" "judged decoration, 0 not judged (counted as unread)" "$(grep '^llm_skip_audit' "$LTWS/captures/c0003/meta.tsv")"
    check "the ok line says the review passed it" "(llm-templates/cmake-cache.json), a review passed it" "$(cat "$LTWS/captures/c0003/meta.tsv")"
    check "the template keeps the verdict" '"verdict": "PASS"' "$(cat "$LTWS/llm-templates/cmake-cache.json")"
    # THE LEDGER: the template records each capture it files, and how
    check "the template's ledger records the captures it filed" "c0003 learned llm-templates/cmake-cache.json;c0004 read llm-templates/cmake-cache.json;" "$(tail -n +2 "$LTWS/llm-templates/cmake-cache.seen.tsv" | cut -f1-3 | tr '\t\n' ' ;')"
    check "the ledger is committed with the capture" "llm-templates/cmake-cache.seen.tsv" "$(git -C "$LTWS" show --stat HEAD 2>&1)"
    check "a shipped template's captures go in the store's ledger" "c0001	read	shipped:mcstatus.json" "$(cat "$LTWS/llm-templates/mcstatus.seen.tsv")"
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
    lt_then "$LTD/reply.json" "$(cat "$LTD/reply.json")" "$LT_PASS"
    rm -f "$LTD/port" "$LTD/log"
    python3 "$HERE/fake_anthropic.py" "$LTD/port" "$LTD/log" "$LTD/reply.json" & LT_PID=$!
    for _ in $(seq 1 50); do [[ -s "$LTD/port" ]] && break; sleep 0.1; done
    LT_URL="http://127.0.0.1:$(cat "$LTD/port")"
    lt_out="$(PROVOST_WORKSPACE="$LTWS" PROVOST_LLM_BASE_URL="$LT_URL" PROVOST_LLM_API_KEY=k-test \
        "$PROVOST" --sync --llm --name volumes "$LTD/vol.txt" 2>&1)"
    kill "$LT_PID" 2>/dev/null || true; wait "$LT_PID" 2>/dev/null || true
    check "a generic parse the gate passed is offered to Claude first (learn, its skip audit, its review)" "3" "$(wc -l < "$LTD/log" | tr -d ' ')"
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
    lt_then "$LTD/reply.json" "$LT_PASS"
    rm -f "$LTD/port" "$LTD/log"
    python3 "$HERE/fake_anthropic.py" "$LTD/port" "$LTD/log" "$LTD/reply.json" & LT_PID=$!
    for _ in $(seq 1 50); do [[ -s "$LTD/port" ]] && break; sleep 0.1; done
    LT_URL="http://127.0.0.1:$(cat "$LTD/port")"
    lt_out="$(PROVOST_WORKSPACE="$LTWS" PROVOST_LLM_BASE_URL="$LT_URL" PROVOST_LLM_API_KEY=k-test \
        "$PROVOST" --sync --llm --name volumes "$LTD/vol2.txt" 2>&1)"
    kill "$LT_PID" 2>/dev/null || true; wait "$LT_PID" 2>/dev/null || true
    check "a stored template that meets a new kind of line is extended" "read by template volumes.json, which Claude extended for 1 unread line(s) of a kind it has not met (llm-templates/volumes.json)" "$lt_out"
    check "the extension reads the new line" "swap	8G	-	[SWAP]" "$(cat "$LTWS/datasets/volumes.tsv")"
    check "the repair was one API call, and its review one more" "2" "$(wc -l < "$LTD/log" | tr -d ' ')"
    check "the repaired template is reviewed on the new capture" "(llm-templates/volumes.json), a review passed it" "$lt_out"
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
    lt_then "$LTD/reply.json" "$LT_PASS"
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
    check "the ledger says how each capture was filed" "c0006 learned;c0007 read;c0008 extended;c0009 read;c0010 read;c0011 checked;" "$(tail -n +2 "$LTWS/llm-templates/volumes.seen.tsv" | cut -f1-2 | tr '\t\n' ' ;')"
    # EVERY CAPTURE IT WAS WRITTEN FROM: a template keeps only its first and
    # latest captures as examples (what Claude is shown); the ledger names the
    # rest, and an extension that no longer reads one of them is refused too.
    # Here vol2's capture (the swap line) is no longer among the examples.
    python3 -c 'import json, sys; p = sys.argv[1]; t = json.load(open(p)); t["examples"] = [e for e in t["examples"] if "[SWAP]" not in e]; json.dump(t, open(p, "w"), indent=1)' "$LTWS/llm-templates/volumes.json"
    { printf 'NAME     SIZE   USED   MOUNT\n'; for i in 1 2 3 4 5 6 7 8 9 10; do printf 'd%s       %sG    1G     /srv/d%s\n' "$i" "$i" "$i"; done; printf 'nfs      1T     200G   server:/export\n'; } > "$LTD/vol5.txt"
    printf '%s' '{"id":"msg_8","type":"message","role":"assistant","model":"claude-opus-5-5","stop_reason":"end_turn","usage":{"input_tokens":1,"output_tokens":1},"content":[{"type":"text","text":"{\"format\": 1, \"tool\": \"volumes\", \"detect\": \"^NAME\\\\s+SIZE\\\\s+USED\\\\s+MOUNT$\", \"skip\": [\"^Volumes on host \"], \"blocks\": [{\"name\": \"volumes\", \"kind\": \"table\", \"header\": \"^NAME\\\\s+SIZE\", \"line\": \"^(?P<name>\\\\S+)\\\\s+(?P<size>[\\\\d.]+[KMGT]?)\\\\s+(?P<used>[\\\\d.]+[KMGT]?)\\\\s+(?P<mount>/\\\\S*|\\\\S+:/\\\\S*)$\"}]}"}]}' > "$LTD/reply.json"
    rm -f "$LTD/port" "$LTD/log"
    python3 "$HERE/fake_anthropic.py" "$LTD/port" "$LTD/log" "$LTD/reply.json" & LT_PID=$!
    for _ in $(seq 1 50); do [[ -s "$LTD/port" ]] && break; sleep 0.1; done
    LT_URL="http://127.0.0.1:$(cat "$LTD/port")"
    lt_out="$(PROVOST_WORKSPACE="$LTWS" PROVOST_LLM_BASE_URL="$LT_URL" PROVOST_LLM_API_KEY=k-test \
        "$PROVOST" --sync --llm --name volumes "$LTD/vol5.txt" 2>&1)"
    kill "$LT_PID" 2>/dev/null || true; wait "$LT_PID" 2>/dev/null || true
    check "an extension that loses a capture beyond the examples is refused" "on another capture it was written from (1 of 1, not shown above) it no longer reads 1 line(s) the template read" "$lt_out"
    check "that capture is checked, not sent" "0" "$(head -n 1 "$LTD/log" | grep -c '/var/log')"
    check "the stored template is used as it was, after one more try" "2 read by template volumes.json (Claude could not extend it" "$(wc -l < "$LTD/log" | tr -d ' ') $(printf '%s\n' "$lt_out" | grep -o 'read by template volumes.json (Claude could not extend it')"
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
    lt_then "$LTD/reply.json" "$(cat "$LTD/reply.json")" "$LT_PASS"
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
    # SKIP AUDIT, in the gate: a skipped line that carries words is not
    # covered for free. A template (here from a library, no key) whose skip
    # lines no one has judged counts them as unread; once their kind is
    # judged decoration (its "decoration" record) they are not counted.
    printf 'Note: inventory taken nightly\nNote: sizes in GB\nNAME   SIZE\nalpha  10\nbeta   20\ngamma  30\n' > "$LTD/inv.txt"
    mkdir -p "$LTD/lib"
    printf '%s' '{"format": 1, "tool": "inventory", "detect": "^NAME\\s+SIZE$", "skip": ["^Note: "], "blocks": [{"name": "items", "kind": "table", "header": "^NAME\\s+SIZE$", "line": "^(?P<name>[a-z]+)\\s+(?P<size>\\d+)$"}]}' > "$LTD/lib/inventory.json"
    check "template.py audit counts and samples what it sets aside" "2 skipped: 0 decoration, 0 set aside of a kind judged decoration, 2 set aside of a kind not judged (counted as unread); coverage 67%
0 |Note: inventory taken nightly
    (2 lines of this kind)" "$(python3 "$HERE/../extract/llm/template.py" audit "$LTD/lib/inventory.json" "$LTD/inv.txt")"
    lt_out="$(PROVOST_WORKSPACE="$LTD/.inv" PROVOST_LLM_TEMPLATE_DIRS="$LTD/lib" "$PROVOST" --sync --llm --name inventory "$LTD/inv.txt" 2>&1)"
    check "set-aside lines not judged count as unread" "template inventory.json does not fit: its 1 block(s) keep 66% of the input's data lines" "$(cat "$LTD/.inv/captures/c0001/meta.tsv")"
    python3 -c 'import json, sys; p = sys.argv[1]; t = json.load(open(p)); t["decoration"] = ["Note: a"]; json.dump(t, open(p, "w"))' "$LTD/lib/inventory.json"
    lt_out="$(PROVOST_WORKSPACE="$LTD/.inv" PROVOST_LLM_TEMPLATE_DIRS="$LTD/lib" "$PROVOST" --sync --llm --name inventory "$LTD/inv.txt" 2>&1)"
    check "judged decoration, they are not counted" "read by template inventory.json." "$lt_out"
    check "and meta says so" "llm_skip_audit	2 skipped: 0 decoration, 2 judged decoration, 0 not judged (counted as unread)" "$(cat "$LTD/.inv/captures/c0002/meta.tsv")"
    check "a library template's captures go in the store's ledger" "c0002	read	$LTD/lib/inventory.json	4	0	2	0	" "$(cat "$LTD/.inv/llm-templates/inventory.seen.tsv")"
    # THE JUDGE (PROVOST_LLM_JUDGE, default 1): after Claude writes or extends a
    # template, one more call reviews the tables it makes of the capture and
    # answers PASS or a list of structural fixes, fed back to the writer once.
    # Here the review asks for the host on line 0 to be kept with the rows;
    # the revision (a format-2 parser) carries it down, and is kept. Before
    # the review, learn's skip audit (the same template again: the banner is
    # judged decoration).
    python3 - "$LTD" <<'PY'
import json, os, sys
d = sys.argv[1]
def msg(text):
    return {"id": "msg_j", "type": "message", "role": "assistant", "model": "claude-opus-5-5", "stop_reason": "end_turn",
            "usage": {"input_tokens": 1, "output_tokens": 1}, "content": [{"type": "text", "text": text}]}
tpl = {"format": 1, "tool": "jvol", "detect": "^NAME\\s+SIZE\\s+USED\\s+MOUNT$", "skip": ["^Volumes on host "],
       "blocks": [{"name": "volumes", "kind": "table", "header": "^NAME\\s+SIZE",
                   "line": "^(?P<name>\\S+)\\s+(?P<size>\\S+)\\s+(?P<used>\\S+)\\s+(?P<mount>/\\S*)$"}]}
fix = {"verdict": "FIX", "fixes": ["line 0 names the host the volumes are on: add a host column to the volumes, filled from it (a format-2 parser)"]}
parser = "\n".join([
    "import re", "def parse(lines):", "    host, recs, used, skip = '', [], [], []",
    "    for j, ln in enumerate(lines):",
    "        m = re.match(r'^Volumes on host (\\S+)$', ln)",
    "        if m:", "            host = m.group(1)", "            used.append(j)", "            continue",
    "        if re.match(r'^NAME\\s+SIZE', ln):", "            used.append(j)", "            continue",
    "        m = re.match(r'^(\\S+)\\s+(\\S+)\\s+(\\S+)\\s+(/\\S*)$', ln)",
    "        if m:", "            used.append(j)",
    "            recs.append({'host': host, 'name': m.group(1), 'size': m.group(2), 'used': m.group(3), 'mount': m.group(4)})",
    "    return {'blocks': [{'name': 'volumes', 'kind': 'table', 'lines': used, 'records': recs}], 'skip': skip}"])
revised = {"format": 2, "tool": "jvol", "detect": "^NAME\\s+SIZE\\s+USED\\s+MOUNT$", "parser": parser}
# a revision that reads every line (so the skip audit's check on it holds),
# each into a block of its own: fragments, which provost's gate refuses
nothing = dict(revised, parser="def parse(lines):\n    return {'blocks': [{'name': 'part%d' % j, 'kind': 'table', "
               "'lines': [j], 'records': [{'text': ln}]} for j, ln in enumerate(lines) if ln.strip()], 'skip': []}")
for name, seq in (("j-fix", [tpl, tpl, fix, revised]), ("j-nogate", [tpl, tpl, fix, nothing]), ("j-one", [tpl, tpl])):
    with open(os.path.join(d, name + ".json"), "w") as fh:
        json.dump([msg(json.dumps(x)) for x in seq], fh)
PY
    rm -f "$LTD/port" "$LTD/log"; cp "$LTD/j-fix.json" "$LTD/reply.json"
    python3 "$HERE/fake_anthropic.py" "$LTD/port" "$LTD/log" "$LTD/reply.json" & LT_PID=$!
    for _ in $(seq 1 50); do [[ -s "$LTD/port" ]] && break; sleep 0.1; done
    LT_URL="http://127.0.0.1:$(cat "$LTD/port")"
    lt_out="$(PROVOST_WORKSPACE="$LTD/.j1" PROVOST_LLM_BASE_URL="$LT_URL" PROVOST_LLM_API_KEY=k-test \
        "$PROVOST" --sync --llm --name jvol "$LTD/vol.txt" 2>&1)"
    check "the judge's fixes go back once: template, skip audit, review, revision" "4" "$(wc -l < "$LTD/log" | tr -d ' ')"
    check "the review is sent the tables the template makes" "Table 1: volumes (table, 3 rows, read from lines 1-4)" "$(sed -n 3p "$LTD/log")"
    check "the revision is asked with the fixes" "1. line 0 names the host" "$(sed -n 4p "$LTD/log")"
    check "the ok line says the template was revised" "(llm-templates/jvol.json), revised after a review asked for 1 fix" "$lt_out"
    check "the revision is what is filed" "alpha	backup	2T	1.5T	/srv/backup" "$(cat "$LTD/.j1/datasets/jvol.tsv")"
    check "the stored template records the review" '"applied": true' "$(cat "$LTD/.j1/llm-templates/jvol.json")"
    # a revision that fails provost's gate: the template as it was before the
    # review is filed and kept instead, and says so
    cp "$LTD/j-nogate.json" "$LTD/reply.json"
    lt_out="$(PROVOST_WORKSPACE="$LTD/.j2" PROVOST_LLM_BASE_URL="$LT_URL" PROVOST_LLM_API_KEY=k-test \
        "$PROVOST" --sync --llm --name jvol "$LTD/vol.txt" 2>&1)"
    check "a revision that fails the gate falls back to the template before the review" "but the revision fails the gate (its blocks are fragments (0 of 5 lines or rows in blocks of 3+)), so the template as it was is kept" "$lt_out"
    check "the template before the review is filed" "backup	2T	1.5T	/srv/backup" "$(cat "$LTD/.j2/datasets/jvol.tsv")"
    check "and kept, with the review not applied" '"applied": false' "$(cat "$LTD/.j2/llm-templates/jvol.json")"
    # PROVOST_LLM_JUDGE=0: no review (learn and its skip audit only)
    cp "$LTD/j-one.json" "$LTD/reply.json"; : > "$LTD/log"
    lt_out="$(PROVOST_LLM_JUDGE=0 PROVOST_WORKSPACE="$LTD/.j3" PROVOST_LLM_BASE_URL="$LT_URL" PROVOST_LLM_API_KEY=k-test \
        "$PROVOST" --sync --llm --name jvol "$LTD/vol.txt" 2>&1)"
    kill "$LT_PID" 2>/dev/null || true; wait "$LT_PID" 2>/dev/null || true
    check "PROVOST_LLM_JUDGE=0: no review call" "2" "$(wc -l < "$LTD/log" | tr -d ' ')"
    check_not "PROVOST_LLM_JUDGE=0: no verdict stored" '"judge"' "$(cat "$LTD/.j3/llm-templates/jvol.json")"
    check "PROVOST_LLM_JUDGE must be 0 or 1" "2" "$(PROVOST_LLM_JUDGE=2 rc_of "$PROVOST" --sync "$LT_SAMPLE")"
    # FORMAT 2: a template that is a small Python parser, for records that
    # span lines (ip-addr.json ships with provost), run in the sandbox
    lt_out="$(PROVOST_WORKSPACE="$LTWS" "$PROVOST" --sync --llm "$HERE/../extract/samples/llm-template/nested.txt" 2>&1)"
    check "a shipped parser template reads multi-line records" "read by template ip-addr.json" "$lt_out"
    check "the parser's blocks are the capture's datasets" "ip-addr.addresses" "$lt_out"
    check "a record is built from several lines" "enp3s0	inet	10.20.30.7/24	global	85211sec	85211sec	10.20.30.255	dynamic,noprefixroute" "$(cat "$LTWS/datasets/ip-addr.addresses.tsv")"
    check "a parser that reaches outside the box is refused" "imports os" "$(printf '{"format": 2, "tool": "x", "detect": "^a", "parser": "import os\\ndef parse(l): return []"}' > "$LTD/bad.json"; python3 "$HERE/../extract/llm/template.py" apply "$LTD/bad.json" "$LTD/vol.txt" 2>&1)"
    # PV-010: the fragments rule sizes a block by its lines OR its rows. A
    # ServerQuery client list is one line holding six clients: a block of one
    # line and six rows is no fragment, so the template files it.
    R4="$HERE/benchmark/round4"; LTL="$LTD/lib"; mkdir -p "$LTL"
    cp "$R4/llm-templates-f2/132-teamspeak-serverquery-clientlist.json" "$LTL/teamspeak-clientlist.json"
    cp "$R4/llm-templates-f2/020-golangci-lint-linters.json" "$LTL/golangci-lint-linters.json"
    lt_out="$(PROVOST_WORKSPACE="$LTD/.frag" PROVOST_LLM_TEMPLATE_DIRS="$LTL" \
        "$PROVOST" --sync --llm --name teamspeak-clientlist "$R4/inputs/132-teamspeak-serverquery-clientlist.txt" 2>&1)"
    check "a one-line block of six records is not a fragment" "read by template teamspeak-clientlist.json" "$lt_out"
    check "each record on the one line is a row" "MusicBot | Radio" "$(cat "$LTD/.frag/datasets/teamspeak-clientlist.clients.tsv" 2>/dev/null)"
    # sizes (lines, rows) 1+6, 1+1, 4+0 and 2+(no count): 6 + 1 + 4 + 2 = 13
    # in all, the 6 and the 4 substantial
    check "a part's size is its lines or rows, whichever is more" "10 13" "$(bash -c '
        source <(sed -n "/^_AM_FRAG_MIN=/,/^}/p" "$1"); tot=0; sub=0
        _am_frag_add 1 6; _am_frag_add 1 1; _am_frag_add 4 0; _am_frag_add 2 x; echo "$sub $tot"' _ "$PROVOST")"
    # PV-010: a yaml parse is not beyond a template STORED for the tool (plain
    # `Label: text` output is valid YAML), but Claude is never asked to write
    # one over a yaml parse: a key and a dead API change nothing.
    lt_out="$(PROVOST_WORKSPACE="$LTD/.yaml" PROVOST_LLM_TEMPLATE_DIRS="$LTL" \
        "$PROVOST" --sync --llm --name golangci-lint-linters "$R4/inputs/020-golangci-lint-linters.txt" 2>&1)"
    check "a stored template betters a yaml parse of its tool" "the engine read it as yaml, coverage 98%): a template stored for this tool fits" "$lt_out"
    check "the linter's section is kept as a column" "staticcheck	enabled" "$(cat "$LTD/.yaml/datasets/golangci-lint-linters.tsv" 2>/dev/null)"
    printf 'server:\n  host: example.org\n  port: 8080\nlogging:\n  level: info\n' > "$LTD/conf.yaml"
    lt_out="$(PROVOST_WORKSPACE="$LTD/.yaml" PROVOST_LLM_BASE_URL="http://127.0.0.1:9" PROVOST_LLM_API_KEY=k-test \
        "$PROVOST" --sync --llm --name app-config "$LTD/conf.yaml" 2>&1)"
    check "a yaml document with no template is filed as yaml" "strategy yaml" "$lt_out"
    check_not "Claude is not asked to write a template over a yaml parse" "Claude" "$lt_out$(cat "$LTD/.yaml/captures/c0002/meta.tsv" 2>/dev/null)"
    # ENDPOINTS (PROVOST_LLM_API, PV-019): openai speaks Chat Completions, as
    # vLLM, llama.cpp's server and Ollama do. tests/fake_openai.py stands in
    # for one: its reply file is a list of the replies' text.
    check "PROVOST_LLM_API must be anthropic or openai" "2" "$(PROVOST_LLM_API=gopher rc_of "$PROVOST" --sync "$LT_SAMPLE")"
    check "PROVOST_LLM_OFFLINE must be 0 or 1" "2" "$(PROVOST_LLM_OFFLINE=yes rc_of "$PROVOST" --sync "$LT_SAMPLE")"
    check "openai takes a local model id (org/name:tag)" "0" "$(PROVOST_LLM_API=openai PROVOST_LLM_MODEL=org/model:q4 PROVOST_WORKSPACE="$LTD/.oaiv" rc_of "$PROVOST" --sync "$LT_SAMPLE")"
    check "anthropic does not" "2" "$(PROVOST_LLM_MODEL=org/model:q4 rc_of "$PROVOST" --sync "$LT_SAMPLE")"
    python3 - "$LTD/oai-v1.txt" "$LTD/oai-v2.txt" <<'EOP'
import json, sys
v1 = {"format": 1, "tool": "volumes", "detect": "^NAME\\s+SIZE\\s+USED\\s+MOUNT$", "skip": ["^Volumes on host "],
      "blocks": [{"name": "volumes", "kind": "table", "header": "^NAME\\s+SIZE",
                  "line": "^(?P<name>\\S+)\\s+(?P<size>[\\d.]+[KMGT]?)\\s+(?P<used>[\\d.]+[KMGT]?)\\s+(?P<mount>/\\S*)$"}]}
v2 = dict(v1, blocks=[dict(v1["blocks"][0], line="^(?P<name>\\S+)\\s+(?P<size>[\\d.]+[KMGT]?)\\s+(?P<used>[\\d.]+[KMGT]?|-)\\s+(?P<mount>/\\S*|\\[SWAP\\])$")])
open(sys.argv[1], "w").write(json.dumps(v1))
open(sys.argv[2], "w").write(json.dumps(v2))
EOP
    LT_JPASS='{"verdict": "PASS"}'
    python3 -c 'import json, sys; print(json.dumps([open(sys.argv[1]).read(), open(sys.argv[1]).read(), sys.argv[2]]))' "$LTD/oai-v1.txt" "$LT_JPASS" > "$LTD/oai.json"
    rm -f "$LTD/oport" "$LTD/olog"
    python3 "$HERE/fake_openai.py" "$LTD/oport" "$LTD/olog" "$LTD/oai.json" & LT_PID=$!
    for _ in $(seq 1 50); do [[ -s "$LTD/oport" ]] && break; sleep 0.1; done
    LT_OURL="http://127.0.0.1:$(cat "$LTD/oport")/v1"
    lt_out="$(PROVOST_WORKSPACE="$LTD/.oai" PROVOST_LLM_API=openai PROVOST_LLM_BASE_URL="$LT_OURL" PROVOST_LLM_API_KEY=k-local \
        ANTHROPIC_API_KEY=sk-ant-never-sent PROVOST_LLM_MODEL=org/local-model:q4 \
        "$PROVOST" --sync --llm --name volumes "$LTD/vol.txt" 2>&1)"
    check "openai: an OpenAI-compatible server writes the template" "read by a new template Claude wrote (llm-templates/volumes.json)" "$lt_out"
    check "openai: learn, its skip audit and its review, all Chat Completions" "3 3" "$(wc -l < "$LTD/olog" | tr -d ' ') $(grep -c '"path": "/v1/chat/completions"' "$LTD/olog")"
    lt_req="$(head -n 1 "$LTD/olog")"
    check "openai: a bearer key" '"authorization": "bearer k-local"' "${lt_req,,}"
    check "openai: the model id as given" '"model": "org/local-model:q4"' "$lt_req"
    check "openai: the guide is the system message" '"role": "system", "content": "' "$lt_req"
    check_not "openai: no Anthropic headers" "anthropic-version" "${lt_req,,}"
    check_not "openai: ANTHROPIC_API_KEY is never sent" "sk-ant-never-sent" "$(cat "$LTD/olog")"
    # repair through it: a new kind of line (a swap volume) extends the template
    python3 -c 'import json, sys; print(json.dumps([open(sys.argv[1]).read(), sys.argv[2]]))' "$LTD/oai-v2.txt" "$LT_JPASS" > "$LTD/oai.json"
    : > "$LTD/olog"
    lt_out="$(PROVOST_WORKSPACE="$LTD/.oai" PROVOST_LLM_API=openai PROVOST_LLM_BASE_URL="$LT_OURL" PROVOST_LLM_API_KEY=k-local \
        PROVOST_LLM_MODEL=org/local-model:q4 "$PROVOST" --sync --llm --name volumes "$LTD/vol2.txt" 2>&1)"
    check "openai: a stored template is repaired through it" "read by template volumes.json, which Claude extended for 1 unread line(s) of a kind it has not met (llm-templates/volumes.json)" "$lt_out"
    check "openai: the repair reads the new line" "swap	8G	-	[SWAP]" "$(cat "$LTD/.oai/datasets/volumes.tsv")"
    check "openai: the repair and its review, Chat Completions" "2 2" "$(wc -l < "$LTD/olog" | tr -d ' ') $(grep -c '"path": "/v1/chat/completions"' "$LTD/olog")"
    # OFFLINE MODE (PROVOST_LLM_OFFLINE=1, or the store's llm-offline file):
    # with a key and a server listening, nothing is sent; stored templates
    # are still used, and the note says offline mode stopped it
    : > "$LTD/olog"
    lt_out="$(PROVOST_WORKSPACE="$LTD/.off1" PROVOST_LLM_OFFLINE=1 PROVOST_LLM_API=openai PROVOST_LLM_BASE_URL="$LT_OURL" \
        PROVOST_LLM_API_KEY=k-local "$PROVOST" --sync --llm --name cmake-cache "$LT_IN" 2>&1)"
    check "offline: a held capture with no template is held as before" "queued in 'unsorted'" "$lt_out"
    check "offline: the held line says offline mode stopped it" "offline mode is on (PROVOST_LLM_OFFLINE=1), so nothing was sent" "$lt_out"
    check "offline: meta.tsv says so too" "offline mode is on (PROVOST_LLM_OFFLINE=1)" "$(grep '^llm_template' "$LTD/.off1/captures/c0001/meta.tsv")"
    lt_out="$(PROVOST_WORKSPACE="$LTD/.off1" PROVOST_LLM_OFFLINE=1 PROVOST_LLM_API=openai PROVOST_LLM_BASE_URL="$LT_OURL" \
        PROVOST_LLM_API_KEY=k-local "$PROVOST" --sync --llm --name volumes "$LTD/vol.txt" 2>&1)"
    check "offline: a generic parse is filed as the engine read it" "strategy aligned-columns" "$lt_out"
    check "offline: and its meta.tsv says why no template was written" "offline mode is on (PROVOST_LLM_OFFLINE=1)" "$(grep '^llm_template' "$LTD/.off1/captures/c0002/meta.tsv")"
    check "offline: nothing reached the server" "0" "$(wc -l < "$LTD/olog" | tr -d ' ')"
    # the store's own setting: no environment turns it off
    mkdir -p "$LTD/.off2/llm-templates"
    # (the template as first written, before the repair: vol2's swap line is a miss for it)
    python3 -c 'import json, sys; t = json.load(open(sys.argv[1])); t["examples"] = [open(sys.argv[2]).read().rstrip("\n")]; t["decoration"] = ["Volumes a"]; json.dump(t, open(sys.argv[3], "w"), indent=1)' \
        "$LTD/oai-v1.txt" "$LTD/vol.txt" "$LTD/.off2/llm-templates/volumes.json"
    : > "$LTD/.off2/llm-offline"
    lt_out="$(PROVOST_WORKSPACE="$LTD/.off2" PROVOST_LLM_OFFLINE=0 PROVOST_LLM_API=openai PROVOST_LLM_BASE_URL="$LT_OURL" \
        PROVOST_LLM_API_KEY=k-local "$PROVOST" --sync --llm --name volumes "$LTD/vol.txt" 2>&1)"
    check "store offline: a stored template is used" "read by template volumes.json" "$lt_out"
    lt_out="$(PROVOST_WORKSPACE="$LTD/.off2" PROVOST_LLM_OFFLINE=0 PROVOST_LLM_API=openai PROVOST_LLM_BASE_URL="$LT_OURL" \
        PROVOST_LLM_API_KEY=k-local "$PROVOST" --sync --llm --name volumes "$LTD/vol2.txt" 2>&1)"
    check "store offline: a miss is not sent to be extended, and meta.tsv says why" "offline mode is on (the store's llm-offline file), so it was not sent to Claude to be extended for 1 unread line(s)" "$(grep '^llm_template' "$LTD/.off2/captures/c0002/meta.tsv")"
    check "store offline: the setting is committed with the capture" "llm-offline" "$(git -C "$LTD/.off2" ls-files llm-offline 2>&1)"
    lt_out="$(PROVOST_WORKSPACE="$LTD/.off2" PROVOST_LLM_OFFLINE=0 PROVOST_LLM_API_KEY=k-test PROVOST_LLM_BASE_URL="$LT_OURL" \
        "$PROVOST" --sync --llm --name cmake-cache "$LT_IN" 2>&1)"
    check "store offline: PROVOST_LLM_OFFLINE=0 does not turn it off" "offline mode is on (the store's llm-offline file), so nothing was sent" "$lt_out"
    check "store offline: nothing reached the server" "0" "$(wc -l < "$LTD/olog" | tr -d ' ')"
    # and template.py itself refuses, whatever calls it
    check "offline: template.py refuses before it sends" "offline mode is on (PROVOST_LLM_OFFLINE=1): nothing was sent" "$(PROVOST_LLM_OFFLINE=1 PROVOST_LLM_API_KEY=k PROVOST_LLM_BASE_URL="$LT_OURL" python3 "$HERE/../extract/llm/template.py" learn "$LTD/vol.txt" --out "$LTD/never.json" 2>&1)"
    check "offline: and nothing reached the server" "0" "$(wc -l < "$LTD/olog" | tr -d ' ')"
    # PROVOST_LLM_ALLOW_HOSTS: a base URL on another host is refused unsent
    lt_out="$(PROVOST_WORKSPACE="$LTD/.allow" PROVOST_LLM_ALLOW_HOSTS=llm.internal PROVOST_LLM_API=openai PROVOST_LLM_BASE_URL="$LT_OURL" \
        PROVOST_LLM_API_KEY=k-local "$PROVOST" --sync --llm --name cmake-cache "$LT_IN" 2>&1)"
    check "allow-hosts: a host not listed is refused" "is not in PROVOST_LLM_ALLOW_HOSTS (llm.internal): nothing was sent" "$lt_out"
    check "allow-hosts: nothing reached the server" "0" "$(wc -l < "$LTD/olog" | tr -d ' ')"
    kill "$LT_PID" 2>/dev/null || true; wait "$LT_PID" 2>/dev/null || true
fi
fi

if _part core; then
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
fi

if _part hardening; then
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
fi

if _part core; then
# Code comes only from the install dir: engine/transform files planted in the
# data store (writable by a shared store's other members) are never run.
EH="$(mktemp -d)/evilhome"; mkdir -p "$EH/transform" "$EH/extract" "$EH/analyze"
MARK="$(mktemp -d)/pwned"
printf 'touch %q\n' "$MARK.transform" > "$EH/transform/melt.sh"
printf 'touch %q\n' "$MARK.units" > "$EH/transform/units.sh"
printf 'touch %q\n' "$MARK.extract" > "$EH/extract/provost-extract"
printf 'touch %q\n' "$MARK.analyze" > "$EH/analyze/provost-analyze"
ev_out="$(printf 'a=1, b=2\n' | env -u PROVOST_WORKSPACE PROVOST_HOME="$EH" "$PROVOST" 2>&1)"
env -u PROVOST_WORKSPACE PROVOST_HOME="$EH" "$PROVOST" stats kv-pairs >/dev/null 2>&1 || true
check "a store-planted engine/transform is never executed" "none" \
    "$(ls "$MARK".* 2>/dev/null || echo none)"
check "capture still works with the bundled engine" "dataset 'kv-pairs'" "$ev_out"
fi

if _part settings; then
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

# run honours PROVOST_MAX_INPUT like inject does (under --refuse-oversize,
# as before PV-021; the default keeps it: the oversize part).
MX="$(mktemp -d)/.max"
mx_out="$(PROVOST_WORKSPACE="$MX" PROVOST_MAX_INPUT=10 "$PROVOST" run --refuse-oversize printf 'a=0123456789abcdef\n' 2>&1 || true)"
check "run --refuse-oversize refuses output larger than PROVOST_MAX_INPUT" "too large" "$mx_out"
check "nothing is captured for oversized run output" "0" "$(find "$MX/captures" -mindepth 1 2>/dev/null | wc -l | tr -d ' ')"

# meta.tsv 'command' is shell-quoted and TSV-safe (tabs/newlines escaped).
QWS="$(mktemp -d)/.quote"
PROVOST_WORKSPACE="$QWS" "$PROVOST" run --name q printf 'k=%s, j=%s\n' 'two words' $'tab\there' >/dev/null 2>&1
qmeta="$QWS/captures/c0001/meta.tsv"
check "meta.tsv stays two columns per line with tabs in args" "0" "$(awk -F'\t' 'NF != 2' "$qmeta" | grep -c . || true)"
check "meta command keeps argument boundaries (quoted)" "'two words'" "$(cat "$qmeta")"
check "meta command escapes a tab" "\$'tab\\there'" "$(cat "$qmeta")"
check "log shows the quoted command" "'two words'" "$(PROVOST_WORKSPACE="$QWS" "$PROVOST" log 2>/dev/null)"
fi

if _part core; then
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
for v in run batch listen search source diff files prev next restore control export rm doctor verify; do
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
for v in init; do
    check "help advanced lists '$v'" "provost $v" "$help_out"
    check "'$v --help' prints its own usage to stdout" "usage: provost $v" "$("$PROVOST" "$v" --help 2>/dev/null)"
done
# A variant run (PV-027): the store core used is what the variant asked for.
case "${PROVOST_SMOKE_VARIANT:-}" in
    sha256)
        check "core@sha256: the core store is a SHA-256 repository" "sha256" "$(git -C "$WS" rev-parse --show-object-format 2>&1)"
        check "core@sha256: ...and verifies" "verify: no findings" "$("$PROVOST" verify 2>&1)"
        check "core@sha256: ...and passes store check" "git object format sha256" "$("$PROVOST" store check 2>&1)" ;;
    signed)
        check "core@signed: every capture in the core store is signed and verifies" "verify: no findings" \
            "$("$PROVOST" verify --require-signed 2>&1)"
        check_not "core@signed: ...no commit provost made there is unsigned" "N" \
            "$(git -C "$WS" -c gpg.ssh.allowedSignersFile="$PROVOST_ALLOWED_SIGNERS" log --format=%G? --grep='^capture c\|^batch:' 2>/dev/null | sort -u)" ;;
esac
fi

if _part store-formats; then
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
check "new store records format 4" "4" "$(cat "$MWS/.store_format" 2>/dev/null)"
mds="$(ls "$MWS/datasets" | head -1)"
awk -F'\t' -v OFS='\t' 'NR==1{print $0, "total_entries"; next} {print $0, 2}' "$MWS/datasets/$mds" > "$MWS/x" && mv "$MWS/x" "$MWS/datasets/$mds"
printf 'a\ttotal_entries\nx\tnot-a-count\n' > "$MWS/datasets/keep.tsv"
rm -f "$MWS/.store_format"
tgit "$MWS" add -A >/dev/null 2>&1; tgit "$MWS" commit -qm "simulate an old store" >/dev/null 2>&1
printf 'k=v\nj=w\n' | PROVOST_WORKSPACE="$MWS" "$PROVOST" --sync >/dev/null 2>&1   # the next write migrates
check_not "migration drops the record-count column" "total_entries" "$(head -1 "$MWS/datasets/$mds")"
check "migration keeps the dataset's rows" "sdb1" "$(cat "$MWS/datasets/$mds")"
check "a non-count total_entries column is kept" "total_entries" "$(head -1 "$MWS/datasets/keep.tsv")"
check "migrated store records format 4" "4" "$(cat "$MWS/.store_format" 2>/dev/null)"
check "migration is committed" "store format 4" "$(tgit "$MWS" log --format=%s)"
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
# A data column named `#` (a tool's own row number) is renamed #_2 by the melt
# rather than sit beside the store's row id under the same name (PV-011), and
# meta.tsv records it.
HWS="$(mktemp -d)/.hashcol"
printf 'name,#\nether1,0\nether2,1\n' | PROVOST_WORKSPACE="$HWS" "$PROVOST" --sync --name hash >/dev/null 2>&1
printf 'name,size\na,1\nb,2\n' | PROVOST_WORKSPACE="$HWS" "$PROVOST" --sync --name plain >/dev/null 2>&1
check "a data column named # becomes #_2 beside the row id" "#	capture	n	name	#_2" "$(head -1 "$HWS/datasets/hash.tsv")"
check "...and keeps its values" "ether2	1" "$(cat "$HWS/datasets/hash.tsv")"
check "...and meta.tsv records the rename" "renamed_columns	hash:#=#_2" "$(cat "$HWS/captures/c0001/meta.tsv")"
check_not "a capture with nothing renamed records nothing" "renamed_columns" "$(cat "$HWS/captures/c0002/meta.tsv")"
# A dataset filed before that (two columns named `#`) has its own renamed on
# the next append, so the old rows keep their values under #_2.
sed -i '1s/#_2$/#/' "$HWS/datasets/hash.tsv"
tgit "$HWS" add -A >/dev/null 2>&1; tgit "$HWS" commit -qm "simulate a pre-PV-011 dataset" >/dev/null 2>&1
printf 'name,#\nether3,2\n' | PROVOST_WORKSPACE="$HWS" "$PROVOST" --sync --name hash >/dev/null 2>&1
check "an old dataset's second # is renamed #_2 on the next append" "#	capture	n	name	#_2" "$(head -1 "$HWS/datasets/hash.tsv")"
check "...its old rows keep their values" "ether1	0" "$(cat "$HWS/datasets/hash.tsv")"
check "...and the new rows land in the same column" "ether3	2" "$(cat "$HWS/datasets/hash.tsv")"
check "...and it is all one dataset" "1" "$(ls "$HWS/datasets" | grep -c '^hash')"
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
check "the migrated format-2 store records format 4" "4" "$(cat "$CWS/.store_format")"
fi

if _part recapcol; then
# PV-015: a reconcile keeps provost's capture column (column 2) the capture id
# in every row when a capture brings a data column named `capture`, in either
# order; the data column keeps its name. A format-3 store a reconcile got
# wrong is put right from provenance.tsv by the format-4 migration.
RWS="$(mktemp -d)/.recapcol"
PROVOST_WORKSPACE="$RWS" "$PROVOST" run --name d printf 'a,b,c\n1,2,3\n' >/dev/null 2>&1
PROVOST_WORKSPACE="$RWS" "$PROVOST" run --name d printf 'capture,a,b,c\nc0001,4,5,6\n' >/dev/null 2>&1
check "a later data column named capture renames provost's to _capture" "#	_capture	n	a	b	c	capture" "$(head -1 "$RWS/datasets/d.tsv")"
check "and every row's column 2 is its own capture" "$(printf '1\tc0001\t1\t1\t2\t3\t\n2\tc0002\t1\t4\t5\t6\tc0001')" "$(tail -n +2 "$RWS/datasets/d.tsv")"
rs="$(PROVOST_WORKSPACE="$RWS" "$PROVOST" show d --capture c0002 2>&1 | sq)"
check "show --capture finds the later capture's row" "2 c0002 1 4 5 6 c0001" "$rs"
check_not "and only that row" "1 c0001 1 1 2 3" "$rs"
check_not "show --capture of the first capture leaves the later row out" "c0002" "$(PROVOST_WORKSPACE="$RWS" "$PROVOST" show d --capture c0001 2>&1)"
PROVOST_WORKSPACE="$RWS" "$PROVOST" run --name d printf 'a,b,c\n7,8,9\n' >/dev/null 2>&1
check "a third capture without the column keeps column 2 true" "3	c0003	1	7	8	9	" "$(cat "$RWS/datasets/d.tsv")"
RWS2="$(mktemp -d)/.recapcol2"
PROVOST_WORKSPACE="$RWS2" "$PROVOST" run --name d printf 'capture,a,b\nzz,1,2\n' >/dev/null 2>&1
PROVOST_WORKSPACE="$RWS2" "$PROVOST" run --name d printf 'a,b\n3,4\n' >/dev/null 2>&1
check "the mirror order files the later row's capture in column 2" "$(printf '#\t_capture\tn\tcapture\ta\tb\n1\tc0001\t1\tzz\t1\t2\n2\tc0002\t1\t\t3\t4')" "$(cat "$RWS2/datasets/d.tsv")"
check "show --capture finds it" "2 c0002 1 3 4" "$(PROVOST_WORKSPACE="$RWS2" "$PROVOST" show d --capture c0002 2>&1 | sq)"
# the two stores as a reconcile before format 4 left them
printf '#\tcapture\tn\ta\tb\tc\t_capture\n1\tc0001\t1\t1\t2\t3\t\n2\tc0001\t1\t4\t5\t6\tc0002\n' > "$RWS/datasets/d.tsv"
printf '#\t_capture\tn\tcapture\ta\tb\n1\tc0001\t1\tzz\t1\t2\n2\t\t1\tc0002\t3\t4\n' > "$RWS2/datasets/d.tsv"
sed -i '/^3\t/d' "$RWS/provenance.tsv"
printf '#\tcapture\tv\n1\tdata\tx\n' > "$RWS/datasets/odd.tsv"      # no other capture column holds the id: left alone
for w in "$RWS" "$RWS2"; do echo 3 > "$w/.store_format"; tgit "$w" add -A >/dev/null 2>&1; tgit "$w" commit -qm "simulate a format-3 store" >/dev/null 2>&1; done
PROVOST_WORKSPACE="$RWS" "$PROVOST" run --name other printf 'x,y\n1,2\n' >/dev/null 2>&1
PROVOST_WORKSPACE="$RWS2" "$PROVOST" run --name other printf 'x,y\n1,2\n' >/dev/null 2>&1
check "migration puts a wrong capture column right" "$(printf '#\t_capture\tn\ta\tb\tc\tcapture\n1\tc0001\t1\t1\t2\t3\t\n2\tc0002\t1\t4\t5\t6\tc0001')" "$(cat "$RWS/datasets/d.tsv")"
check "migration fills the mirror order's empty column 2" "$(printf '#\t_capture\tn\tcapture\ta\tb\n1\tc0001\t1\tzz\t1\t2\n2\tc0002\t1\t\t3\t4')" "$(cat "$RWS2/datasets/d.tsv")"
check "migration leaves a dataset it cannot put right" "1	data	x" "$(cat "$RWS/datasets/odd.tsv")"
check "the repaired store records format 4" "4" "$(cat "$RWS/.store_format")"
fi

if _part browse; then
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

# rm NAME purges a controlled directory's capture with both its tags, so
# 'files' no longer serves files from a capture rm reports gone (PV-016).
FP2="$(mktemp -d)/proj"; mkdir -p "$FP2"
( cd "$FP2" && PROVOST_HOME="$FH" PROVOST_WORKSPACE="" "$PROVOST" control >/dev/null 2>&1
  echo 'v = 1' > m.py
  PROVOST_HOME="$FH" PROVOST_WORKSPACE="" "$PROVOST" run --name gone printf 'a b\n1 2\n' >/dev/null 2>&1
  PROVOST_HOME="$FH" PROVOST_WORKSPACE="" "$PROVOST" run --name kept printf 'a b\n3 4\n' >/dev/null 2>&1 )
fr2 () { ( cd "$FP2" && PROVOST_HOME="$FH" PROVOST_WORKSPACE="" "$PROVOST" "$@" 2>&1 ); }
check "a controlled run keeps its files (files-c0001)" "m.py" "$(fr2 files c1)"
fr2 rm -f gone >/dev/null
check_not "rm NAME drops a purged capture's files tag" "files-c0001" "$(git -C "$FP2/.provost" tag | tr '\n' ' ')"
check "files of a capture rm purged is refused" "no such capture: c0001" "$(fr2 files c1 || true)"
check "files of a surviving capture still works" "m.py" "$(fr2 files c2)"

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

# show --tsv: the rows as stored, for a program to read (provost_data.load
# reads this way, PV-031). A store of its own: the checks above count captures.
TWS="$(mktemp -d)/.tsv"
printf 'k\tv\tw\nx\t\ty\nz\t1\t\n' | PROVOST_WORKSPACE="$TWS" "$PROVOST" --sync --name blanks >/dev/null 2>&1
printf 'k\tv\tw\nq\t2\t3\n' | PROVOST_WORKSPACE="$TWS" "$PROVOST" --sync --name blanks >/dev/null 2>&1
# Lines joined with '|' first: grep -F takes a newline in a pattern as two.
bs="$(PROVOST_WORKSPACE="$TWS" "$PROVOST" show blanks --tsv 2>&1 | tr '\n' '|')"
check "show --tsv prints the header tab-separated" $'[#\tcapture\tn\tk\tv\tw|' "[$bs"
check "a blank cell stays blank, mid-row" $'|1\tc0001\t1\tx\t\ty|' "$bs"
check "and at the end of a row" $'|2\tc0001\t2\tz\t1\t|' "$bs"
check "show --tsv --capture keeps that capture's rows" $'[#\tcapture\tn\tk\tv\tw|3\tc0002\t1\tq\t2\t3|]' \
    "[$(PROVOST_WORKSPACE="$TWS" "$PROVOST" show blanks --capture 2 --tsv 2>&1 | tr '\n' '|')]"
check "show --tsv --capture with no rows prints the header alone" $'[#\tcapture\tn\tk\tv\tw|]' \
    "[$(PROVOST_WORKSPACE="$TWS" "$PROVOST" show blanks --capture 9 --tsv 2>&1 | tr '\n' '|')]"
check "show --tsv of no such dataset is refused" "no such dataset: nope" \
    "$(PROVOST_WORKSPACE="$TWS" "$PROVOST" show nope --tsv 2>&1 || true)"
fi

if _part listen; then
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
fi

if _part batch; then
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
oout="$(PROVOST_MAX_INPUT=2000 bt batch --refuse-oversize --name ov "$BTD/web01.txt" "$BTD/big.txt"; echo "rc=$?")"
check "under --refuse-oversize an oversized input is reported" "big.txt: too large" "$oout"
check "...the rest are filed" "dataset 'ov'" "$oout"
check "...and batch exits 1" "rc=1" "$oout"
oout="$(PROVOST_MAX_INPUT=2000 bt batch --name ov2 "$BTD/web01.txt" "$BTD/big.txt"; echo "rc=$?")"
check "by default batch keeps an oversized input and files its head (PV-021)" "rc=0" "$oout"
check "...kept beside the store" "the whole of it is kept at $BTWS.artifacts/" "$oout"
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
# Two batch writers at once (PV-024): each takes the lock in turn; every
# capture is filed, ids have no gap or duplicate, rows none either.
CBWS="$(mktemp -d)/.cb"; CBD="$(mktemp -d)"
for i in $(seq 1 12); do printf 'Name,Load\nh%02d,0.%d\n' "$i" "$i" > "$CBD/h$i.txt"; done
printf 'a,b\n1,2\n' | PROVOST_WORKSPACE="$CBWS" PROVOST_ASYNC=0 "$PROVOST" --name warm >/dev/null 2>&1
( PROVOST_WORKSPACE="$CBWS" "$PROVOST" batch --name cb "$CBD"/h{1,2,3,4,5,6}.txt >/dev/null 2>&1; echo "a=$?" > "$CBD/rc.a" ) &
( PROVOST_WORKSPACE="$CBWS" "$PROVOST" batch --name cb "$CBD"/h{7,8,9,10,11,12}.txt >/dev/null 2>&1; echo "b=$?" > "$CBD/rc.b" ) &
wait
check "two concurrent batch writers both finish" "a=0 b=0" "$(cat "$CBD/rc.a") $(cat "$CBD/rc.b")"
check "...with every capture filed, ids c0001..c0013 with no gap" "$(printf 'c%04d ' $(seq 1 13))" \
    "$(ls "$CBWS/captures" | sort | tr '\n' ' ')"
check "...and every row once, no duplicate row index" "12 12" \
    "$(awk -F'\t' 'NR > 1 { n++; if (!seen[$1]++) u++ } END { print n, u }' "$CBWS/datasets/cb.tsv")"
check "...each batch its own commit" "2" "$(tgit "$CBWS" log --format=%s | grep -c '^batch: 6 capture(s)')"
check "--jobs must be a number (exit 2)" "2" "$(PROVOST_WORKSPACE="$BTWS" rc_of "$PROVOST" batch -j x "$BTD/web01.txt")"
fi

if _part units; then
# --units base (PV-032): a NAME[UNIT] column in base units beside each column
# whose unit can be read; off by default, so tidy output does not change.
UWS="$(mktemp -d)/.units"; UD="$(mktemp -d)"
up () { PROVOST_WORKSPACE="$UWS" PROVOST_ASYNC=0 "$PROVOST" "$@" 2>&1; }
printf '# OSU MPI Bandwidth Test v7.4\n# Size        Bandwidth (MB/s)\n1                         3.26\n2                         6.55\n4                        13.30\n' > "$UD/osu.txt"
up --name plain "$UD/osu.txt" >/dev/null
check "without --units the dataset is as before" "# capture n A Bandwidth_(MB/s) 1 c0001 1 1 3.26" "$(up show plain | sq | tr '\n' ' ')"
check_not "...no NAME[UNIT] column" "[B/s]" "$(up show plain)"
check_not "...no units line in meta.tsv" "units" "$(cat "$UWS/captures/c0001/meta.tsv")"
check "...and no units.tsv" "none" "$(ls "$UWS/captures/c0001/units.tsv" 2>/dev/null || echo none)"
up --units base --name osu "$UD/osu.txt" >/dev/null
check "--units base adds NAME[UNIT] right after the column" "# capture n A Bandwidth_(MB/s) Bandwidth_(MB/s)[B/s]" "$(up show osu | sq | head -1)"
check "...in base units, exactly" "1 3.26 3260000" "$(up show osu | sq)"
check "...and 13.30 MB/s is 13300000 B/s" "4 13.30 13300000" "$(up show osu | sq)"
umeta="$(cat "$UWS/captures/c0002/meta.tsv")"
check "meta.tsv records the mode" "units	base" "$umeta"
check "...and where the record is" "units_columns	units.tsv" "$umeta"
check "units.tsv records each column: dataset, column, new column, base, from, read" \
    "osu	Bandwidth_(MB/s)	Bandwidth_(MB/s)[B/s]	B/s	name	MB/s=10^6" "$(cat "$UWS/captures/c0002/units.tsv")"
check "...under a header" "dataset	column	unit_column	base	from	read" "$(head -1 "$UWS/captures/c0002/units.tsv")"
check "source still gives the input verbatim" "13.30" "$(up source c0002)"
up --units=base --name osu "$UD/osu.txt" >/dev/null
check "--units=base is the same option" "7 c0003 1 1 3.26 3260000" "$(up show osu | sq)"
up --name osu "$UD/osu.txt" >/dev/null
check "a later capture without --units joins the dataset" "10 c0004 1 1 3.26" "$(up show osu | sq)"
check_not "...its unit cells empty" "10 c0004 1 1 3.26 3260000" "$(up show osu | sq)"
check_not "...not a variant" "osu.v2" "$(up ls)"
PROVOST_UNITS=base up --name envu "$UD/osu.txt" >/dev/null
check "PROVOST_UNITS=base is the option" "Bandwidth_(MB/s)[B/s]" "$(up show envu | head -1)"
PROVOST_UNITS=base up --units off --name offu "$UD/osu.txt" >/dev/null
check_not "--units off wins over PROVOST_UNITS=base" "[B/s]" "$(up show offu)"
cp "$HERE/../extract/samples/iperf3-intervals/basic.txt" "$UD/iperf3.txt"
up run --units base -- cat "$UD/iperf3.txt" >/dev/null
ishow="$(up show cat | sq)"
check "a NAME_unit column: each row in its unit (iperf's MBytes are 2^20)" "112 MBytes 117440512" "$ishow"
check "...its Mbits/sec are 10^6 bits" "940 Mbits/sec 940000000" "$ishow"
check "...and KBytes 2^10" "412 KBytes 421888" "$ishow"
check "...as units.tsv says" "MBytes=2^20 (iperf)" "$(cat "$UWS"/captures/c0007/units.tsv)"
printf 'name,bw,io\nREAD,482MiB/s (505MB/s),28.2GiB (30.3GB)\nWRITE,344MiB/s (361MB/s),20.2GiB (21.7GB)\n' > "$UD/fio.csv"
up --units base --name fio "$UD/fio.csv" >/dev/null
fshow="$(up show fio | sq)"
check "units in the cells (fio): bw" "482MiB/s (505MB/s) 505413632" "$fshow"
check "...io, a fraction of a GiB, exactly" "28.2GiB (30.3GB) 30279519436.8" "$fshow"
printf 'host,total\nweb01,7.8Gi\n' > "$UD/free.csv"
up --units base --name freeh "$UD/free.csv" >/dev/null
check_not "a bare multiplier (Gi) is not read: no column added" "[B]" "$(up show freeh)"
check "...the mode is still recorded" "units	base" "$(cat "$UWS"/captures/c0009/meta.tsv)"
check_not "...with no record of columns" "units_columns" "$(cat "$UWS"/captures/c0009/meta.tsv)"
up --units base --min-confidence 101 "$UD/osu.txt" >/dev/null
check "a held capture stays one raw column" "# capture raw" "$(up show unsorted | sq | head -1)"
check_not "...with no units line" "units" "$(cat "$UWS"/captures/c0010/meta.tsv)"
PROVOST_WORKSPACE="$UWS" "$PROVOST" batch -q --units base --name bat "$UD/osu.txt" "$UD/osu.txt" >/dev/null 2>&1 || true
check "batch takes --units base" "Bandwidth_(MB/s)[B/s]" "$(up show bat | head -1)"
check "...a units.tsv for each capture" "2" "$(ls "$UWS"/captures/c001[12]/units.tsv 2>/dev/null | wc -l | tr -d ' ')"
check "verify is clean with units.tsv in the captures" "0" "$(PROVOST_WORKSPACE="$UWS" rc_of "$PROVOST" verify)"
check "--units with a bad mode is a usage error (exit 2)" "2" "$(PROVOST_WORKSPACE="$UWS" rc_of "$PROVOST" --units si "$UD/osu.txt")"
check "...and says what it takes" "--units must be base or off (got 'si')" "$(up --units si "$UD/osu.txt" || true)"
check "--units with no mode is a usage error (exit 2)" "2" "$(PROVOST_WORKSPACE="$UWS" rc_of "$PROVOST" run --units)"
check "PROVOST_UNITS must be off or base (exit 2)" "2" "$(PROVOST_WORKSPACE="$UWS" PROVOST_UNITS=yes rc_of "$PROVOST" ls)"
check "inject --help lists --units" "--units MODE" "$("$PROVOST" inject --help)"
check "run --help lists --units" "--units MODE" "$("$PROVOST" run --help)"
check "batch --help lists --units" "--units MODE" "$("$PROVOST" batch --help)"
check "help advanced has a UNITS section" "UNITS" "$("$PROVOST" help advanced)"
check "help advanced lists PROVOST_UNITS" "PROVOST_UNITS" "$("$PROVOST" help advanced)"
fi

if _part verify; then
# verify (PV-026): input hashes at capture, and 'provost verify'.
VWS="$(mktemp -d)/.verify"
vp () { PROVOST_WORKSPACE="$VWS" PROVOST_ASYNC=0 "$PROVOST" "$@" 2>&1; }
vrc () { PROVOST_WORKSPACE="$VWS" PROVOST_ASYNC=0 rc_of "$PROVOST" "$@"; }
vsha () { if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi | awk '{ print $1 }'; }
printf 'a,b\r\n1,2\r\n' | vp --name t >/dev/null
vmeta="$(cat "$VWS/captures/c0001/meta.tsv")"
check "a capture records the sha256 of its input as received (CRs and all)" \
    "input_sha256	$(printf 'a,b\r\n1,2\r\n' | vsha)" "$vmeta"
check "...and its size in bytes" "input_bytes	10" "$vmeta"
check "...and the sha256 of output.txt as stored" "output_sha256	$(vsha < "$VWS/captures/c0001/output.txt")" "$vmeta"
check "the commit carries the hashes as trailers" "Output-SHA256: c0001 $(vsha < "$VWS/captures/c0001/output.txt")" \
    "$(tgit "$VWS" log -1 --format=%B capture-c0001)"
vp run printf 'k v\n1 2\n' >/dev/null
printf 'x y\n1 2\n' > "$VWS/../in1"; printf 'x y\n3 4\n' > "$VWS/../in2"
vp batch --name bt "$VWS/../in1" "$VWS/../in2" >/dev/null
check "a batch commit carries every capture's trailer" "Output-SHA256: c0004" "$(tgit "$VWS" log -1 --format=%B)"
check "run records the hash too" "input_sha256	$(printf 'k v\n1 2\n' | vsha)" "$(cat "$VWS/captures/c0002/meta.tsv")"
vout="$(vp verify; echo "rc=$?")"
check "a clean store verifies (exit 0)" "rc=0" "$vout"
check "...after git fsck" "git fsck --full: clean" "$vout"
check "...with every capture's hash checked" "checked all 4 capture(s): 4 of 4 hashed matching" "$vout"
check "...and names the head commit to record" "main at $(tgit "$VWS" rev-parse HEAD)" "$vout"
check "--capture checks just those" "checked 2 capture(s)" "$(vp verify --capture 1,c0003)"
check "--capture refuses a malformed id (exit 2)" "2" "$(vrc verify --capture x1)"
check "an unknown capture is a finding (exit 1)" "1" "$(vrc verify --capture 9)"
check "verify takes no stray arguments (exit 2)" "2" "$(vrc verify extra)"
# Tampering, outside provost.
echo tampered >> "$VWS/captures/c0002/output.txt"
check "an uncommitted edit is reported" "changed outside provost and not committed" "$(vp verify)"
check "...exit 1" "1" "$(vrc verify)"
tgit "$VWS" commit -qam tamper
check "a committed edit is reported" "c0002: its output.txt was changed after it was filed" "$(vp verify)"
tgit "$VWS" reset -q --hard HEAD~1
# One byte changed, the meta.tsv made to match, the tag moved: the trailer gives it away.
printf 'k v\n1 3\n' > "$VWS/captures/c0002/output.txt"
sed "s/^output_sha256.*/output_sha256	$(vsha < "$VWS/captures/c0002/output.txt")/" "$VWS/captures/c0002/meta.tsv" > "$VWS/m" \
    && mv "$VWS/m" "$VWS/captures/c0002/meta.tsv"
tgit "$VWS" commit -qam tamper; tgit "$VWS" tag -f capture-c0002 >/dev/null
check "a rewritten output, meta.tsv and tag is caught by the commit trailer" "c0002: its meta.tsv records a hash, but its commit carries no Output-SHA256 trailer" "$(vp verify)"
tgit "$VWS" reset -q --hard HEAD~1; tgit "$VWS" tag -f capture-c0002 "$(tgit "$VWS" rev-list -1 --grep='^capture c0002' HEAD)" >/dev/null
# The stored output changed under its tag, its record untouched.
vbad="$(mktemp -d)/.vb"; cp -R "$VWS" "$vbad"
printf 'k v\n1 3\n' > "$vbad/captures/c0002/output.txt"
tgit "$vbad" commit -qam tamper; tgit "$vbad" tag -f capture-c0002 >/dev/null
check "an output that no longer matches its recorded sha256 is reported" "c0002: output.txt hashes to" \
    "$(PROVOST_WORKSPACE="$vbad" "$PROVOST" verify 2>&1)"
check "the store is back to verifying clean" "0" "$(vrc verify)"
# A missing object.
vobj="$(mktemp -d)/.vo"; cp -R "$VWS" "$vobj"
vb="$(tgit "$vobj" rev-parse capture-c0001:captures/c0001/output.txt)"
if [[ -f "$vobj/.git/objects/${vb:0:2}/${vb:2}" ]]; then rm -f "$vobj/.git/objects/${vb:0:2}/${vb:2}"
else for pk in "$vobj"/.git/objects/pack/*.pack; do mv "$pk" "$pk.x"; tgit "$vobj" unpack-objects -q < "$pk.x"; rm -f "$pk.x" "${pk%.pack}.idx"; done
     rm -f "$vobj/.git/objects/${vb:0:2}/${vb:2}"; fi
vout="$(PROVOST_WORKSPACE="$vobj" "$PROVOST" verify 2>&1; echo "rc=$?")"
check "a deleted object fails fsck" "git fsck --full reports damage" "$vout"
check "...and is reported, exit 1" "rc=1" "$vout"
# rm purges are not failures.
vp rm -f --capture c0002 >/dev/null
vout="$(vp verify; echo "rc=$?")"
check "a store with an rm-purged capture still verifies" "rc=0" "$vout"
check "...and counts the removed id" "1 capture id(s) removed by rm" "$vout"
# An id that never was in the history (a dropped commit) is a failure.
vgap="$(mktemp -d)/.vg"; cp -R "$VWS" "$vgap"
cp -R "$vgap/captures/c0004" "$vgap/captures/c0009"
tgit "$vgap" add -A; tgit "$vgap" commit -qm forged; tgit "$vgap" tag capture-c0009
vout="$(PROVOST_WORKSPACE="$vgap" "$PROVOST" verify 2>&1; echo "rc=$?")"
check "ids missing from the whole history are reported" "4 capture id(s) never appear in the store's history" "$vout"
check "...exit 1" "rc=1" "$vout"
# A store made before hashes were recorded: no hash lines, no trailers.
VOLD="$(mktemp -d)/.vold"
printf 'a,b\n1,2\n' | PROVOST_WORKSPACE="$VOLD" PROVOST_ASYNC=0 "$PROVOST" --name t >/dev/null 2>&1
grep -v 'sha256\|input_bytes' "$VOLD/captures/c0001/meta.tsv" > "$VOLD/m" && mv "$VOLD/m" "$VOLD/captures/c0001/meta.tsv"
tgit "$VOLD" add -A; tgit "$VOLD" commit -q --amend -m "capture c0001: inject csv → t (#1..1)"; tgit "$VOLD" tag -f capture-c0001 >/dev/null
vout="$(PROVOST_WORKSPACE="$VOLD" "$PROVOST" verify 2>&1; echo "rc=$?")"
check "a pre-hash capture is reported as unhashed" "1 filed before hashes were recorded" "$vout"
check "...and does not fail (exit 0)" "rc=0" "$vout"
# A restored (detached) store, and a controlled directory's files-* tags.
vp restore c0001 >/dev/null
check "a store on a restored capture verifies its main branch" "rc=0" "$(vp verify; echo "rc=$?")"
vp restore latest >/dev/null
VPROJ="$(mktemp -d)"; echo one > "$VPROJ/f.txt"
( cd "$VPROJ" && PROVOST_HOME="$(mktemp -d)" PROVOST_WORKSPACE="" "$PROVOST" control >/dev/null 2>&1
  printf 'a,b\n1,2\n' | PROVOST_ASYNC=0 PROVOST_WORKSPACE="" "$PROVOST" --name t >/dev/null 2>&1 )
check "a controlled directory's store (files-* tags off main) verifies" "rc=0" \
    "$(cd "$VPROJ" && PROVOST_WORKSPACE="" "$PROVOST" verify 2>&1; echo "rc=$?")"
check "verify --help says what it does not prove" "does NOT prove that the" "$(vp verify --help)"
check "verify outside a store is a clean error" "nothing to verify" "$(PROVOST_WORKSPACE="$(mktemp -d)/none" "$PROVOST" verify 2>&1)"
fi

if _part manifest; then
echo "== run manifest (PV-020): profiles, --manifest, check-manifest, annotate =="
MWS="$(mktemp -d)/.mws"; MD="$(mktemp -d)"
mp () { PROVOST_WORKSPACE="$MWS" "$PROVOST" "$@" 2>&1; }
printf '#%% req=REQ-12 test=stream test.version=5.10 build.commit=abc123 sut=node7\nName,Load\nx,1\n' > "$MD/full.txt"
printf '#%% test=stream test.version=5.10 build.commit=abc123 sut=node7\nName,Load\nx,2\n' > "$MD/noreq.txt"
printf 'Name,Load\nx,3\n' > "$MD/plain.txt"
out="$(mp --name full --manifest-profile default "$MD/full.txt"; echo "rc=$?")"
check_not "a full prologue passes the capture-time check" "warning" "$out"
check "...and is filed" "rc=0" "$out"
out="$(mp --name noreq --manifest-profile default "$MD/noreq.txt"; echo "rc=$?")"
check "a prologue missing req warns" "lacks required key(s): req -- filed anyway" "$out"
check "...and still files it (exit 0)" "rc=0" "$out"
out="$(mp --name noreq --strict-manifest "$MD/noreq.txt"; echo "rc=$?")"
check "--strict-manifest refuses a capture missing req" "not captured (--strict-manifest)" "$out"
check "...with exit 1" "rc=1" "$out"
check "...and files nothing" "c0002" "$(mp log | tail -n 1)"
out="$(mp --name plain "$MD/plain.txt"; echo "rc=$?")"
check_not "a capture without a prologue, with no profile asked for, says nothing new" "manifest" "$out"
check_not "...and keeps no context" "context" "$(cat "$MWS/captures/c0003/meta.tsv")"
# --manifest FILE: KEY=VALUE lines, a value with spaces, prepended as the prologue
printf '# a comment\nreq=REQ-9\ntest=hpl\ntest.version=2.3\nbuild.commit=def456\nsut=cluster a\nbuild.toolchain=gcc 13.2, "x"\n' > "$MD/m.txt"
out="$(mp --name mf --context-columns --manifest "$MD/m.txt" "$MD/plain.txt"; echo "rc=$?")"
check_not "--manifest FILE with every required key passes" "warning" "$out"
check "--manifest prepends the prologue (value quoted)" '#% build.toolchain="gcc 13.2, \"x\""' "$(cat "$MWS/captures/c0004/context.txt")"
check "a quoted value with spaces is one context column" "cluster a" "$(mp show mf)"
check "...unquoted again" 'gcc 13.2, "x"' "$(mp show mf)"
printf 'not a key value\n' > "$MD/bad.txt"
check "--manifest refuses a line that is not KEY=VALUE (exit 1)" "1" "$(PROVOST_WORKSPACE="$MWS" rc_of "$PROVOST" --manifest "$MD/bad.txt" "$MD/plain.txt")"
check "--manifest names a missing file" "no such manifest file" "$(mp --manifest "$MD/nope.txt" "$MD/plain.txt")"
check "an unknown profile is an error" "no manifest profile 'nope'" "$(mp --manifest-profile nope "$MD/plain.txt")"
printf 'req\tlater\tyes\tx\n' > "$MD/badprof.tsv"
check "a malformed profile names its line" "line 1: want KEY" "$(mp check-manifest --profile "$MD/badprof.tsv")"
# check-manifest over the store
out="$(mp check-manifest; echo "rc=$?")"
check "check-manifest: a complete capture" "c0001 complete -" "$(sq <<< "$out")"
check "check-manifest: the one missing req" "c0002 incomplete req" "$(sq <<< "$out")"
check "check-manifest: no prologue lists every required key" "c0003 incomplete req,test,test.version,build.commit,sut" "$(sq <<< "$out")"
check "check-manifest warns, exit 0, by default" "rc=0" "$out"
check "check-manifest --strict exits 1 when one is incomplete" "1" "$(PROVOST_WORKSPACE="$MWS" rc_of "$PROVOST" check-manifest --strict)"
check "check-manifest --strict exits 0 when all are complete" "0" "$(PROVOST_WORKSPACE="$MWS" rc_of "$PROVOST" check-manifest --strict c0001 mf)"
check "check-manifest NAME checks the captures that fed it" "c0002 incomplete" "$(mp check-manifest noreq | sq)"
check_not "...and only those" "c0001" "$(mp check-manifest noreq)"
check "check-manifest --profile proposal uses that profile's names" "rvtm_id" "$(mp check-manifest --profile proposal c0001)"
# a store's own profile, and PROVOST_MANIFEST_PROFILE
printf 'host\trun\tyes\tthe host\n' > "$MWS/manifest-profile.tsv"
check "the store's manifest-profile.tsv is used when none is named" "c0001 incomplete host" "$(mp check-manifest c0001 | sq)"
check "PROVOST_MANIFEST_PROFILE wins over the store's" "c0001 complete" "$(PROVOST_MANIFEST_PROFILE=default mp check-manifest c0001 | sq)"
rm -f "$MWS/manifest-profile.tsv"
# post-run keys: never at capture time; annotate adds them; --post checks them
check "check-manifest --post demands reviewer and disposition" "c0001 incomplete reviewer,disposition" "$(mp check-manifest --post c0001 | sq)"
out="$(mp annotate c0001 reviewer="Jo Smith" disposition=retest; echo "rc=$?")"
check "annotate adds post-run keys to a filed capture" "annotated (reviewer, disposition)" "$out"
check "annotate commits" "annotate c0001: reviewer, disposition" "$(tgit "$MWS" log -1 --format=%s)"
check "...without filing the capture again" "c0004" "$(mp log | tail -n 1)"
mp annotate 1 disposition=pass >/dev/null
check "annotating a key again replaces it" "1" "$(grep -c disposition "$MWS/captures/c0001/annotations.txt")"
check "...with the new value" "#% disposition=pass" "$(cat "$MWS/captures/c0001/annotations.txt")"
check "check-manifest --post sees the annotations" "c0001 complete" "$(mp check-manifest --post c0001 | sq)"
mp annotate c0002 req=REQ-12 >/dev/null
check "an annotation can supply a missing run-time key" "c0002 complete" "$(mp check-manifest c0002 | sq)"
check "source shows the annotations" 'reviewer="Jo Smith"' "$(mp source c0001)"
check "annotate refuses an unknown capture" "no such capture in the store: c0099" "$(mp annotate c0099 reviewer=x)"
check "annotate wants KEY=VALUE (exit 2)" "2" "$(PROVOST_WORKSPACE="$MWS" rc_of "$PROVOST" annotate c0001 reviewer)"
check "annotate refuses a bad key (exit 2)" "2" "$(PROVOST_WORKSPACE="$MWS" rc_of "$PROVOST" annotate c0001 '1x=y')"
# run and batch take the same options
out="$(mp run --name runm --manifest "$MD/m.txt" printf 'a,b\n1,2\n'; echo "rc=$?")"
check "run --manifest files with the manifest" "#% req=REQ-9" "$(mp source "$(mp log | tail -n 1 | awk '{print $1}')")"
out="$(mp batch --strict-manifest --name bm "$MD/full.txt" "$MD/noreq.txt"; echo "rc=$?")"
check "batch --strict-manifest skips the input missing a key" "noreq.txt: the run manifest (profile default) lacks required key(s): req" "$out"
check "...files the rest" "1 input(s)" "$out"
check "...and exits 1" "rc=1" "$out"
check "PROVOST_MANIFEST_STRICT must be 0 or 1 (exit 2)" "2" "$(PROVOST_MANIFEST_STRICT=x PROVOST_WORKSPACE="$MWS" rc_of "$PROVOST" ls)"
check "check-manifest --help" "usage: provost check-manifest" "$(mp check-manifest --help)"
fi

if _part redact; then
echo "== secrets and redaction (PV-033): the capture-time scrub, export --redact =="
RWS="$(mktemp -d)/.rws"; RD="$(mktemp -d)"
rp () { PROVOST_WORKSPACE="$RWS" XDG_CONFIG_HOME="$RD/cfg" "$PROVOST" "$@" 2>&1; }
rrc () { PROVOST_WORKSPACE="$RWS" XDG_CONFIG_HOME="$RD/cfg" rc_of "$PROVOST" "$@"; }
rsha () { if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi | awk '{ print $1 }'; }
# A fake PEM key, a bearer token and a password line: none of them is stored.
printf 'name value\nuser bob\n> Authorization: Bearer abcdefghijklmnopqrstuvwx0123\nDB_PASSWORD=hunter2x\n-----BEGIN RSA PRIVATE KEY-----\nMIIEowIBAAKCAQEAfakefakefake\nZmFrZWZha2VmYWtl\n-----END RSA PRIVATE KEY-----\nlast line\n' > "$RD/secrets.txt"
out="$(rp --name cfg "$RD/secrets.txt")"
check "a capture with secrets says what it scrubbed" "secrets scrubbed before filing: authorization=1, password=1, private-key=1" "$out"
rout="$(cat "$RWS/captures/c0001/output.txt")"
check_not "the bearer token is not stored" "abcdefghijklmnopqrstuvwx0123" "$rout"
check_not "the password is not stored" "hunter2x" "$rout"
check_not "the private key is not stored" "MIIEowIBAAKCAQEAfakefakefake" "$rout"
check_not "...nor its END line" "END RSA PRIVATE KEY" "$rout"
check "each is replaced by its kind" "DB_PASSWORD=[REDACTED:password]" "$rout"
check "...the key block by one line" "$(printf '[REDACTED:private-key]\nlast line')" "$rout"
check "...the header keeps its name" "> Authorization: [REDACTED:authorization]" "$rout"
rmeta="$(cat "$RWS/captures/c0001/meta.tsv")"
check "meta.tsv counts what was scrubbed, by kind" "redacted	authorization=1,password=1,private-key=1" "$rmeta"
check "input_sha256 is of the input as received, secrets and all" "input_sha256	$(rsha < "$RD/secrets.txt")" "$rmeta"
check "output_sha256 is of output.txt as stored" "output_sha256	$(rsha < "$RWS/captures/c0001/output.txt")" "$rmeta"
check "source shows the scrubbed input" "[REDACTED:password]" "$(rp source c0001)"
check_not "the store's history holds no secret" "hunter2x" "$(tgit "$RWS" log --all -p)"
check "a scrubbed store verifies" "rc=0" "$(rp verify; echo "rc=$?")"
# A key inside a JSON string, after another key (a cloud service account).
printf '{"type": "service_account", "private_key": "-----BEGIN PRIVATE KEY-----\\nMIIEvQIBADANBgkqhkiG9w0BAQEFAASC\\n-----END PRIVATE KEY-----\\n", "client_email": "svc@proj.example"}\n' > "$RD/sa.json"
rp --name sa "$RD/sa.json" >/dev/null
check "a private key inside a JSON string is scrubbed, the rest kept" '"private_key": "[REDACTED:private-key]\n", "client_email": "svc@proj.example"}' \
    "$(cat "$RWS/captures/c0002/output.txt")"
# run: the command line is scrubbed too.
out="$(rp run echo mysql --password=Pw0rd5x -h db1)"
check "run scrubs its command line" "command	echo mysql --password=[REDACTED:password] -h db1" "$(cat "$RWS/captures/c0003/meta.tsv")"
check_not "...in the commit message too" "Pw0rd5x" "$(tgit "$RWS" log -1 --format=%B)"
check_not "...and the output" "Pw0rd5x" "$(cat "$RWS/captures/c0003/output.txt")"
check "...and counts both" "redacted	password=2" "$(cat "$RWS/captures/c0003/meta.tsv")"
# Nothing to scrub: byte for byte as it came, a missing last newline included.
printf 'a,b\n1,2' | rp --name plain >/dev/null
check "an input with no secret records 'none'" "redacted	none" "$(cat "$RWS/captures/c0004/meta.tsv")"
check "...and is stored byte for byte" "same" "$(cmp -s <(printf 'a,b\n1,2') "$RWS/captures/c0004/output.txt" && echo same)"
printf 'k v\nx 1\ntoken=Xy12345678' | rp --name nolf >/dev/null
check "a scrubbed input keeps a missing last newline missing" "$(printf 'k v\nx 1\ntoken=[REDACTED:token]' | od -An -c)" "$(od -An -c < "$RWS/captures/c0005/output.txt")"
# Look-alikes stay.
printf 'Last password change          : Nov 01, 2026\nPassword expires              : never\npasswd:         files systemd\nPWD=/home/u\ntokens: 5\nerror: unexpected token: expected\npassword: yes\n  -W, --password           force password prompt\nnetmask 255.255.255.0 inet 10.0.0.7\n' > "$RD/alike.txt"
rp --name alike "$RD/alike.txt" >/dev/null
check "look-alikes are left alone (redacted none)" "redacted	none" "$(cat "$RWS/captures/c0006/meta.tsv")"
check "...byte for byte" "same" "$(cmp -s "$RD/alike.txt" "$RWS/captures/c0006/output.txt" && echo same)"
# --no-redact and PROVOST_REDACT.
rp --name off --no-redact "$RD/secrets.txt" >/dev/null
check "--no-redact stores the input as it comes" "hunter2x" "$(cat "$RWS/captures/c0007/output.txt")"
check "...and records 'off'" "redacted	off" "$(cat "$RWS/captures/c0007/meta.tsv")"
PROVOST_REDACT=0 PROVOST_WORKSPACE="$RWS" "$PROVOST" --name off "$RD/secrets.txt" >/dev/null 2>&1
check "PROVOST_REDACT=0 does the same" "redacted	off" "$(cat "$RWS/captures/c0008/meta.tsv")"
PROVOST_REDACT=0 PROVOST_WORKSPACE="$RWS" "$PROVOST" --name on --redact "$RD/secrets.txt" >/dev/null 2>&1
check "--redact turns it back on" "redacted	authorization=1" "$(cat "$RWS/captures/c0009/meta.tsv")"
check "PROVOST_REDACT must be 0 or 1 (exit 2)" "2" "$(PROVOST_REDACT=x PROVOST_WORKSPACE="$RWS" rc_of "$PROVOST" ls)"
check "doctor says the scrub is on" "secret scrub: on" "$(rp doctor)"
# batch, --manifest and the background path.
printf 'k,v\npassword,"x"\napi_key=Ab12345678\n' > "$RD/b1.txt"; printf 'k,v\nsecret=Zz98765432\n' > "$RD/b2.txt"
rp batch --name bt "$RD/b1.txt" "$RD/b2.txt" >/dev/null
check "batch scrubs each input" "redacted	api-key=1" "$(cat "$RWS/captures/c0010/meta.tsv")"
check "...and records each one's own" "redacted	secret=1" "$(cat "$RWS/captures/c0011/meta.tsv")"
printf 'sut=node7\ntoken=Tk0123456789\n' > "$RD/m.txt"
rp --name man --manifest "$RD/m.txt" "$RD/b2.txt" >/dev/null
check "--manifest lines are scrubbed too" "#% token=[REDACTED:token]" "$(cat "$RWS/captures/c0012/output.txt")"
check "...and counted" "redacted	secret=1,token=1" "$(cat "$RWS/captures/c0012/meta.tsv")"
printf 'k v\nx 1\npassword=AsyncPw9\n' | PROVOST_WORKSPACE="$RWS" "$PROVOST" --async --name bg >/dev/null 2>&1
for _ in $(seq 1 100); do [[ -f "$RWS/captures/c0013/meta.tsv" ]] && break; sleep 0.1; done
check "a background capture is scrubbed and records it" "redacted	password=1" "$(cat "$RWS/captures/c0013/meta.tsv" 2>/dev/null)"
check_not "...and stores no secret" "AsyncPw9" "$(cat "$RWS/captures/c0013/output.txt" 2>/dev/null)"
# The corpus: the scrub changes exactly the reviewed inputs (each a real secret).
check "the scrub changes exactly the corpus inputs in tests/corpus/scrubbed.tsv" "$(cat "$HERE/corpus/scrubbed.tsv")" \
    "$(LC_ALL=C awk -f "$HERE/../lib/provost_redact.awk" -f "$HERE/corpus/scrub-survey.awk" "$HERE"/corpus/inputs/*)"

# --- export --redact: host names and addresses pseudonymised -------------------
XWS="$(mktemp -d)/.xws"; XD="$(mktemp -d)"
xp () { PROVOST_WORKSPACE="$XWS" XDG_CONFIG_HOME="$XD/cfg" "$PROVOST" "$@" 2>&1; }
xrc () { PROVOST_WORKSPACE="$XWS" XDG_CONFIG_HOME="$XD/cfg" rc_of "$PROVOST" "$@"; }
printf 'host\taddr\tload\nweb03.example.com\t10.0.0.1\t0.5\nnode7\t10.0.0.2\t0.7\ndb1\t2001:db8::5\t0.1\nbig\t1.3.6.1.2.1\t0.2\n' | xp --name fleet >/dev/null
printf '#%% host=node7\nping web03.example.com from node7-ib0 (10.0.0.2) via 2001:0db8:0:0:0:0:0:5\nnetmask 255.255.255.0 lo 127.0.0.1 oid 1.3.6.1.2.1\nDB_PASSWORD=Lk7742kq\n' | xp --name ping --no-redact >/dev/null
xp run echo ssh node12.cluster.local uptime >/dev/null
printf 'h,v\na,1\n' | xp --name node7-df >/dev/null
xp rm -f --capture c0004 >/dev/null
printf 'h,v\nb,2\n' | xp --name web03-df >/dev/null
printf 'db1\n' > "$XD/inventory"
cat > "$XD/policy" <<'EOF'
# a fleet going to a vendor
key = keys/k1
domain = example.com
domain = *.cluster.local
host = node[0-9]+
column = host
hosts = inventory
EOF
out="$(xp export --redact "$XD/policy" "$XD/x1.bundle"; echo "rc=$?")"
check "export --redact writes a bundle" "exported a redacted copy of the store" "$out"
check "...exit 0" "rc=0" "$out"
check "...made the missing key" "made a new redaction key: $XD/keys/k1" "$out"
check "...readable by its owner only" "600" "$(stat -c %a "$XD/keys/k1" 2>/dev/null || stat -f %Lp "$XD/keys/k1")"
check "...and counts what it did" "6 host name(s), 2 IPv4 and 1 IPv6 address(es) pseudonymised; 1 secret(s) scrubbed" "$out"
XI="$XD/imp1"; xp import "$XD/x1.bundle" "$XI" >/dev/null
xi () { PROVOST_WORKSPACE="$XI" "$PROVOST" "$@" 2>&1; }
xall="$(cd "$XI" && cat datasets/*.tsv provenance.tsv captures/*/* 2>/dev/null; tgit "$XI" log --all -p --format='%an %ae%n%B')"
for leak in web03 node7 node12 db1 example.com cluster.local 10.0.0.1 10.0.0.2 2001:db8 2001:0db8 Lk7742kq; do
    check "the export holds no '$leak' anywhere in its history" "0" "$(grep -cwF -- "$leak" <<< "$xall" || true)"
done
xtri="$(xi triage)"
check "a held capture's input ('unsorted', base64) is pseudonymised too" "ping $(awk 'NR == 2 { print $1 }' <<< "$(xi show fleet | sq | awk 'NR == 2 { print $4 }')")" "$xtri"
for leak in web03 node7 Lk7742kq 10.0.0.2; do
    check "...holds no '$leak' once decoded" "0" "$(grep -cwF -- "$leak" <<< "$xtri" || true)"
done
check "the key is not in the export" "no" "$(grep -qF "$(head -n 1 "$XD/keys/k1")" <<< "$xall" && echo yes || echo no)"
fleet="$(xi show fleet | sq)"
check "a host column's values are pseudonyms" "host-" "$(awk 'NR == 2' <<< "$fleet")"
check "...and its addresses" "ip4-" "$(awk 'NR == 2' <<< "$fleet")"
check "an IPv6 address is a pseudonym" "ip6-" "$(awk 'NR == 4' <<< "$fleet")"
check "four numbers inside a longer dotted run are not an address" "1.3.6.1.2.1" "$fleet"
ping_src="$(xi source c0002)"
h7="$(awk 'NR == 3 { print $4 }' <<< "$fleet")"
check "a name is the same pseudonym in every dataset and output" "from $h7-ib0" "$ping_src"
check "...in the prologue too" "#% host=$h7" "$ping_src"
v6="$(awk 'NR == 4 { print $5 }' <<< "$fleet")"
check "2001:db8::5 and its long form are one pseudonym" "via $v6" "$ping_src"
check "netmasks and loopback stay" "netmask 255.255.255.0 lo 127.0.0.1 oid 1.3.6.1.2.1" "$ping_src"
check "secrets of a --no-redact capture are scrubbed on export" "DB_PASSWORD=[REDACTED:password]" "$ping_src"
check "the run's command is pseudonymised" "echo ssh host-" "$(cat "$XI/captures/c0003/meta.tsv")"
check "a dataset named after a host is renamed to match" "yes" "$(ls "$XI/datasets" | grep -q '^host-[0-9a-f]*-df[.]tsv$' && echo yes || echo no)"
check "...and provenance names it the same way" "$(ls "$XI/datasets" | sed -n 's/[.]tsv$//p' | grep '^host-')" "$(cat "$XI/provenance.tsv")"
xmeta="$(cat "$XI/captures/c0001/meta.tsv")"
check_not "an exported meta.tsv has no input_sha256" "input_sha256" "$xmeta"
check "...says it was pseudonymised, with the key's id" "pseudonymised	key " "$xmeta"
check "...and its output_sha256 is the exported output's" "output_sha256	$(rsha < "$XI/captures/c0001/output.txt")" "$xmeta"
check_not "no Input-SHA256 trailer is exported" "Input-SHA256" "$(tgit "$XI" log --all --format=%B)"
xv="$(xi verify; echo "rc=$?")"
check "the import verifies clean (rm'd capture and all)" "rc=0" "$xv"
check "...every hash checked" "4 of 4 hashed matching" "$xv"
# The same key gives the same pseudonyms; another key, others.
xp export --redact "$XD/policy" "$XD/x2.bundle" >/dev/null
xp import "$XD/x2.bundle" "$XD/imp2" >/dev/null
check "the same key gives the same pseudonyms" "$fleet" "$(PROVOST_WORKSPACE="$XD/imp2" "$PROVOST" show fleet 2>&1 | sq)"
sed 's|^key = keys/k1|key = keys/k2|' "$XD/policy" > "$XD/policy2"
xp export --redact "$XD/policy2" "$XD/x3.bundle" >/dev/null
xp import "$XD/x3.bundle" "$XD/imp3" >/dev/null
check_not "another key gives other pseudonyms" "$h7" "$(PROVOST_WORKSPACE="$XD/imp3" "$PROVOST" show fleet 2>&1)"
# The default key, and what is refused.
printf 'domain = example.com\n' > "$XD/p-default"
check "with no key line the key is ~/.config/provost/redact.key" "$XD/cfg/provost/redact.key" "$(xp export --redact "$XD/p-default" "$XD/x4.bundle")"
check "an existing output file is refused" "already exists" "$(xp export --redact "$XD/policy" "$XD/x1.bundle")"
printf 'colour = blue\n' > "$XD/p-bad"
check "an unknown policy key is refused" "unknown key 'colour'" "$(xp export --redact "$XD/p-bad" "$XD/x5.bundle")"
check "...exit 1" "1" "$(xrc export --redact "$XD/p-bad" "$XD/x5.bundle")"
printf 'host = node[0-9\n' > "$XD/p-re"
check "a pattern awk cannot read is refused" "not a regular expression awk can read" "$(xp export --redact "$XD/p-re" "$XD/x5.bundle")"
printf 'hosts = nowhere.txt\n' > "$XD/p-hosts"
check "a missing hosts file is refused" "no such hosts file" "$(xp export --redact "$XD/p-hosts" "$XD/x5.bundle")"
printf 'key = %s/k\n' "$XWS" > "$XD/p-in"
check "a key inside the store is refused" "is inside the store" "$(xp export --redact "$XD/p-in" "$XD/x5.bundle")"
printf 'short\n' > "$XD/kshort"; printf 'key = kshort\n' > "$XD/p-short"
check "a short key is refused" "too short" "$(xp export --redact "$XD/p-short" "$XD/x5.bundle")"
check "a missing policy is refused" "no such redaction policy" "$(xp export --redact "$XD/nope" "$XD/x5.bundle")"
check "--redact needs a policy (exit 2)" "2" "$(xrc export --redact)"
check "export --help documents --redact" "--redact POLICY" "$(xp export --help)"
# A controlled directory: its files-* tags stay behind.
XC="$(mktemp -d)"; echo 'web03.example.com' > "$XC/hosts.txt"
( cd "$XC" && PROVOST_HOME="$(mktemp -d)" PROVOST_WORKSPACE="" "$PROVOST" control >/dev/null 2>&1
  printf 'a,b\nweb03.example.com,2\n' | PROVOST_ASYNC=0 PROVOST_WORKSPACE="" "$PROVOST" --name t >/dev/null 2>&1
  PROVOST_WORKSPACE="" XDG_CONFIG_HOME="$XD/cfg" "$PROVOST" export --redact "$XD/policy" "$XD/xc.bundle" >/dev/null 2>&1 )
xp import "$XD/xc.bundle" "$XD/impc" >/dev/null
check "a controlled directory's files (files-* tags) are not exported" "" "$(tgit "$XD/impc" tag -l 'files-*')"
check "...its captures are" "capture-c0001" "$(tgit "$XD/impc" tag -l 'capture-*')"
fi

if _part wrap; then
echo "== provost-wrap, the generic harness wrapper (PV-023, docs/integrations) =="
WWS="$(mktemp -d)/.wws"; WD="$(mktemp -d)"
WRAP="$HERE/../docs/integrations/examples/provost-wrap"
# The wrapper calls $PROVOST: this checkout's.
wr () { PROVOST_WORKSPACE="$WWS" PROVOST="$PROVOST" bash "$WRAP" "$@"; }
wp () { PROVOST_WORKSPACE="$WWS" "$PROVOST" "$@" 2>&1; }
printf 'printf "size,bw\\n1,10\\n2,20\\n"; exit 3\n' > "$WD/bench.sh"
out="$(wr test=stream 'sut=node "7"' -- sh "$WD/bench.sh" 2>&1; echo "rc=$?")"
check "provost-wrap passes the command's output through" "2,20" "$out"
check "...exits with the command's own status" "rc=3" "$out"
check_not "...and says nothing of its own" "warning" "$out"
check "...files a capture, named after the command" "sh 2" "$(wp ls | sq)"
out="$(wp show sh | sq)"
check "...its KEY=VALUE words and rc as columns" "# capture test sut rc n size bw" "$out"
check "...a quoted value read back whole" 'stream node "7" 3 2 2 20' "$out"
check "...the prologue kept with the capture" '#% sut="node \"7\""' "$(wp source c0001)"
out="$(wr --name probe -- sh -c 'echo "a,b"; echo "1,2"' 2>&1; echo "rc=$?")"
check "--name names the dataset, and a success is 0" "rc=0" "$out"
check "...into that dataset" "probe 1" "$(wp ls | sq)"
check "a command with no output files nothing" "0" "$(wr true; echo "$?")"
check "...(still two captures)" "c0002" "$(wp log | tail -n 1)"
out="$(wr nosuch-command-pv023 2>&1; echo "rc=$?")"
check "a command not found exits 127" "rc=127" "$out"
check "...and files nothing" "c0002" "$(wp log | tail -n 1)"
out="$(PROVOST_WORKSPACE="$WWS" PROVOST=/nonexistent/provost bash "$WRAP" sh "$WD/bench.sh" 2>&1; echo "rc=$?")"
check "with no provost the command still runs" "2,20" "$out"
check "...the wrapper says it could not file" "could not file the output of sh (its status, 3, is kept)" "$out"
check "...and the command's status is kept" "rc=3" "$out"
check "with no command, usage (exit 2)" "2" "$(rc_of bash "$WRAP" a=b)"
check "--name with no value, usage (exit 2)" "2" "$(rc_of bash "$WRAP" --name)"
fi

if _part env; then
echo "== environment capture (PV-028): --env, the allow-list, secrets withheld =="
EWS="$(mktemp -d)/.ews"; ED="$(mktemp -d)"
ep () { PROVOST_WORKSPACE="$EWS" "$PROVOST" "$@" 2>&1; }
# the context.txt of the store's latest capture
ectx () { cat "$EWS/captures/$(ep log | tail -n 1 | awk '{print $1}')/context.txt" 2>/dev/null || true; }
printf 'Name,Load\nx,1\n' > "$ED/plain.txt"
# without --env, nothing changes, whatever the environment holds
out="$(LOADEDMODULES=gcc/13.2.0 SLURM_JOB_ID=4242 OMP_NUM_THREADS=8 ep --name plain "$ED/plain.txt"; echo "rc=$?")"
check "without --env a capture files as before" "rc=0" "$out"
check_not "...says nothing about the environment" "env" "$out"
check "...and keeps no context" "no context" "$([[ -e "$EWS/captures/c0001/context.txt" ]] && echo context || echo no context)"
check "...and stores the input as it came" "$(cat "$ED/plain.txt")" "$(cat "$EWS/captures/c0001/output.txt")"
check "--env then --no-env records nothing" "no context" "$(ep --env --no-env --name plain "$ED/plain.txt" >/dev/null; [[ -e "$EWS/captures/c0002/context.txt" ]] && echo context || echo no context)"
# --env: the fixed set, the Slurm job id under the profile's own key
out="$(LOADEDMODULES=gcc/13.2.0:openmpi/4.1.6 SLURM_JOB_ID=4242 SLURM_JOB_NODELIST='node[01-04]' \
       SLURM_CLUSTER_NAME=frontier SLURM_JOB_PARTITION=batch OMP_NUM_THREADS=8 UCX_TLS=rc,sm FOO_BAR=1 \
       ep --env --name e "$ED/plain.txt"; echo "rc=$?")"
check "--env files the capture" "rc=0" "$out"
check_not "...with no warning when nothing looks like a secret" "warning" "$out"
ctx="$(ectx)"
check "--env records the host" "#% env.host=${HOSTNAME:-$(uname -n)}" "$ctx"
check "--env records the kernel (uname -sr, quoted)" "#% env.kernel=\"$(uname -sr)\"" "$ctx"
check "--env records the architecture" "#% env.arch=$(uname -m)" "$ctx"
check "--env records the user" "#% env.user=$(id -un)" "$ctx"
if [[ -r /etc/os-release ]]; then
    check "--env records the OS release (PRETTY_NAME)" "#% env.os=\"$(. /etc/os-release; printf '%s' "$PRETTY_NAME")\"" "$ctx"
fi
check "--env records the loaded environment modules" "#% env.modules=gcc/13.2.0:openmpi/4.1.6" "$ctx"
check "--env records the Slurm job id under the default profile's sched.job" "#% sched.job=4242" "$ctx"
check_not "...and not again as env.slurm.job" "env.slurm.job" "$ctx"
check "--env records the Slurm node list" "#% env.slurm.nodes=node[01-04]" "$ctx"
check "--env records the Slurm cluster and partition" "#% env.slurm.cluster=frontier" "$ctx"
check "...partition" "#% env.slurm.partition=batch" "$ctx"
check "an allow-listed variable is recorded (default list: OMP_*)" "#% env.var.OMP_NUM_THREADS=8" "$ctx"
check "...and UCX_*" "#% env.var.UCX_TLS=rc,sm" "$ctx"
check_not "a variable not on the allow-list is absent" "FOO_BAR" "$ctx"
check_not "kernel modules only with --env=modules" "env.kernel.modules" "$ctx"
check "the data still parses as before" "Load" "$(ep show e)"
c_e="$(ep log | tail -n 1 | awk '{print $1}')"
check "input_sha256 is of the input as received, before --env's lines" "input_sha256	$(sha256sum < "$ED/plain.txt" | cut -d' ' -f1)" "$(cat "$EWS/captures/$c_e/meta.tsv")"
check "verify passes on a store with --env captures" "0" "$(PROVOST_WORKSPACE="$EWS" rc_of "$PROVOST" verify)"
# the proposal profile's name for the job id
SLURM_JOB_ID=4242 ep --env --manifest-profile proposal --name e "$ED/plain.txt" >/dev/null
check "under the proposal profile the job id is job_id" "#% job_id=4242" "$(ectx)"
check_not "...not sched.job" "sched.job" "$(ectx)"
# a key the input's own prologue or --manifest sets is theirs
printf '#%% sched.job=99 env.host=elsewhere\nName,Load\nx,2\n' > "$ED/pro.txt"
SLURM_JOB_ID=4242 ep --env --name e "$ED/pro.txt" >/dev/null
ctx="$(ectx)"
check "the input's own sched.job is kept" "#% sched.job=99" "$ctx"
check_not "...and --env's is left out" "sched.job=4242" "$ctx"
check_not "...as is its env.host" "env.host=${HOSTNAME:-$(uname -n)}" "$ctx"
check "...while the other readings are added" "#% env.arch=" "$ctx"
printf 'sched.job=77\n' > "$ED/m.txt"
SLURM_JOB_ID=4242 ep --env --manifest "$ED/m.txt" --name e "$ED/plain.txt" >/dev/null
check "a --manifest FILE's key wins over --env's" "#% sched.job=77" "$(ectx)"
check_not "...which is left out" "sched.job=4242" "$(ectx)"
# the manifest check sees what --env filled
printf 'sched.job\trun\tyes\tthe job\tslurm.job\n' > "$ED/job.tsv"
out="$(SLURM_JOB_ID=4242 ep --env --manifest-profile "$ED/job.tsv" --name e "$ED/plain.txt")"
check_not "a required key --env fills passes the capture-time check" "lacks required" "$out"
out="$(ep --env --manifest-profile "$ED/job.tsv" --name e "$ED/plain.txt")"
check "...and outside a Slurm job it is reported missing" "lacks required key(s): sched.job" "$out"
printf 'sched.job\trun\tno\tthe job\tslurm.jbo\n' > "$ED/typo.tsv"
check "a profile's env column naming no reading is a warning" "names 'slurm.jbo', which --env does not read" "$(SLURM_JOB_ID=1 ep --env --manifest-profile "$ED/typo.tsv" --name e "$ED/plain.txt")"
check "...and the reading keeps its env. name" "#% env.slurm.job=1" "$(ectx)"
# secrets: refused even when allow-listed, by value and by name
tok="ghp_$(printf 'A1b2C3d4%.0s' 1 2 3 4 5)"
out="$(NCCL_DEBUG=INFO NCCL_SOCKET_IFNAME="$tok" OMP_AUTH_TOKEN=plain ep --env --name e "$ED/plain.txt"; echo "rc=$?")"
check "an allow-listed variable holding a token is refused, with a warning" "\$NCCL_SOCKET_IFNAME not recorded: its value (github-token) looks like a secret" "$out"
check "a variable with a secret's name is refused" "\$OMP_AUTH_TOKEN not recorded: its name (secret-name)" "$out"
check "...and the capture is still filed" "rc=0" "$out"
ctx="$(ectx)"
check "the refused names are listed in env.withheld" "#% env.withheld=NCCL_SOCKET_IFNAME,OMP_AUTH_TOKEN" "$ctx"
check "...beside the variables that were recorded" "#% env.var.NCCL_DEBUG=INFO" "$ctx"
check_not "the token is nowhere in the store's files" "$tok" "$(grep -r --exclude-dir=.git -- "$tok" "$EWS" || true)"
check_not "...nor in its history" "$tok" "$(tgit "$EWS" log -p --all 2>&1)"
for v in 'Bearer abcdefghijklmnopqrstuvwxyz' 'https://jo:hunter2@example.com/x' 'AKIAABCDEFGHIJKLMNOP' \
         $'-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaC1rZXk=' 'password=hunter2' 'sk-ant-api03-abcdefghijklmnopqrstuvwxyz'; do
    check "a value like '${v%%$'\n'*}' is refused" "not recorded" "$(MPI_X="$v" ep --env --name e "$ED/plain.txt")"
done
check_not "ordinary values are not taken for secrets (GPU UUID, paths)" "warning" \
    "$(CUDA_VISIBLE_DEVICES=GPU-8a1f2c3d-4e5f-6a7b-8c9d-0e1f2a3b4c5d CUDA_HOME=/opt/nvidia/hpc_sdk/Linux_x86_64/24.5/cuda I_MPI_PIN_DOMAIN=core ep --env --name e "$ED/plain.txt")"
# the allow-list
out="$(FOO_BAR=1 FOO_BAZ=2 OMP_NUM_THREADS=8 PROVOST_ENV_VARS='FOO_*' ep --env --name e "$ED/plain.txt")"
check "PROVOST_ENV_VARS replaces the default allow-list" "#% env.var.FOO_BAR=1" "$(ectx)"
check_not "...so the default's OMP_* is not recorded" "OMP_NUM_THREADS" "$(ectx)"
OMP_NUM_THREADS=8 PROVOST_ENV_VARS= ep --env --name e "$ED/plain.txt" >/dev/null
check_not "PROVOST_ENV_VARS set empty records no variables" "env.var." "$(ectx)"
check "...but still the host" "#% env.host=" "$(ectx)"
ITS_TOKEN=x PROVOST_ENV_VARS='ITS_TOKEN, FOO_BAR' FOO_BAR=1 ep --env --name e "$ED/plain.txt" >/dev/null
check "a variable named outright is still refused when it looks like a secret" "#% env.withheld=ITS_TOKEN" "$(ectx)"
check "...and a comma separates patterns too" "#% env.var.FOO_BAR=1" "$(ectx)"
mkdir -p "$ED/cwd"; : > "$ED/cwd/OMP_file"
(cd "$ED/cwd" && OMP_NUM_THREADS=4 PROVOST_WORKSPACE="$EWS" "$PROVOST" --env --name e "$ED/plain.txt" >/dev/null 2>&1)
check "an allow-list glob is never matched against file names" "#% env.var.OMP_NUM_THREADS=4" "$(ectx)"
CUDA_X=$'one\ttwo\nthree' PROVOST_ENV_VARS='CUDA_X' ep --env --name e "$ED/plain.txt" >/dev/null
check "a value's tabs and line breaks become spaces (one prologue line)" '#% env.var.CUDA_X="one two three"' "$(ectx)"
# --env=modules, PROVOST_ENV, run and batch
mkdir -p "$ED/bin"
printf '#!/bin/sh\nprintf "Module                  Size  Used by\\nzfs 1 0\\nbridge 2 1\\naes 3 0\\n"\n' > "$ED/bin/lsmod"; chmod +x "$ED/bin/lsmod"
PATH="$ED/bin:$PATH" ep --env=modules --name e "$ED/plain.txt" >/dev/null
check "--env=modules adds the kernel modules, sorted" "#% env.kernel.modules=aes,bridge,zfs" "$(ectx)"
PROVOST_ENV=1 ep --name e "$ED/plain.txt" >/dev/null
check "PROVOST_ENV=1 is --env" "#% env.host=" "$(ectx)"
PATH="$ED/bin:$PATH" PROVOST_ENV=modules ep --name e "$ED/plain.txt" >/dev/null
check "PROVOST_ENV=modules is --env=modules" "#% env.kernel.modules=aes,bridge,zfs" "$(ectx)"
SLURM_JOB_ID=5 ep run --env --name re printf 'a,b\n1,2\n' >/dev/null
check "run --env records the environment" "#% sched.job=5" "$(ectx)"
printf 'Name,Load\nx,3\n' > "$ED/b2.txt"
out="$(SLURM_JOB_ID=6 ep batch --env --name be "$ED/plain.txt" "$ED/b2.txt"; echo "rc=$?")"
check "batch --env files every input" "rc=0" "$out"
n_be=0; for c in "$EWS"/captures/c*; do grep -q '^#% sched.job=6$' "$c/context.txt" 2>/dev/null && n_be=$((n_be + 1)); done
check "...each carrying the environment" "2" "$n_be"
out="$(ep --env --context-columns --name ecol "$ED/plain.txt"; ep show ecol)"
check "--context-columns makes the readings columns" "env.arch" "$out"
# macOS: no /etc/os-release there, so sw_vers (a stand-in uname and sw_vers)
mkdir -p "$ED/mac"
printf '#!/bin/sh\nif [ "$*" = -s ]; then echo Darwin; else exec %s "$@"; fi\n' "$(command -v uname)" > "$ED/mac/uname"
printf '#!/bin/sh\ncase "$1" in -productName) echo macOS ;; -productVersion) echo 14.5 ;; esac\n' > "$ED/mac/sw_vers"
chmod +x "$ED/mac/uname" "$ED/mac/sw_vers"
PATH="$ED/mac:$PATH" ep --env --name e "$ED/plain.txt" >/dev/null
check "on macOS the OS release comes from sw_vers" '#% env.os="macOS 14.5"' "$(ectx)"
# bad settings
check "--env=other is a usage error (exit 2)" "2" "$(PROVOST_WORKSPACE="$EWS" rc_of "$PROVOST" --env=all "$ED/plain.txt")"
check "PROVOST_ENV must be 0, 1 or modules (exit 2)" "2" "$(PROVOST_ENV=yes PROVOST_WORKSPACE="$EWS" rc_of "$PROVOST" ls)"
check "PROVOST_ENV_VARS refuses what is not a name pattern (exit 2)" "2" "$(PROVOST_ENV_VARS='OMP_*=8' PROVOST_WORKSPACE="$EWS" rc_of "$PROVOST" ls)"
check "--help names --env" "--env" "$(ep inject --help)"
fi

if _part oversize; then
# Inputs over PROVOST_MAX_INPUT kept by reference (PV-021).
OWS="$(mktemp -d)/.oversize"; OART="$OWS.artifacts"
op () { PROVOST_WORKSPACE="$OWS" PROVOST_ASYNC=0 "$PROVOST" "$@" 2>&1; }
orc () { PROVOST_WORKSPACE="$OWS" PROVOST_ASYNC=0 rc_of "$PROVOST" "$@"; }
osha () { if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi | awk '{ print $1 }'; }
ometa () { printf '<%s>' "$(awk -F'\t' -v k="$2" '$1 == k { print substr($0, length(k) + 2); exit }' "$OWS/captures/$1/meta.tsv")"; }
# <...> around a value, so a check matches all of it, or that it is empty (<>).
ov () { printf '<%s>' "$*"; }
OD="$(dirname "$OWS")"
# 12 MB against the default 10 MiB cap: a two-line table, then one 12 MB run of x
# with no newline (cut back to whole lines, only the table is parsed, so the
# check stays fast).
# (Not built with awk: mawk's gsub on a long string is quadratic.)
{ printf 'a,b\n1,2\n'; head -c 12000000 /dev/zero | tr '\0' x; } > "$OD/big.txt"
osize="$(wc -c < "$OD/big.txt" | tr -d ' ')"
bsha="$(osha < "$OD/big.txt")"
op --name small <<< $'k,v\n1,2' >/dev/null           # the store exists before the big one
check "an input within the cap makes no artifact directory" "no" "$([[ -e "$OART" ]] && echo yes || echo no)"
kb0="$(tgit "$OWS" count-objects -v | awk '$1 == "size:" || $1 == "size-pack:" { s += $2 } END { print s + 0 }')"
oout="$(op --name big "$OD/big.txt"; echo "rc=$?")"
check "a 12 MB input over a 10 MiB cap is filed, not refused" "rc=0" "$oout"
check "...and says it is truncated" "truncated: only the first 8 of the input's $osize bytes were parsed" "$oout"
check "...meta.tsv marks it truncated" "<1>" "$(ometa c0002 truncated)"
check "...records the bytes parsed" "<8>" "$(ometa c0002 parsed_bytes)"
check "...and the whole input's size" "<$osize>" "$(ometa c0002 raw_bytes)"
check "...input_sha256 is the whole input's, as received" "<$bsha>" "$(ometa c0002 input_sha256)"
check "...raw_sha256 names the kept copy" "<$bsha>" "$(ometa c0002 raw_sha256)"
check "...kept at <store>.artifacts/<sha256>" "<$OART/$bsha>" "$(ometa c0002 raw_artifact)"
check "the kept copy's sha256 matches" "$bsha" "$(osha < "$OART/$bsha")"
check "...and it is read-only (no write bit, so root's -w cannot fool it)" "<r--r--r-->" "$(ov "$(ls -l "$OART/$bsha" | cut -c2-10)")"
check "output.txt holds only the parsed head" "<8>" "$(ov "$(wc -c < "$OWS/captures/c0002/output.txt" | tr -d ' ')")"
kb1="$(tgit "$OWS" count-objects -v | awk '$1 == "size:" || $1 == "size-pack:" { s += $2 } END { print s + 0 }')"
check "git's object store did not grow by the 12 MB (KiB grown < 1024)" "<yes>" "$(ov "$( (( kb1 - kb0 < 1024 )) && echo yes || echo "no: $((kb1 - kb0)) KiB")")"
check "nothing under the store holds the big input" "<>" "$(ov "$(find "$OWS" -type f -size +1000k -print)")"
check "the dataset has the parsed rows" "a b" "$(op show big | sq)"
check "source says where the whole input is and verifies it" "raw_check: ok: the full raw input is $OART/$bsha" "$(op source c0002)"
check "...by row number too" "raw_check: ok" "$(op source 2)"
check "verify checks the kept copy" "1 truncated capture(s) whose whole input was checked" "$(op verify)"
# The same bytes piped, and run: one kept copy, shared.
cat "$OD/big.txt" | op --name big >/dev/null
check "a piped oversize input is kept the same way" "<$bsha>" "$(ometa c0003 raw_sha256)"
op run cat "$OD/big.txt" >/dev/null || true
check "run keeps an oversize output too" "<$bsha>" "$(ometa c0004 raw_sha256)"
check "...and run's command still exits as it did" "<0>" "$(ov "$(orc run cat "$OD/big.txt")")"
check "the same bytes are kept once" "<1>" "$(ov "$(find "$OART" -type f | wc -l | tr -d ' ')")"
check "nothing is left staged in the artifact directory" "<>" "$(ov "$(find "$OART" -name '.incoming.*' -print)")"
# Exactly at the cap, and one byte over it.
printf 'p,q\n' > "$OD/edge.txt"; for i in $(seq 1 30); do printf '%s,%s\n' "$i" "$((i * 7))"; done >> "$OD/edge.txt"
esize="$(wc -c < "$OD/edge.txt" | tr -d ' ')"
check "an input exactly at the cap is filed whole, as before" "rc=0" "$(PROVOST_MAX_INPUT="$esize" op --name edge "$OD/edge.txt"; echo "rc=$?")"
check "...not marked truncated" "<>" "$(ometa c0006 truncated)"
check "...with nothing kept" "<1>" "$(ov "$(find "$OART" -type f | wc -l | tr -d ' ')")"
check "one byte over the cap is kept and truncated" "<1>" "$(PROVOST_MAX_INPUT=$((esize - 1)) op --name edge "$OD/edge.txt" >/dev/null; ometa c0007 truncated)"
check "...its head cut back to the last whole line" "<$((esize - $(tail -n 1 "$OD/edge.txt" | wc -c | tr -d ' ')))>" "$(ometa c0007 parsed_bytes)"
check "...and the kept copy is the whole input" "<$(osha < "$OD/edge.txt")>" "$(ometa c0007 raw_sha256)"
# The old behaviour, behind a flag.
rout="$(PROVOST_MAX_INPUT="$((esize - 1))" op --refuse-oversize --name edge "$OD/edge.txt"; echo "rc=$?")"
check "--refuse-oversize refuses it, as before" "input too large (max $((esize - 1)) bytes; raise PROVOST_MAX_INPUT)" "$rout"
check "...exit 1" "rc=1" "$rout"
check "PROVOST_OVERSIZE=refuse too, for run" "command output too large" "$(PROVOST_OVERSIZE=refuse PROVOST_MAX_INPUT=10 op run cat "$OD/edge.txt")"
check "a bad PROVOST_OVERSIZE is refused (exit 2)" "<2>" "$(ov "$(PROVOST_OVERSIZE=maybe orc ls)")"
# The artifact directory: configurable, never inside the store.
check "PROVOST_ARTIFACT_DIR moves it" "<$OD/elsewhere/" "$(PROVOST_ARTIFACT_DIR="$OD/elsewhere" PROVOST_MAX_INPUT=40 op --name edge "$OD/edge.txt" >/dev/null; ometa c0008 raw_artifact)"
check "...one inside the store is refused" "is the store or inside it" "$(PROVOST_ARTIFACT_DIR="$OWS/art" PROVOST_MAX_INPUT=40 op --name edge "$OD/edge.txt")"
check "...and nothing was filed" "no" "$([[ -e "$OWS/art" ]] && echo yes || echo no)"
# Missing and altered.
chmod u+w "$OART/$bsha"; printf 'x' >> "$OART/$bsha"
check "source reports an altered kept copy" "raw_check: ALTERED" "$(op source c0002)"
check "...exit 1" "<1>" "$(ov "$(orc source c0002)")"
check "verify reports it" "its full raw input at $OART/$bsha hashes to" "$(op verify)"
rm -f "$OART/$bsha"
check "source reports a missing kept copy" "raw_check: MISSING" "$(op source c0002)"
check "...exit 1" "<1>" "$(ov "$(orc source c0002)")"
check "verify reports it" "c0002: its full raw input (sha256 ${bsha:0:16}…) is missing" "$(op verify)"
check "an export never carries a kept copy" "no" "$(op export "$OD/x.bundle" >/dev/null; [[ $(wc -c < "$OD/x.bundle") -gt 1000000 ]] && echo yes || echo no)"
# A controlled directory: <dir>/.provost.artifacts, left out of its files.
CD="$(mktemp -d)/ctl"; mkdir -p "$CD"; printf 'k v\n1 2\n' > "$CD/notes.txt"
( cd "$CD" && env -u PROVOST_WORKSPACE "$PROVOST" control . >/dev/null 2>&1
  env -u PROVOST_WORKSPACE PROVOST_ASYNC=0 PROVOST_MAX_INPUT=40 "$PROVOST" --name edge "$OD/edge.txt" >/dev/null 2>&1
  env -u PROVOST_WORKSPACE PROVOST_ASYNC=0 PROVOST_MAX_INPUT=40 "$PROVOST" --name edge "$OD/edge.txt" >/dev/null 2>&1 ) || true
check "a controlled directory keeps them in DIR/.provost.artifacts" "<1>" "$(ov "$(find "$CD/.provost.artifacts" -type f 2>/dev/null | wc -l | tr -d ' ')")"
check "...its files commit was made" "notes.txt" "$(tgit "$CD/.provost" ls-tree -r --name-only files-c0002 2>/dev/null)"
check_not "...without the kept copies" "artifacts" "$(tgit "$CD/.provost" ls-tree -r --name-only files-c0002 2>/dev/null)"
check "...its manifest was made" "notes.txt" "$(cat "$CD/.provost/context/manifest.tsv" 2>/dev/null)"
check_not "...without them" "artifacts" "$(cat "$CD/.provost/context/manifest.tsv" 2>/dev/null)"
check "the repository ignores a kept-input directory, so no handover bundle (git archive) carries one" \
    ".provost.artifacts/" "$(git -C "$HERE/.." check-ignore -v --no-index .provost.artifacts/x sub/.provost.artifacts/x ws.artifacts/x 2>/dev/null)"
check "...whatever its store is called" "*.artifacts/" "$(git -C "$HERE/.." check-ignore -v --no-index ws.artifacts/x 2>/dev/null)"
check "help advanced documents it" "OVERSIZE INPUTS" "$("$PROVOST" help advanced)"
check "inject --help names --refuse-oversize" "--refuse-oversize" "$("$PROVOST" inject --help)"
check "doctor says where they are kept" "kept whole, outside git, in $OART" "$(op doctor)"
fi

if _part operator; then
# The operator (PV-027): an Operator: trailer on every commit provost makes.
OWS2="$(mktemp -d)/.op"
opp () { PROVOST_WORKSPACE="$OWS2" PROVOST_ASYNC=0 "$PROVOST" "$@" 2>&1; }
printf 'a b\n1 2\n' | opp --name t >/dev/null
me="$(id -un)@$(uname -n)"
check "a capture's commit names its operator, user@host by default" "Operator: $me" "$(tgit "$OWS2" log -1 --format=%B capture-c0001)"
check "...as a trailer git reads, in the block with the hash trailers" "$me" \
    "$(tgit "$OWS2" log -1 --format='%(trailers:key=Operator,valueonly)' capture-c0001)"
check "...the hash trailers still parse beside it" "c0001" \
    "$(tgit "$OWS2" log -1 --format='%(trailers:key=Output-SHA256,valueonly)' capture-c0001)"
printf 'a b\n3 4\n' | PROVOST_OPERATOR="Jane Q. Tester (bench 4)" opp --name t >/dev/null
check "PROVOST_OPERATOR overrides it" "Operator: Jane Q. Tester (bench 4)" "$(tgit "$OWS2" log -1 --format=%B capture-c0002)"
check_not "...and the default is not also written" "Operator: $me" "$(tgit "$OWS2" log -1 --format=%B capture-c0002)"
check "the committer is still provost" "provost <provost@localhost>" "$(tgit "$OWS2" log -1 --format='%cn <%ce>' capture-c0002)"
printf 'x y\n1 2\n' > "$OWS2.i1"; printf 'x y\n3 4\n' > "$OWS2.i2"
PROVOST_OPERATOR=batcher opp batch --name bt "$OWS2.i1" "$OWS2.i2" >/dev/null
check "a batch commit names its operator once, after every capture's trailers" "batcher" \
    "$(tgit "$OWS2" log -1 --format='%(trailers:key=Operator,valueonly)')"
check "...still with both captures' hashes" "c0004" "$(tgit "$OWS2" log -1 --format='%(trailers:key=Output-SHA256,valueonly)')"
PROVOST_OPERATOR=reviewer opp annotate c0001 disposition=ok >/dev/null
check "annotate's commit names its operator" "Operator: reviewer" "$(tgit "$OWS2" log -1 --format=%B)"
PROVOST_OPERATOR=cleaner opp rm -f --capture c0003 >/dev/null
check "rm's commit names its operator" "Operator: cleaner" "$(tgit "$OWS2" log -1 --format=%B)"
check "doctor shows the operator" "operator: $me (user@host" "$(opp doctor)"
check "...and PROVOST_OPERATOR when it is set" "operator: lab-7 (PROVOST_OPERATOR)" "$(PROVOST_OPERATOR=lab-7 opp doctor)"
check "an operator with a line break is refused (exit 2)" "2" \
    "$(PROVOST_WORKSPACE="$OWS2" PROVOST_OPERATOR=$'a\nForged: x' rc_of "$PROVOST" ls)"
check "...with the reason" "cannot hold a tab, a line break" "$(PROVOST_OPERATOR=$'a\nb' opp ls)"
check "an operator over 512 characters is refused (exit 2)" "2" \
    "$(PROVOST_WORKSPACE="$OWS2" PROVOST_OPERATOR="$(printf 'x%.0s' $(seq 1 513))" rc_of "$PROVOST" ls)"
check "the store still verifies" "verify: no findings" "$(opp verify)"
# A redacted export leaves the operator behind (it names a person).
printf 'key = %s\nhost = node[0-9]+\n' "$OWS2.key" > "$OWS2.pol"
opp export --redact "$OWS2.pol" "$OWS2.x.bundle" >/dev/null
opp import "$OWS2.x.bundle" "$OWS2.ximp" >/dev/null
check_not "export --redact drops the Operator trailers" "Operator:" "$(tgit "$OWS2.ximp" log --format=%B)"
check "...and says so" "Operator trailers" "$(opp export --redact "$OWS2.pol" "$OWS2.x2.bundle")"
fi

if _part signing; then
# Signed captures (PV-027): PROVOST_SIGN=ssh with a throwaway key.
if (( GITV < 2034 )) || ! command -v ssh-keygen >/dev/null 2>&1; then
    echo "  skip signing: SSH signing needs git 2.34 or later and ssh-keygen (this is git $(git --version | awk '{ print $3 }'))"
    check "an old git is refused for PROVOST_SIGN=ssh with a clear message" "needs git 2.34 or later" \
        "$(printf 'a b\n1 2\n' | PROVOST_WORKSPACE="$(mktemp -d)/.s" PROVOST_SIGN=ssh PROVOST_ASYNC=0 "$PROVOST" --name t 2>&1)"
else
SK="$(mktemp -d)"
ssh-keygen -q -t ed25519 -N '' -C smoke -f "$SK/key" </dev/null
ssh-keygen -q -t ed25519 -N '' -C other -f "$SK/other" </dev/null
ssh-keygen -q -t ed25519 -N 'a passphrase' -C locked -f "$SK/locked" </dev/null
printf 'smoke@test %s\n' "$(cat "$SK/key.pub")" > "$SK/allowed"
printf 'other@test %s\n' "$(cat "$SK/other.pub")" > "$SK/notallowed"
SWS="$(mktemp -d)/.signed"
sp () { PROVOST_WORKSPACE="$SWS" PROVOST_ASYNC=0 PROVOST_SIGN=ssh PROVOST_SIGNING_KEY="$SK/key" "$PROVOST" "$@" 2>&1; }
src () { PROVOST_WORKSPACE="$SWS" PROVOST_ASYNC=0 PROVOST_SIGN=ssh PROVOST_SIGNING_KEY="$SK/key" rc_of "$PROVOST" "$@"; }
sgit () { tgit "$SWS" -c gpg.ssh.allowedSignersFile="$SK/allowed" "$@"; }
printf 'a b\n1 2\n' | sp --name t >/dev/null
sp run printf 'k v\n1 2\n' >/dev/null
printf 'x y\n1 2\n' > "$SK/i1"; printf 'x y\n3 4\n' > "$SK/i2"
sp batch --name bt "$SK/i1" "$SK/i2" >/dev/null
sp annotate c0001 reviewer=me >/dev/null
showsig="$(sgit log --show-signature --format='%s' 2>&1)"
check "git log --show-signature: every commit is signed" "5" "$(grep -c 'Good "git" signature for smoke@test' <<< "$showsig")"
check "...the store's history is 5 commits (init, 2 captures, a batch, annotate)" "5" "$(sgit rev-list --count HEAD)"
check "...none unsigned or bad" "G" "$(sgit log --format=%G? | sort -u | tr -d '\n')"
check "every capture tag is an annotated tag" "tag tag tag tag" "$(sgit for-each-ref --format='%(objecttype)' 'refs/tags/capture-*' | tr '\n' ' ')"
vt=0; for t in c0001 c0002 c0003 c0004; do sgit verify-tag "capture-$t" >/dev/null 2>&1 || vt=$((vt + 1)); done
check "...each one signed and verifying (git verify-tag)" "0" "$vt"
check "...and its message names the capture and the operator" "Operator: " "$(sgit cat-file tag capture-c0003)"
check "commands read through the annotated tags" "x y" "$(sp source 3)"
check "verify checks them against the allowed signers" "4 of 4 capture(s) signed (commit and tag), 4 checked good" \
    "$(sp verify --allowed-signers "$SK/allowed")"
check "...--require-signed passes (exit 0)" "0" "$(src verify --require-signed --allowed-signers "$SK/allowed")"
check "...PROVOST_ALLOWED_SIGNERS does the same" "4 checked good" "$(PROVOST_ALLOWED_SIGNERS="$SK/allowed" sp verify)"
check "without an allowed-signers file they are counted, not checked" "4 not checked (no allowed-signers file" "$(sp verify)"
check "...and that is not a finding (exit 0)" "0" "$(src verify)"
check "...but is under --require-signed (exit 1)" "1" "$(src verify --require-signed)"
check "a signer not in the allowed signers is a finding" "not an allowed signer" "$(sp verify --allowed-signers "$SK/notallowed")"
check "...exit 1" "1" "$(src verify --allowed-signers "$SK/notallowed")"
check "a missing allowed-signers file is an error" "no such allowed-signers file" "$(sp verify --allowed-signers "$SK/nope")"
check "doctor says signing works" "signing: ssh with $SK/key; a test signature works" "$(sp doctor)"
check "store check counts the annotated tags" "4 capture tag(s) are annotated" "$(sp store check)"
check "...and passes" "a valid format-4 store" "$(sp store check)"
# A forced signing failure: nothing is written, exit non-zero.
head0="$(sgit rev-parse HEAD)"; ncap0="$(cat "$SWS/.next_capture_id")"
out="$(printf 'a b\n5 6\n' | PROVOST_WORKSPACE="$SWS" PROVOST_ASYNC=0 PROVOST_SIGN=ssh PROVOST_SIGNING_KEY="$SK/missing" "$PROVOST" --name t 2>&1; echo "rc=$?")"
check "a signing key that is not there fails the capture" "rc=1" "$out"
check "...saying why, and that nothing was captured" "does not exist or cannot be read. Nothing was captured" "$out"
check "...no commit was made" "$head0" "$(sgit rev-parse HEAD)"
check "...and no capture id was used" "$ncap0" "$(cat "$SWS/.next_capture_id")"
check "...nor any file written" "clean" "$(o="$(tgit "$SWS" status --porcelain)"; [[ -z "$o" ]] && echo clean || echo "$o")"
out="$(printf 'a b\n5 6\n' | PROVOST_WORKSPACE="$SWS" PROVOST_ASYNC=0 PROVOST_SIGN=ssh PROVOST_SIGNING_KEY="$SK/locked" "$PROVOST" --name t 2>&1; echo "rc=$?")"
check "a key that would ask for a passphrase is refused, not waited on" "needs a passphrase, and provost will not wait" "$out"
check "...exit 1" "rc=1" "$out"
out="$(printf 'a b\n5 6\n' | env -u SSH_AUTH_SOCK PROVOST_WORKSPACE="$SWS" PROVOST_ASYNC=0 PROVOST_SIGN=ssh PROVOST_SIGNING_KEY="$SK/locked.pub" "$PROVOST" --name t 2>&1; echo "rc=$?")"
check "...so is its .pub when no ssh-agent holds it" "$SK/locked needs a passphrase" "$out"
mkdir "$SK/pubonly"; cp "$SK/key.pub" "$SK/pubonly/"
out="$(printf 'a b\n5 6\n' | env -u SSH_AUTH_SOCK PROVOST_WORKSPACE="$SWS" PROVOST_ASYNC=0 PROVOST_SIGN=ssh PROVOST_SIGNING_KEY="$SK/pubonly/key.pub" "$PROVOST" --name t 2>&1; echo "rc=$?")"
check "a .pub key no ssh-agent holds fails the test signature" "a test signature failed" "$out"
check "...exit 1, nothing committed" "rc=1 $head0" "$(grep -o 'rc=1' <<< "$out") $(sgit rev-parse HEAD)"
check "doctor reports a key that cannot sign (exit 1)" "1" \
    "$(PROVOST_WORKSPACE="$SWS" PROVOST_SIGN=ssh PROVOST_SIGNING_KEY="$SK/missing" rc_of "$PROVOST" doctor)"
check "PROVOST_SIGN must be off, ssh or gpg (exit 2)" "2" "$(PROVOST_WORKSPACE="$SWS" PROVOST_SIGN=x509 rc_of "$PROVOST" ls)"
# The test signature passes and git's own commit signature then fails: the
# capture fails too (a stand-in ssh-keygen that signs once and then refuses).
FK="$(mktemp -d)"; real_kg="$(command -v ssh-keygen)"
cat > "$FK/ssh-keygen" <<EOF
#!/bin/sh
case " \$* " in *" -Y sign "*)
    n=\$(cat "$FK/n" 2>/dev/null || echo 0); n=\$((n + 1)); echo \$n > "$FK/n"
    [ "\$n" -gt 1 ] && { echo "stand-in: signing refused" >&2; exit 1; } ;;
esac
exec "$real_kg" "\$@"
EOF
chmod +x "$FK/ssh-keygen"
SWF="$(mktemp -d)/.sf"; cp -R "$SWS" "$SWF"; headf="$(tgit "$SWF" rev-parse HEAD)"
out="$(printf 'a b\n5 6\n' | PATH="$FK:$PATH" PROVOST_WORKSPACE="$SWF" PROVOST_ASYNC=0 PROVOST_SIGN=ssh PROVOST_SIGNING_KEY="$SK/key" "$PROVOST" --name t 2>&1; echo "rc=$?")"
check "a commit git cannot sign fails the capture" "rc=1" "$out"
check "...saying so" "could not be signed, so nothing was committed" "$out"
check "...no unsigned commit was made" "$headf" "$(tgit "$SWF" rev-parse HEAD)"
check "...and no tag" "none" "$(o="$(tgit "$SWF" tag -l 'capture-c0005')"; echo "${o:-none}")"
# Unsigned and half-signed captures.
printf 'a b\n7 8\n' | PROVOST_WORKSPACE="$SWS" PROVOST_ASYNC=0 "$PROVOST" --name t >/dev/null 2>&1
check "an unsigned capture beside signed ones is not a finding by default" "0" "$(src verify --allowed-signers "$SK/allowed")"
check "...it is counted" "; 1 unsigned" "$(sp verify --allowed-signers "$SK/allowed")"
check "...--require-signed fails it" "c0005: not signed" "$(sp verify --require-signed --allowed-signers "$SK/allowed")"
check "...--capture narrows --require-signed" "0" "$(src verify --require-signed --allowed-signers "$SK/allowed" --capture 1,2)"
SWT="$(mktemp -d)/.st"; cp -R "$SWS" "$SWT"
tgit "$SWT" tag -f capture-c0002 "capture-c0002^{commit}" >/dev/null
check "a signed capture re-tagged by hand is always a finding" "c0002: its tag is not signed, though its commit is" \
    "$(PROVOST_WORKSPACE="$SWT" "$PROVOST" verify 2>&1)"
# gpg too, where gpg is installed (a throwaway keyring).
if command -v gpg >/dev/null 2>&1 && GH="$(mktemp -d /tmp/pvg.XXXXXX)" \
   && GNUPGHOME="$GH" gpg --batch --passphrase '' --quick-gen-key 'provost smoke <smoke@test>' ed25519 sign never >/dev/null 2>&1; then
    fpr="$(GNUPGHOME="$GH" gpg --batch --with-colons --list-secret-keys 2>/dev/null | awk -F: '$1 == "fpr" { print $10; exit }')"
    GWS="$(mktemp -d)/.g"
    printf 'a b\n1 2\n' | GNUPGHOME="$GH" PROVOST_WORKSPACE="$GWS" PROVOST_ASYNC=0 PROVOST_SIGN=gpg PROVOST_SIGNING_KEY="$fpr" "$PROVOST" --name t >/dev/null 2>&1
    check "PROVOST_SIGN=gpg signs with an OpenPGP key" "G" "$(GNUPGHOME="$GH" tgit "$GWS" log --format=%G? | sort -u | tr -d '\n')"
    check "...and verify checks it against the keyring" "1 checked good" "$(GNUPGHOME="$GH" PROVOST_WORKSPACE="$GWS" "$PROVOST" verify --require-signed 2>&1)"
    GNUPGHOME="$GH" gpgconf --kill gpg-agent >/dev/null 2>&1 || true; rm -rf "$GH"
else
    echo "  skip PROVOST_SIGN=gpg: no gpg here"
fi
fi
fi

if _part objfmt; then
# SHA-256 stores (PV-027): provost init --object-format, PROVOST_OBJECT_FORMAT.
HWS="$(mktemp -d)/.h"
hp () { PROVOST_WORKSPACE="$HWS" PROVOST_ASYNC=0 "$PROVOST" "$@" 2>&1; }
hrc () { PROVOST_WORKSPACE="$HWS" PROVOST_ASYNC=0 rc_of "$PROVOST" "$@"; }
check "init refuses an object format it does not know (exit 2)" "2" "$(hrc init --object-format md5)"
check "PROVOST_OBJECT_FORMAT is checked too (exit 2)" "2" "$(PROVOST_WORKSPACE="$HWS" PROVOST_OBJECT_FORMAT=sha512 rc_of "$PROVOST" ls)"
D1="$(mktemp -d)/.d1"
check "init makes a sha1 store by default" "object format sha1" "$(PROVOST_WORKSPACE="$D1" "$PROVOST" init 2>&1)"
check "doctor shows a store's object format" "object format: sha1" "$(PROVOST_WORKSPACE="$D1" "$PROVOST" doctor 2>&1)"
check "store check shows it" "git object format sha1" "$(PROVOST_WORKSPACE="$D1" "$PROVOST" store check 2>&1)"
if (( GITV < 2029 )); then
    echo "  skip SHA-256 stores: git $(git --version | awk '{ print $3 }') cannot make one (2.29 or later can)"
    check "an old git is refused with a clear message" "needs git 2.29 or later" "$(hp init --object-format sha256)"
else
check "init --object-format sha256 makes a SHA-256 store" "object format sha256" "$(hp init --object-format sha256)"
check "...it is one" "sha256" "$(git -C "$HWS" rev-parse --show-object-format)"
check "doctor shows it" "object format: sha256" "$(hp doctor)"
check "init again is a no-op" "already exists (object format sha256); nothing to do" "$(hp init)"
check "init will not convert it (exit 1)" "1" "$(hrc init --object-format sha1)"
check "...and says so" "does not convert a store" "$(hp init --object-format=sha1)"
printf 'a b\n1 2\n' | hp --name t >/dev/null
hp run printf 'k v\n1 2\n' >/dev/null
check "a capture into it verifies" "verify: no findings" "$(hp verify)"
check "store check passes it" "git object format sha256" "$(hp store check)"
hp export "$HWS.bundle" >/dev/null
hp import "$HWS.bundle" "$HWS.imp" >/dev/null
check "export and import keep the object format" "sha256" "$(git -C "$HWS.imp" rev-parse --show-object-format)"
check "...and the import verifies" "verify: no findings" "$(PROVOST_WORKSPACE="$HWS.imp" "$PROVOST" verify 2>&1)"
printf 'key = %s\nhost = node[0-9]+\n' "$HWS.key" > "$HWS.pol"
hp export --redact "$HWS.pol" "$HWS.x.bundle" >/dev/null
hp import "$HWS.x.bundle" "$HWS.ximp" >/dev/null
check "a redacted export of a SHA-256 store is SHA-256" "sha256" "$(git -C "$HWS.ximp" rev-parse --show-object-format)"
check "...and verifies" "verify: no findings" "$(PROVOST_WORKSPACE="$HWS.ximp" "$PROVOST" verify 2>&1)"
E1="$(mktemp -d)/.e1"
printf 'a b\n1 2\n' | PROVOST_WORKSPACE="$E1" PROVOST_OBJECT_FORMAT=sha256 PROVOST_ASYNC=0 "$PROVOST" --name t >/dev/null 2>&1
check "PROVOST_OBJECT_FORMAT=sha256 makes the store a first capture creates SHA-256" "sha256" "$(git -C "$E1" rev-parse --show-object-format)"
printf 'a b\n3 4\n' | PROVOST_WORKSPACE="$E1" PROVOST_OBJECT_FORMAT=sha1 PROVOST_ASYNC=0 "$PROVOST" --name t >/dev/null 2>&1
check "...and does not change one that exists" "sha256" "$(git -C "$E1" rev-parse --show-object-format)"
check "...which still verifies" "verify: no findings" "$(PROVOST_WORKSPACE="$E1" "$PROVOST" verify 2>&1)"
# Signed and SHA-256 at once.
if (( GITV >= 2034 )) && command -v ssh-keygen >/dev/null 2>&1; then
    HK="$(mktemp -d)"; ssh-keygen -q -t ed25519 -N '' -C smoke -f "$HK/key" </dev/null
    printf 'smoke@test %s\n' "$(cat "$HK/key.pub")" > "$HK/allowed"
    HS="$(mktemp -d)/.hs"
    printf 'a b\n1 2\n' | PROVOST_WORKSPACE="$HS" PROVOST_OBJECT_FORMAT=sha256 PROVOST_SIGN=ssh PROVOST_SIGNING_KEY="$HK/key" PROVOST_ASYNC=0 "$PROVOST" --name t >/dev/null 2>&1
    check "a signed SHA-256 store verifies with --require-signed" "1 checked good" \
        "$(PROVOST_WORKSPACE="$HS" "$PROVOST" verify --require-signed --allowed-signers "$HK/allowed" 2>&1)"
fi
fi
fi

if _part store-spec; then
echo "== the store format as a spec (PV-022): every older format read, nothing read changes =="
FXD="$HERE/store-fixtures"
# A store's every file, .git included, as one listing: a read must leave it
# byte for byte as it was (cksum: POSIX, so it runs on macOS too).
snapshot () { ( cd "$1" && find . -type f -exec cksum {} + | LC_ALL=C sort -k3 ); }
fx_open () { local d; d="$(mktemp -d)"; tar -C "$d" -xzf "$FXD/format$1.tar.gz"; printf '%s\n' "$d"; }
fxp () { PROVOST_WORKSPACE="$FX/store" "$PROVOST" "$@" 2>&1; }
fxrc () { local rc=0; PROVOST_WORKSPACE="$FX/store" "$PROVOST" "$@" >/dev/null 2>&1 || rc=$?; echo "<$rc>"; }
for n in 1 2 3 4; do
    FX="$(fx_open "$n")"
    check "format $n: the fixture is a store of that format" "<$n>" "<$( [[ -f "$FX/store/.store_format" ]] && cat "$FX/store/.store_format" || echo 1)>"
    before="$(snapshot "$FX")"
    ds="disks"; (( n == 1 )) && ds="aligned-columns"     # 2.0.1 named a dataset by its parser
    check "format $n: ls lists its datasets" "$ds" "$(fxp ls)"
    check "format $n: show reads a dataset" "sdb" "$(fxp show "$ds")"
    check "format $n: source N reads a row's capture" "sda" "$(fxp source 1)"
    check "format $n: source ID reads a capture" "sdd" "$(fxp source c0002)"
    check "format $n: log lists the captures" "c0006" "$(fxp log)"
    check "format $n: search finds a value" "sdh" "$(fxp search sdh)"
    check "format $n: triage decodes the held input" "~~" "$(fxp triage)"
    check "format $n: stats reads a dataset" "<0>" "$(fxrc stats "$ds")"
    check "format $n: diff compares two captures" "<0>" "$(fxrc diff c0001 c0002)"
    check "format $n: verify passes" "<0>" "$(fxrc verify)"
    check "format $n: doctor runs" "<0>" "$(fxrc doctor)"
    check "format $n: export writes a bundle" "exported store" "$(fxp export "$FX/x.bundle"; rm -f "$FX/x.bundle")"
    check "format $n: store check passes it as format $n" "a valid format-$n store" "$(fxp store check)"
    after="$(snapshot "$FX")"
    check "format $n: no read changed a byte of the store (.git included)" "<same>" \
        "<$([[ "$before" == "$after" ]] && echo same || diff <(printf '%s\n' "$before") <(printf '%s\n' "$after") | head -n 6)>"
    # and a store no one can write reads the same (not as root: root writes anyway)
    if [[ "$(id -u)" != 0 ]]; then
        chmod -R a-w "$FX"
        check "format $n, read-only: ls" "$ds" "$(fxp ls)"
        check "format $n, read-only: source" "sda" "$(fxp source 1)"
        check "format $n, read-only: verify" "<0>" "$(fxrc verify)"
        check "format $n, read-only: export" "exported store" "$(PROVOST_LOCK_TIMEOUT=1 fxp export "$(mktemp -d)/x.bundle")"
        check "format $n, read-only: store check" "<0>" "$(fxrc store check)"
        chmod -R u+w "$FX"
    fi
    # The first write migrates it to the current format, and it still checks.
    printf 'a b\n1 2\n' | PROVOST_WORKSPACE="$FX/store" "$PROVOST" --sync --name late >/dev/null 2>&1
    check "format $n: a write migrates it to format 4" "4" "$(cat "$FX/store/.store_format")"
    (( n < 4 )) && check "format $n: the migration is a commit of its own" "store format 4" "$(tgit "$FX/store" log --format=%s)"
    check "format $n: the migrated store passes store check" "a valid format-4 store" "$(fxp store check)"
    check "format $n: and verify" "<0>" "$(fxrc verify)"
    (( n == 3 )) && check "format 3: the migration puts PV-015's wrong rows right" "$(printf '8\tc0004\t1\tsdh\t500\t7\t\tsnap1')" "$(cat "$FX/store/datasets/disks.tsv")"
    (( n == 1 )) && check_not "format 1: the migration drops total_entries" "total_entries" "$(head -1 "$FX/store/datasets/aligned-columns.tsv")"
done
FX="$(fx_open 3)"
check "format 3: store check names PV-015's rows without failing them" "known fault (PV-015)" "$(fxp store check)"
FX="$(fx_open 4)"
check "format 4: a truncated capture's kept input is found beside the moved store" "1 truncated, kept input checked" "$(fxp store check)"
check "format 4: the fixture keeps the PV-021 fields" "raw_sha256" "$(cat "$FX/store/captures/c0007/meta.tsv")"

# store check: a fresh store passes; each kind of damage fails it
SC="$(mktemp -d)/.sc"
printf 'name size\nsda 5\n' | PROVOST_WORKSPACE="$SC" "$PROVOST" --sync --name d >/dev/null 2>&1
printf 'k: v\nj: w\n' | PROVOST_WORKSPACE="$SC" "$PROVOST" --sync --name kv >/dev/null 2>&1
scp () { PROVOST_WORKSPACE="$SC" "$PROVOST" store check 2>&1; }
check "store check passes a fresh store" "a valid format-4 store" "$(scp)"
check "...exit 0" "0" "$(PROVOST_WORKSPACE="$SC" rc_of "$PROVOST" store check)"
check "store check DIR checks that store" "a valid format-4 store" "$("$PROVOST" store check "$SC" 2>&1)"
check "store with no subcommand is a usage error" "2" "$(rc_of "$PROVOST" store frob)"
check "store --help prints its usage" "usage: provost store check" "$("$PROVOST" store --help)"
cp "$SC/.next_row_id" "$SC/.keep"; rm -f "$SC/.next_row_id"
check "a missing row counter fails it" ".next_row_id is missing" "$(scp)"
check "...exit 1" "1" "$(PROVOST_WORKSPACE="$SC" rc_of "$PROVOST" store check)"
echo 1 > "$SC/.next_row_id"
check "a row counter behind the rows fails it" ".next_row_id is 1, but row #" "$(scp)"
mv "$SC/.keep" "$SC/.next_row_id"
cp "$SC/.next_capture_id" "$SC/.keep"; rm -f "$SC/.next_capture_id"
check "a missing capture counter fails it" ".next_capture_id is missing" "$(scp)"
mv "$SC/.keep" "$SC/.next_capture_id"
echo x > "$SC/.store_format"
check "a bad format file fails it" ".store_format holds 'x', not a format number" "$(scp)"
echo 9 > "$SC/.store_format"
check "a format newer than this provost fails it" "store format 9 is newer than this provost knows (4)" "$(scp)"
echo 4 > "$SC/.store_format"
check "...and put back, it passes" "a valid format-4 store" "$(scp)"
cp "$SC/provenance.tsv" "$SC/.keep"; sed '$d' "$SC/.keep" > "$SC/provenance.tsv"
check "a row missing from provenance fails it" "is not in provenance.tsv" "$(scp)"
mv "$SC/.keep" "$SC/provenance.tsv"
cp "$SC/datasets/d.tsv" "$SC/.keep"; awk -F'\t' -v OFS='\t' 'NR == 2 { $2 = "c0099" } { print }' "$SC/.keep" > "$SC/datasets/d.tsv"
check "a row naming the wrong capture fails it (format 4)" "says capture \"c0099\", provenance.tsv says c0001" "$(scp)"
mv "$SC/.keep" "$SC/datasets/d.tsv"
mv "$SC/captures/c0002/meta.tsv" "$SC/.keep"
check "a capture with no meta.tsv fails it" "captures/c0002: meta.tsv is missing" "$(scp)"
mv "$SC/.keep" "$SC/captures/c0002/meta.tsv"
tgit "$SC" tag -d capture-c0001 >/dev/null 2>&1
check "a capture with no tag fails it" "there is no tag capture-c0001" "$(scp)"
check "store check changes nothing (it found the damage, it did not commit it)" "<>" "<$(tgit "$SC" status --porcelain)>"

# The format's contract, held in place: every format this provost writes has
# a migration to it, a section in the spec and a fixture of it, so bumping
# _STORE_FORMAT without them fails here (and the mutation proves it can).
format_contract () {   # PROVOST-FILE -> "ok", or what is missing
    local pf="$1" n k miss=""
    n="$(sed -n 's/^_STORE_FORMAT=\([0-9]*\)$/\1/p' "$pf")"
    [[ "$n" =~ ^[0-9]+$ ]] || { echo "no _STORE_FORMAT"; return; }
    for (( k = 2; k <= n; k++ )); do
        grep -qF "if (( \$(_store_format) < $k )); then" "$pf" || miss="$miss no-migration-to-$k"
    done
    for (( k = 1; k <= n; k++ )); do
        grep -qE "^### Format $k([^0-9]|\$)" "$HERE/../docs/store-format.md" || miss="$miss no-spec-section-$k"
        [[ -f "$FXD/format$k.tar.gz" ]] || miss="$miss no-fixture-$k"
    done
    echo "${miss:-ok}"
}
check "every store format has a migration, a spec section and a fixture" "ok" "$(format_contract "$PROVOST")"
MUT="$(mktemp -d)/provost"; sed 's/^_STORE_FORMAT=4$/_STORE_FORMAT=5/' "$PROVOST" > "$MUT"
check "mutation: _STORE_FORMAT bumped with no migration fails the contract" "no-migration-to-5" "$(format_contract "$MUT")"
check "...and no spec section or fixture" "no-spec-section-5 no-fixture-5" "$(format_contract "$MUT")"
check "the spec states the compatibility promise" "Every provost reads every older store format" "$(cat "$HERE/../docs/store-format.md")"
check "so does the README" "Every provost reads every older store format" "$(cat "$HERE/../README.md")"
check "help advanced names store check" "provost store check" "$("$PROVOST" help advanced)"

# A controlled directory's store: context/manifest.tsv and files-* tags.
CDS="$(mktemp -d)/ctl"; mkdir -p "$CDS"; printf 'k v\n1 2\n' > "$CDS/notes.txt"
( cd "$CDS" && env -u PROVOST_WORKSPACE "$PROVOST" control . >/dev/null 2>&1
  printf 'a b\n1 2\n' | env -u PROVOST_WORKSPACE "$PROVOST" --sync --name t >/dev/null 2>&1 ) || true
check "store check passes a controlled directory's store" "1 files-* tag(s)" "$("$PROVOST" store check "$CDS/.provost" 2>&1)"
fi

if [[ -z "${PROVOST_SMOKE_PART:-}" ]]; then
    # one job (PROVOST_TEST_JOBS=1): the variants, each in a process of its own
    for v in "${SMOKE_VARIANTS[@]}"; do
        vlog="$(PROVOST_SMOKE_PART="${v%@*}" PROVOST_SMOKE_VARIANT="${v#*@}" bash "${BASH_SOURCE[0]}" 2>&1 || true)"
        grep -v '^smoke: [0-9]* passed, [0-9]* failed$' <<< "$vlog" || true
        line="$(grep '^smoke: [0-9]* passed, [0-9]* failed$' <<< "$vlog" | tail -1 || true)"
        if [[ -z "$line" ]]; then echo "  FAIL part '$v' stopped early"; fail=$((fail + 1)); continue; fi
        read -r _ p _ f _ <<< "$line"; pass=$((pass + p)); fail=$((fail + f))
    done
fi
echo "smoke: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
