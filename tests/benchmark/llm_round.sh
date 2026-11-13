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
## Rounds 4 and 5's templates are no longer in the tree (PV-042): restore the
## directories a run names from the archive commit first (README.md, "LLM run
## records"), or name your own with --templates. A directory that is missing
## or holds no *.json stops the run (exit 2) rather than reading every input
## untemplated.
##
## Usage:
##   bash tests/benchmark/llm_round.sh --round4 [outdir] [--templates DIR[:DIR...]]
##   (several directories: the first one holding <stem>.json wins, so
##   `--templates round4/llm-templates-f2:round4/llm-templates` runs the
##   format-2 rewrites where they exist and the format-1 templates elsewhere)
##   [--inputs DIR]   read the inputs from DIR instead of roundN/inputs/ (e.g.
##   round4/variants/: a second capture of each tool, to test a stored
##   template on output it was not written from)
##   [--learn]        keep the API key (PROVOST_LLM_API_KEY): with no
##   --templates, Claude writes each input's template (`template.py learn`,
##   through the CLI exactly as a user's capture would be); with --templates,
##   a stored template that misses lines is repaired. Costs API calls; every
##   reply's usage goes to outdir/llm-log.jsonl.
##   [--examples DIR] give each offered template DIR/<stem>.txt as the capture
##   it was written from (what `learn` stores with a template), e.g. the
##   round's inputs/ when the run reads variants/
##   [--jobs N]       run N inputs at once (default 1)
##
## Writes, per input NAME, under outdir:
##   NAME.out        provost's own report of the capture
##   NAME.meta       the capture's meta.tsv (strategy, coverage, llm_template …)
##   NAME.<ds>.tsv   every dataset the capture filed (tidy)
##   templates/NAME.json  (--learn) the template the store kept, if any
## and outdir/summary.tsv: name, filed-by (template | engine | held),
## strategy, llm_template line, datasets. Rate the tidy files on the round's
## CRITERIA.md; this script makes no judgement.
################################################################################
set -uo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
root=$(cd -- "$here/../.." && pwd)
provost="$root/provost"

round=""; outdir=""; tdir=""; idir=""; learn=0; edir=""; jobs=1
while [[ $# -gt 0 ]]; do
    case "$1" in
        --round[0-9]*) round="${1#--}"; shift ;;
        --templates) tdir="$2"; shift 2 ;;
        --inputs) idir="$2"; shift 2 ;;
        --learn) learn=1; shift ;;
        --examples) edir="$2"; shift 2 ;;
        --jobs) jobs="$2"; shift 2 ;;
        -*) echo "unknown option: $1" >&2; exit 2 ;;
        *) outdir="$1"; shift ;;
    esac
done
[[ -n "$round" ]] || { echo "usage: $0 --roundN [outdir] [--templates DIR] [--inputs DIR] [--learn] [--examples DIR] [--jobs N]" >&2; exit 2; }
[[ "$jobs" =~ ^[1-9][0-9]*$ ]] || { echo "--jobs needs a whole number" >&2; exit 2; }
set_dir="${idir:-$here/$round/inputs}"
[[ -d "$set_dir" ]] || { echo "no such inputs directory: $set_dir" >&2; exit 2; }
(( learn )) || [[ -n "$tdir" ]] || tdir="$here/$round/llm-templates"
# shellcheck source=tests/benchmark/llm_archive.sh
source "$here/llm_archive.sh"
[[ -z "$tdir" ]] || need_templates "$tdir"
[[ -n "$outdir" ]] || outdir="$(mktemp -d)"
mkdir -p "$outdir/.sum"

if (( learn )); then
    [[ -n "${PROVOST_LLM_API_KEY:-}${ANTHROPIC_API_KEY:-}" ]] || { echo "--learn needs PROVOST_LLM_API_KEY" >&2; exit 2; }
    mkdir -p "$outdir/templates"
    export PROVOST_LLM_LOG="$outdir/llm-log.jsonl"
else
    unset PROVOST_LLM_API_KEY ANTHROPIC_API_KEY
fi
export PROVOST_LLM=1 PROVOST_NO_RC=1

one_input () {
    local in_file="$1" stem ws one _td _tds d b ds="" strategy llm by
    stem="$(basename "$in_file" .txt)"
    ws="$(mktemp -d)/.store"
    # a per-input template dir: the capture is named after the stem's tool, and
    # provost looks for <name>.json first, then any template whose detect fits
    one="$(mktemp -d)"
    IFS=: read -ra _tds <<< "$tdir"
    for _td in ${_tds[@]+"${_tds[@]}"}; do      # --templates A:B — the first dir holding the stem wins
        [[ -f "$_td/$stem.json" ]] || continue
        if [[ -n "$edir" && -f "$edir/$stem.txt" ]]; then
            python3 - "$_td/$stem.json" "$edir/$stem.txt" "$one/${stem#[0-9]*-}.json" <<'PY'
import json, sys
t = json.load(open(sys.argv[1], encoding="utf-8"))
if not t.get("examples"):
    s = open(sys.argv[2], encoding="utf-8", errors="replace").read()
    t["examples"] = [s[:-1] if s.endswith("\n") else s]
json.dump(t, open(sys.argv[3], "w", encoding="utf-8"), indent=1, ensure_ascii=False)
PY
        else
            cp "$_td/$stem.json" "$one/${stem#[0-9]*-}.json"
        fi
        break
    done
    PROVOST_WORKSPACE="$ws" PROVOST_LLM_TEMPLATE_DIRS="$one" \
        "$provost" --sync --name "${stem#[0-9]*-}" "$in_file" > "$outdir/$stem.out" 2>&1
    cp "$ws/captures/c0001/meta.tsv" "$outdir/$stem.meta" 2>/dev/null || true
    for d in "$ws"/datasets/*.tsv; do
        [[ -f "$d" ]] || continue
        b="$(basename "$d" .tsv)"
        [[ "$b" == unsorted ]] && continue
        cp "$d" "$outdir/$stem.$b.tsv"
        ds="${ds:+$ds,}$b"
    done
    if (( learn )); then
        for d in "$ws"/llm-templates/*.json; do [[ -f "$d" ]] && cp "$d" "$outdir/templates/$stem.json"; done
    fi
    strategy="$(awk -F'\t' '$1 == "strategy" { print $2 }' "$outdir/$stem.meta" 2>/dev/null)"
    llm="$(awk -F'\t' '$1 == "llm_template" { print $2 }' "$outdir/$stem.meta" 2>/dev/null)"
    if [[ "$llm" == filed* ]]; then by=template
    elif [[ -z "$ds" ]]; then by=held
    else by=engine; fi
    printf '%s\t%s\t%s\t%s\t%s\n' "$stem" "$by" "$strategy" "$llm" "$ds" > "$outdir/.sum/$stem"
    rm -rf "$(dirname "$ws")" "$one"
}

for in_file in "$set_dir"/*.txt; do
    while (( $(jobs -rp | wc -l) >= jobs )); do wait -n; done
    one_input "$in_file" &
done
wait
printf 'name\tfiled_by\tstrategy\tllm_template\tdatasets\n' > "$outdir/summary.tsv"
cat "$outdir"/.sum/* >> "$outdir/summary.tsv" 2>/dev/null
rm -rf "$outdir/.sum"
echo "wrote $outdir/summary.tsv"
awk -F'\t' 'NR > 1 { n[$2]++ } END { for (k in n) printf "  %-9s %d\n", k, n[k] }' "$outdir/summary.tsv"
