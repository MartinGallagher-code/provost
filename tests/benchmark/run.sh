#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Held-out generalisation benchmark.
##
## Every input under inputs/ (round 1) or round2/inputs/ (round 2) is a tool
## output the engine had NEVER been tuned against when it was added — no hint
## row, no strategy, no golden. The corpus under tests/corpus/ measures
## regression; this measures generalisation, which is a different and harsher
## question: what happens the first time provost meets an output nobody wrote a
## parser for?
##
## There is deliberately no pass/fail gate here. A gate would invite fitting
## the engine to these files, which destroys the only property that makes
## them useful. The ratings (ratings.tsv, round2/ratings.tsv) are a snapshot of
## a human-readable judgement (see docs/benchmark-2026-08-12-generalisation.md
## and docs/benchmark-2026-10-02-generalisation-round2.md); re-run this script
## and re-read the diff when you want to know whether a change helped or hurt
## inputs it was not written for.
##
## Usage:
##   bash tests/benchmark/run.sh [--round2] [-j N] [--tidy] [outdir]
##
##   --round2   run the round-2 set (round2/inputs/, 109 inputs) instead of
##              the round-1 set (inputs/, 50 inputs)
##   -j N       parallel jobs (default: CPU count; PROVOST_BENCH_JOBS)
##   --tidy     also melt the default parse to tidy TSV (NAME.tidy)
##   outdir     default: a fresh mktemp dir
##
## Writes, per input NAME:
##   NAME.def        default single-dataset extract (what `provost` does bare)
##   NAME.meta       the strategy that claimed it, and its confidence
##   NAME.prio       the same extract under --rank priority (the pre-calibration
##                   ranking: first detecting strategy in priority order wins)
##   NAME.prio.meta  ... and the strategy/confidence that won under it
##   NAME.multi      the --multi segmentation, exactly as `provost --multi`
##                   requests it (-f tsv --max-strategies 1; datasets separated
##                   by __DATASET__<TAB>n<TAB>strategy<TAB>confidence lines)
##   NAME.tidy       (--tidy only) NAME.def melted to the tidy table
##   NAME.multi.tidy (--tidy only) each --multi dataset melted, under its banner
################################################################################
set -uo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
root=$(cd -- "$here/../.." && pwd)
engine="$root/extract/provost-extract"

set_dir="$here/inputs"
jobs="${PROVOST_BENCH_JOBS:-$(nproc 2>/dev/null || echo 2)}"
tidy=0
outdir=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --round2) set_dir="$here/round2/inputs"; shift ;;
        -j) jobs="${2:?-j needs a number}"; shift 2 ;;
        -j*) jobs="${1#-j}"; shift ;;
        --tidy) tidy=1; shift ;;
        -h|--help) sed -n '/^## Usage:/,/^####/p' "${BASH_SOURCE[0]}" | sed 's/^## \{0,1\}//'; exit 0 ;;
        -*) echo "run.sh: unknown option: $1" >&2; exit 2 ;;
        *) outdir="$1"; shift ;;
    esac
done
outdir="${outdir:-$(mktemp -d)}"
mkdir -p "$outdir"

inputs=()
while IFS= read -r -d '' f; do inputs+=("$f"); done \
    < <(find "$set_dir" -maxdepth 1 -name '*.txt' -print0 | sort -z)

