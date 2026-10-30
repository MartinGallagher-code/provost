#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## The layout model on a benchmark round, model-first: every input under
## roundN/inputs/ is labelled by the model (the tiny LM with --lm DIR, else
## the shipped trees), and its records are measured and turned into a dataset
## exactly as provost's --model path does (the engine's `-s layout-model`
## with the records handed in, then the tidy melt). No quality gate and no
## engine parse: this is what the model alone makes of every capture, to rate
## on the round's CRITERIA.md against the default engine's ratings.
##
## Usage:
##   bash tests/benchmark/model_round.sh --round4 outdir [--lm DIR]
##
## Writes, per input NAME, under outdir:
##   NAME.out        one line: what the model filed (or that it read nothing)
##   NAME.meta       strategy, confidence, coverage, consistency
##   NAME.layout-model.tsv   the dataset (tidy), when there is one
## and outdir/summary.tsv: name, rows, coverage, consistency.
################################################################################
set -uo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
root=$(cd -- "$here/../.." && pwd)

round=""; outdir=""; lm=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --round[0-9]*) round="${1#--}"; shift ;;
        --lm) lm="$2"; shift 2 ;;
        -*) echo "unknown option: $1" >&2; exit 2 ;;
        *) outdir="$1"; shift ;;
    esac
done
[[ -n "$round" && -n "$outdir" ]] || { echo "usage: $0 --roundN outdir [--lm DIR]" >&2; exit 2; }
set_dir="$here/$round/inputs"
[[ -d "$set_dir" ]] || { echo "no such inputs directory: $set_dir" >&2; exit 2; }
mkdir -p "$outdir/.rec"

python3 "$here/model_records.py" ${lm:+--lm "$lm"} "$outdir/.rec" "$set_dir"/*.txt > "$outdir/.rec/list" \
    || { echo "labelling failed" >&2; exit 1; }

# shellcheck source=../../transform/melt.sh
source "$root/transform/melt.sh"
export PROVOST_NO_RC=1
printf 'name\trows\tcoverage\tconsistency\n' > "$outdir/summary.tsv"
for in_file in "$set_dir"/*.txt; do
    stem="$(basename "$in_file" .txt)"
    rec="$outdir/.rec/$stem.rec"
    wide="$outdir/.rec/$stem.wide"
    meta="$outdir/.rec/$stem.emeta"
    : > "$wide"
    if [[ -s "$rec" ]]; then
        PROVOST_LM_RECORDS="$rec" bash "$root/extract/provost-extract" -s layout-model --emit-meta \
            -f tsv --max-strategies 1 "$in_file" > "$wide" 2> "$meta" || true
    fi
    IFS=$'\t' read -r s c v t < <(awk -F'\t' '/^__EXTRACT_META__/ { s = $2; c = $3; v = $4; t = $5 }
        END { printf "%s\t%s\t%s\t%s\n", s, c, v, t }' "$meta" 2>/dev/null) || true
    if [[ "${s:-}" == layout-model && -s "$wide" ]] && grep -q . "$wide"; then
        _core_melt_tidy_file "$wide" > "$outdir/$stem.layout-model.tsv"
        rows=$(( $(wc -l < "$outdir/$stem.layout-model.tsv") - 1 ))
        printf 'filed by the layout model: dataset layout-model, %s row(s), coverage %s%%\n' \
            "$rows" "${v:--}" > "$outdir/$stem.out"
    else
        rows=0
        printf 'the layout model read nothing it could file: nothing extracted\n' > "$outdir/$stem.out"
    fi
    printf 'strategy\tlayout-model\nconfidence\t%s\ncoverage\t%s\nconsistency\t%s\n' \
        "${c:--}" "${v:--}" "${t:--}" > "$outdir/$stem.meta"
    printf '%s\t%s\t%s\t%s\n' "$stem" "$rows" "${v:--}" "${t:--}" >> "$outdir/summary.tsv"
    unset s c v t
done
rm -rf "$outdir/.rec"
echo "wrote $outdir/summary.tsv"
awk -F'\t' 'NR > 1 { n++; if ($2 > 0) f++ } END { printf "  %d inputs, %d filed, %d read nothing\n", n, f, n - f }' \
    "$outdir/summary.tsv"
