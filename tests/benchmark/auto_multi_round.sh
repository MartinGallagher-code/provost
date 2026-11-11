#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## The automatic --multi fallback on a benchmark round, through the real CLI:
## every input under roundN/inputs/ is captured once by `provost --sync`, each
## into a fresh store, with provost's defaults (PROVOST_AUTO_MULTI=1, the
## quality gate on, no --model, no --llm). This is how HANDOFF 0a measured
## auto-multi on round 4 (2026-10-20), as a script, so the next round is
## measured the same way.
##
## Usage:
##   bash tests/benchmark/auto_multi_round.sh --round4 outdir [-j N]
##
## Writes, under outdir:
##   summary.tsv   name, outcome (filed / segmented / held), the single
##                 parse's strategy, coverage and consistency, the number of
##                 datasets filed, and meta.tsv's auto_multi line (why it was
##                 segmented, or why segmenting was declined)
##   NAME/         the store's datasets/ (tidy TSV, one file per dataset) and
##                 the capture's meta.tsv
## Rate a segmented capture by its datasets: they are the engine's --multi
## datasets (run.sh's NAME.multi.tidy), so a round already rated for --multi
## rates them by that rating where the two are the same tables.
################################################################################
set -uo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
root=$(cd -- "$here/../.." && pwd)

round=""; outdir=""; jobs="${PROVOST_BENCH_JOBS:-$(nproc 2>/dev/null || echo 2)}"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --round[0-9]*) round="${1#--}"; shift ;;
        -j) jobs="${2:?-j needs a number}"; shift 2 ;;
        -j*) jobs="${1#-j}"; shift ;;
        -h|--help) sed -n '/^## Usage:/,/^####/p' "${BASH_SOURCE[0]}" | sed 's/^## \{0,1\}//'; exit 0 ;;
        -*) echo "auto_multi_round.sh: unknown option: $1" >&2; exit 2 ;;
        *) outdir="$1"; shift ;;
    esac
done
[[ -n "$round" && -n "$outdir" ]] || { echo "usage: $0 --roundN outdir [-j N]" >&2; exit 2; }
set_dir="$here/$round/inputs"
[[ -d "$set_dir" ]] || { echo "no such inputs directory: $set_dir" >&2; exit 2; }
mkdir -p "$outdir"
outdir=$(cd -- "$outdir" && pwd)

# one INPUT — capture it into a fresh store and keep what it filed.
one () {
    local f="$1" n ws meta outcome single scov scons nds am
    n=$(basename "$f" .txt)
    ws=$(mktemp -d)
    PROVOST_NO_RC=1 PROVOST_WORKSPACE="$ws/store" PROVOST_AUTO_MULTI=1 \
        PROVOST_MODEL=0 PROVOST_LLM=0 \
        "$root/provost" --sync <"$f" >"$ws/log" 2>&1 || true
    mkdir -p "$outdir/$n"
    meta=$(find "$ws/store/captures" -name meta.tsv 2>/dev/null | head -n 1)
    if [[ -n "$meta" ]]; then
        cp "$meta" "$outdir/$n/meta.tsv"
        cp "$ws/store/datasets/"*.tsv "$outdir/$n/" 2>/dev/null || true
    fi
    cp "$ws/log" "$outdir/$n/log"
    rm -rf "$ws"
    _m () { awk -F'\t' -v k="$1" '$1 == k { print $2; exit }' "$outdir/$n/meta.tsv" 2>/dev/null; }
    am=$(_m auto_multi)
    if [[ "$(_m dataset)" == unsorted ]]; then outcome=held
    elif [[ "$am" == segmented* ]]; then outcome=segmented
    else outcome=filed; fi
    single=$(_m single_strategy); scov=$(_m single_coverage); scons=$(_m single_consistency)
    if [[ -z "$single" ]]; then single=$(_m strategy); scov=$(_m coverage); scons=$(_m consistency); fi
    nds=$(_m datasets); nds="${nds:-1}"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$n" "$outcome" "${single:--}" "${scov:--}" "${scons:--}" \
        "$nds" "${am:--}" > "$outdir/$n/row"
}
export -f one
export root outdir

find "$set_dir" -maxdepth 1 -name '*.txt' -print0 | sort -z \
    | xargs -0 -n 1 -P "$jobs" bash -c 'one "$1"' _
{
    printf 'name\toutcome\tsingle_strategy\tsingle_coverage\tsingle_consistency\tdatasets\tauto_multi\n'
    for d in "$outdir"/*/; do cat "$d/row" 2>/dev/null; done
} > "$outdir/summary.tsv"
awk -F'\t' 'NR > 1 { c[$2]++ } END { for (k in c) printf "%s %d\n", k, c[k] }' "$outdir/summary.tsv" | sort