# Single-dataset modes go through the engine's batch fast path: one engine
# process per job slot handles a whole chunk of inputs (`--batch --batch-out`
# writes NAME.wide + NAME.meta), so the strategy tree is sourced JOBS times
# per mode instead of once per input. Output is byte-identical to a per-input
# `provost-extract ... <FILE` call.
_batch () {   # _batch SUBDIR ENGINE-ARGS...
    local sub="$outdir/.$1" c i; shift
    mkdir -p "$sub"
    for ((c = 0; c < jobs; c++)); do
        for ((i = c; i < ${#inputs[@]}; i += jobs)); do
            printf '%s\n' "${inputs[$i]}"
        done | "$engine" --batch --batch-out "$sub" "$@" 2>/dev/null &
    done
    wait
}
_batch def  -f plain --max-strategies 1
_batch prio -f plain --max-strategies 1 --rank priority
[[ "$tidy" == 1 ]] && _batch tsv -f tsv --max-strategies 1
# The batch path skips a file it believes is binary, and its test (file size
# minus the bytes `$(<file)` returns, > 2) also fires on plain text that ends in
# three or more newlines (lib/_dispatch.sh, batch loop). Redo any input the
# batch left without output the per-input way, so every input is measured.
_redo () {   # _redo SUBDIR FILE ENGINE-ARGS...
    local sub="$outdir/.$1" f="$2" n; shift 2
    n=$(basename "$f" .txt)
    [[ -e "$sub/$n.meta" ]] && return
    "$engine" "$@" --emit-meta <"$f" >"$sub/$n.wide" 2>"$sub/$n.meta"
}
for f in "${inputs[@]}"; do
    _redo def  "$f" -f plain --max-strategies 1
    _redo prio "$f" -f plain --max-strategies 1 --rank priority
    [[ "$tidy" == 1 ]] && _redo tsv "$f" -f tsv --max-strategies 1
done
for f in "${inputs[@]}"; do
    n=$(basename "$f" .txt)
    for pair in "def/$n.wide:$n.def" "def/$n.meta:$n.meta" \
                "prio/$n.wide:$n.prio" "prio/$n.meta:$n.prio.meta"; do
        src="$outdir/.${pair%%:*}" dst="$outdir/${pair#*:}"
        if [[ -e "$src" ]]; then mv -f "$src" "$dst"; else : >"$dst"; fi
    done
done
if [[ "$tidy" == 1 ]]; then
    # melt.sh sourced once, called in-process per input.
    ( # shellcheck source=/dev/null
      source "$root/transform/melt.sh"
      for f in "${inputs[@]}"; do
          n=$(basename "$f" .txt)
          _core_melt_tidy_file "$outdir/.tsv/$n.wide" >"$outdir/$n.tidy" 2>/dev/null
      done )
fi
rm -rf "$outdir/.def" "$outdir/.prio" "$outdir/.tsv"

# --multi has no batch path; run it per input in a job pool. Same flags as
# `provost --multi` uses (provost:776): tsv, one strategy per dataset.
printf '%s\0' "${inputs[@]}" \
    | xargs -0 -n 1 -P "$jobs" sh -c \
        'n=$(basename "$2" .txt); "$0" --multi -f tsv --max-strategies 1 <"$2" >"$1/$n.multi" 2>/dev/null' \
        "$engine" "$outdir"
if [[ "$tidy" == 1 ]]; then
    # Melt each --multi dataset separately; keep the __DATASET__ banners.
    ( # shellcheck source=/dev/null
      source "$root/transform/melt.sh"
      for f in "${inputs[@]}"; do
          n=$(basename "$f" .txt)
          rm -f "$outdir/.ds".*
          awk -v pre="$outdir/.ds" '
              /^__DATASET__\t/ { k++; print > (pre "." k ".hdr"); next }
              k { print > (pre "." k ".tsv") }' "$outdir/$n.multi"
          : >"$outdir/$n.multi.tidy"
          for ((k = 1; ; k++)); do
              h="$outdir/.ds.$k.hdr"
              [[ -e "$h" ]] || break
              cat "$h" >>"$outdir/$n.multi.tidy"
              [[ -e "${h%.hdr}.tsv" ]] && _core_melt_tidy_file "${h%.hdr}.tsv" \
                  >>"$outdir/$n.multi.tidy" 2>/dev/null
          done
          rm -f "$outdir/.ds".*
      done )
fi

printf 'benchmark outputs: %s\n' "$outdir"

# Summary line per input: how the engine read it, and how big the parse came
# out relative to the input. A parse much SHORTER than its input is the
# signature of silent truncation, which is the failure mode that hurts most.
# PRIORITY shows the --rank priority winner only where it differs.
_strat () { awk -F'\t' '$1 == "__EXTRACT_META__" {print $2 "/" $3; exit}' "$1" 2>/dev/null; }
printf '\n%-40s %-26s %5s %5s %5s %s\n' NAME STRATEGY/CONF IN OUT MULTI PRIORITY
for f in "$set_dir"/*.txt; do
    n=$(basename "$f" .txt)
    s=$(_strat "$outdir/$n.meta")
    p=$(_strat "$outdir/$n.prio.meta")
    [[ "${p%/*}" == "${s%/*}" ]] && p="="
    printf '%-40s %-26s %5s %5s %5s %s\n' \
        "$n" "${s:-none}" "$(wc -l <"$f")" "$(wc -l <"$outdir/$n.def")" \
        "$(grep -c '__DATASET__' "$outdir/$n.multi" 2>/dev/null || echo 0)" \
        "${p:-none}"
done
