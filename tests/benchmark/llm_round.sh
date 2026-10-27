#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## LLM templates on a benchmark round: every input under roundN/inputs/ goes
## through the real CLI (`provost --sync --llm`, one fresh store per input)
## with the round's templates (roundN/llm-templates/<stem>.json) offered as a
## template directory, and nothing else (no API: PROVOST_LLM_API_KEY is
## unset, so a template that does not fit leaves the capture held exactly as
## the default run would).
##
## Usage:
##   bash tests/benchmark/llm_round.sh --round4 [outdir] [--templates DIR[:DIR...]]
##   (several directories: the first one holding <stem>.json wins, so
##   `--templates round4/llm-templates-f2:round4/llm-templates` runs the
##   format-2 rewrites where they exist and the format-1 templates elsewhere)
##
## Writes, per input NAME, under outdir:
##   NAME.out        provost's own report of the capture
##   NAME.meta       the capture's meta.tsv (strategy, coverage, llm_template …)
##   NAME.<ds>.tsv   every dataset the capture filed (tidy)
## and outdir/summary.tsv: name, filed-by (template | engine | held),
## strategy, llm_template line, datasets. Rate the tidy files on the round's
## CRITERIA.md; this script makes no judgement.
################################################################################
set -uo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
root=$(cd -- "$here/../.." && pwd)
provost="$root/provost"

round=""; outdir=""; tdir=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --round[0-9]*) round="${1#--}"; shift ;;
        --templates) tdir="$2"; shift 2 ;;
        -*) echo "unknown option: $1" >&2; exit 2 ;;
        *) outdir="$1"; shift ;;
    esac
done
[[ -n "$round" ]] || { echo "usage: $0 --roundN [outdir] [--templates DIR]" >&2; exit 2; }
set_dir="$here/$round/inputs"
[[ -d "$set_dir" ]] || { echo "no such round: $set_dir" >&2; exit 2; }
[[ -n "$tdir" ]] || tdir="$here/$round/llm-templates"
[[ -n "$outdir" ]] || outdir="$(mktemp -d)"
mkdir -p "$outdir"

unset PROVOST_LLM_API_KEY ANTHROPIC_API_KEY
export PROVOST_LLM=1 PROVOST_LLM_TEMPLATE_DIRS="$tdir" PROVOST_NO_RC=1

printf 'name\tfiled_by\tstrategy\tllm_template\tdatasets\n' > "$outdir/summary.tsv"
for in_file in "$set_dir"/*.txt; do
    stem="$(basename "$in_file" .txt)"
    ws="$(mktemp -d)/.store"
    # a per-input template dir: the capture is named after the stem's tool, and
    # provost looks for <name>.json first, then any template whose detect fits
    one="$(mktemp -d)"
    IFS=: read -ra _tds <<< "$tdir"
    for _td in "${_tds[@]}"; do      # --templates A:B — the first dir holding the stem wins
        [[ -f "$_td/$stem.json" ]] && { cp "$_td/$stem.json" "$one/${stem#[0-9]*-}.json"; break; }
    done
    PROVOST_WORKSPACE="$ws" PROVOST_LLM_TEMPLATE_DIRS="$one" \
        "$provost" --sync --name "${stem#[0-9]*-}" "$in_file" > "$outdir/$stem.out" 2>&1
    cp "$ws/captures/c0001/meta.tsv" "$outdir/$stem.meta" 2>/dev/null || true
    ds=""
    for d in "$ws"/datasets/*.tsv; do
        [[ -f "$d" ]] || continue
        b="$(basename "$d" .tsv)"
        [[ "$b" == unsorted ]] && continue
        cp "$d" "$outdir/$stem.$b.tsv"
        ds="${ds:+$ds,}$b"
    done
    strategy="$(awk -F'\t' '$1 == "strategy" { print $2 }' "$outdir/$stem.meta" 2>/dev/null)"
    llm="$(awk -F'\t' '$1 == "llm_template" { print $2 }' "$outdir/$stem.meta" 2>/dev/null)"
    if [[ "$llm" == filed* ]]; then by=template
    elif [[ -z "$ds" ]]; then by=held
    else by=engine; fi
    printf '%s\t%s\t%s\t%s\t%s\n' "$stem" "$by" "$strategy" "$llm" "$ds" >> "$outdir/summary.tsv"
    rm -rf "$(dirname "$ws")" "$one"
done
echo "wrote $outdir/summary.tsv"
awk -F'\t' 'NR > 1 { n[$2]++ } END { for (k in n) printf "  %-9s %d\n", k, n[k] }' "$outdir/summary.tsv"
