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
##   NAME.layout-model.tsv   the dataset (tidy), when the whole input is one
##                   table or one key/value record; else, as provost's
##                   --model does, NAME.layout-model.segK.tsv for each of the
##                   model's own sections
## and outdir/summary.tsv: name, rows, how it was filed, coverage, consistency.
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
printf 'name\trows\tfiled\tcoverage\tconsistency\n' > "$outdir/summary.tsv"
# measure: the engine's -s layout-model on the records handed in, then the melt.
# Sets M_ROWS / M_COV / M_CONS; writes the tidy table to $3.
measure () {
    local inp="$1" rec="$2" tsv="$3" wide="$outdir/.rec/m.wide" meta="$outdir/.rec/m.meta" s c v t
    M_ROWS=0; M_COV=-; M_CONS=-
    [[ -s "$rec" ]] || return 1
    PROVOST_LM_RECORDS="$rec" bash "$root/extract/provost-extract" -s layout-model --emit-meta \
        -f tsv --max-strategies 1 "$inp" > "$wide" 2> "$meta" || true
    IFS=$'\t' read -r s c v t < <(awk -F'\t' '/^__EXTRACT_META__/ { s = $2; c = $3; v = $4; t = $5 }
        END { printf "%s\t%s\t%s\t%s\n", s, c, v, t }' "$meta" 2>/dev/null) || true
    [[ "${s:-}" == layout-model && -s "$wide" ]] && grep -q . "$wide" || return 1
    _core_melt_tidy_file "$wide" > "$tsv"
    M_ROWS=$(( $(wc -l < "$tsv") - 1 )); M_COV="${v:--}"; M_CONS="${t:--}"
    return 0
}

for in_file in "$set_dir"/*.txt; do
    stem="$(basename "$in_file" .txt)"
    how="" rows=0 cov=- cons=-
    if measure "$in_file" "$outdir/.rec/$stem.rec" "$outdir/$stem.layout-model.tsv"; then
        how="one dataset"; rows=$M_ROWS; cov=$M_COV; cons=$M_CONS
    else
        rm -f "$outdir/$stem.layout-model.tsv"
        k=0
        for seg in "$outdir/.rec/$stem".seg.*.txt; do
            [[ -f "$seg" ]] || continue
            k=$((k + 1))
            if measure "$seg" "${seg%.txt}.rec" "$outdir/$stem.layout-model.seg$k.tsv"; then
                rows=$(( rows + M_ROWS ))
            else
                rm -f "$outdir/$stem.layout-model.seg$k.tsv"
            fi
        done
        (( rows > 0 )) && how="$k section(s)"
    fi
    if [[ -n "$how" ]]; then
        printf 'filed by the layout model: %s, %s row(s), coverage %s%%\n' "$how" "$rows" "$cov" > "$outdir/$stem.out"
    else
        printf 'the layout model read nothing it could file: nothing extracted\n' > "$outdir/$stem.out"
    fi
    printf 'strategy\tlayout-model\nfiled\t%s\ncoverage\t%s\nconsistency\t%s\n' \
        "${how:-nothing}" "$cov" "$cons" > "$outdir/$stem.meta"
    printf '%s\t%s\t%s\t%s\t%s\n' "$stem" "$rows" "${how:-nothing}" "$cov" "$cons" >> "$outdir/summary.tsv"
done
rm -rf "$outdir/.rec"
echo "wrote $outdir/summary.tsv"
awk -F'\t' 'NR > 1 { n++; if ($2 > 0) f++ } END { printf "  %d inputs, %d filed, %d read nothing\n", n, f, n - f }' \
    "$outdir/summary.tsv"
