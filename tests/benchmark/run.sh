#!/usr/bin/env bash
################################################################################
## Held-out generalisation benchmark.
##
## Every input under inputs/ is a tool output the engine has NEVER been tuned
## against — no hint row, no strategy, no golden. The corpus under
## tests/corpus/ measures regression; this measures generalisation, which is a
## different and harsher question: what happens the first time glean meets an
## output nobody wrote a parser for?
##
## There is deliberately no pass/fail gate here. A gate would invite fitting
## the engine to these 50 files, which destroys the only property that makes
## them useful. The ratings in ratings.tsv are a snapshot of a human-readable
## judgement (see docs/benchmark-2026-08-12-generalisation.md); re-run this
## script and re-read the diff when you want to know whether a change helped
## or hurt inputs it was not written for.
##
## Usage:
##   bash tests/benchmark/run.sh [outdir]      # default: a fresh mktemp dir
##
## Writes, per input NAME:
##   NAME.def     default single-dataset extract (what `glean` does bare)
##   NAME.meta    the strategy that claimed it, and its confidence
##   NAME.multi   the --multi segmentation
################################################################################
set -uo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
root=$(cd -- "$here/../.." && pwd)
engine="$root/extract/envoy-extract"
outdir="${1:-$(mktemp -d)}"

mkdir -p "$outdir"

for f in "$here"/inputs/*.txt; do
    n=$(basename "$f" .txt)
    # --emit-meta writes its banner to STDERR, not into the field stream, so the
    # parse and the strategy that produced it separate for free.
    "$engine" -f plain --max-strategies 1 --emit-meta <"$f" \
        >"$outdir/$n.def" 2>"$outdir/$n.meta"
    "$engine" -f plain --multi <"$f" >"$outdir/$n.multi" 2>/dev/null
done

printf 'benchmark outputs: %s\n' "$outdir"

# Summary line per input: how the engine read it, and how big the parse came
# out relative to the input. A parse much SHORTER than its input is the
# signature of silent truncation, which is the failure mode that hurts most.
printf '\n%-28s %-24s %5s %5s %s\n' NAME STRATEGY/CONF IN OUT MULTI
for f in "$here"/inputs/*.txt; do
    n=$(basename "$f" .txt)
    s=$(awk -F'\t' 'NR==1 {print $2 "/" $3}' "$outdir/$n.meta" 2>/dev/null)
    printf '%-28s %-24s %5s %5s %s\n' \
        "$n" "${s:-none}" "$(wc -l <"$f")" "$(wc -l <"$outdir/$n.def")" \
        "$(grep -c '__DATASET__' "$outdir/$n.multi" 2>/dev/null || echo 0)"
done
