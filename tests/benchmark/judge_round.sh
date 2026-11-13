#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## The --llm judge alone, on a round's stored templates (PV-009): each
## template under DIR (default roundN/llm-templates-learn/, the templates
## `llm_round.sh --learn` kept) is reviewed on the input it was written from
## (`template.py judge`: one call, and on a FIX one revision), and the
## template that comes out is written to outdir/judged/<stem>.json. Nothing
## else changes, so running `llm_round.sh --roundN OUT --templates DIR` and
## `--templates outdir/judged` measures the judge and nothing but the judge.
##
## Usage:
##   bash tests/benchmark/judge_round.sh --round5 OUTDIR [--templates DIR] [--jobs N]
##
## Needs PROVOST_LLM_API_KEY (or ANTHROPIC_API_KEY); every reply's usage goes
## to outdir/llm-log.jsonl. Writes outdir/judge.tsv: stem, verdict
## (PASS | FIX | none), applied (yes | no | -), fixes (joined with " | "),
## the summary line.
##
## Rounds 4 and 5's templates are no longer in the tree (PV-042): restore
## roundN/llm-templates-learn/ from the archive commit first (README.md, "LLM
## run records"), or name your own with --templates. A directory that is
## missing or holds no *.json stops the run (exit 2) before any API call.
################################################################################
set -uo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
root=$(cd -- "$here/../.." && pwd)
py="$root/extract/llm/template.py"

round=""; outdir=""; tdir=""; jobs=1
while [[ $# -gt 0 ]]; do
    case "$1" in
        --round[0-9]*) round="${1#--}"; shift ;;
        --templates) tdir="$2"; shift 2 ;;
        --jobs) jobs="$2"; shift 2 ;;
        -*) echo "unknown option: $1" >&2; exit 2 ;;
        *) outdir="$1"; shift ;;
    esac
done
[[ -n "$round" && -n "$outdir" ]] || { echo "usage: $0 --roundN OUTDIR [--templates DIR] [--jobs N]" >&2; exit 2; }
[[ "$jobs" =~ ^[1-9][0-9]*$ ]] || { echo "--jobs needs a whole number" >&2; exit 2; }
tdir="${tdir:-$here/$round/llm-templates-learn}"
idir="$here/$round/inputs"
[[ -d "$idir" ]] || { echo "no such inputs directory: $idir" >&2; exit 2; }
# shellcheck source=tests/benchmark/llm_archive.sh
source "$here/llm_archive.sh"
need_templates "$tdir"
[[ -n "${PROVOST_LLM_API_KEY:-}${ANTHROPIC_API_KEY:-}" ]] || { echo "needs PROVOST_LLM_API_KEY" >&2; exit 2; }
mkdir -p "$outdir/judged" "$outdir/.j"
export PROVOST_LLM_LOG="$outdir/llm-log.jsonl"

one () {
    local t="$1" stem in out tool
    stem="$(basename "$t" .json)"; in="$idir/$stem.txt"
    [[ -f "$in" ]] || return 0
    tool="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1])).get("tool") or "")' "$t" 2>/dev/null)"
    if out="$(python3 "$py" judge "$t" "$in" --out "$outdir/judged/$stem.json" --tool "$tool" 2>&1)"; then
        python3 - "$outdir/judged/$stem.json" "$stem" "${out#*$'\n'}" > "$outdir/.j/$stem" <<'PY'
import json, sys
t = json.load(open(sys.argv[1]))
j = t.get("judge") or {}
applied = "-" if j.get("verdict") != "FIX" else ("yes" if j.get("applied") else "no")
fixes = " | ".join(f.replace("\t", " ").replace("\n", " ") for f in j.get("fixes") or [])
print("\t".join([sys.argv[2], j.get("verdict", "none"), applied, fixes, sys.argv[3].replace("\t", " ")]))
PY
    else
        cp "$t" "$outdir/judged/$stem.json"
        printf '%s\tnone\t-\t\t%s\n' "$stem" "${out//$'\n'/ }" > "$outdir/.j/$stem"
    fi
}
export -f one
export py idir outdir

ls "$tdir"/*.json | xargs -P "$jobs" -I{} bash -c 'one "$1"' _ {}
{ printf 'stem\tverdict\tapplied\tfixes\tsummary\n'; cat "$outdir"/.j/* 2>/dev/null; } > "$outdir/judge.tsv"
rm -rf "$outdir/.j"
awk -F'\t' 'NR>1{n[$2 ($3=="-"?"":" applied=" $3)]++} END{for (k in n) print n[k] "\t" k}' "$outdir/judge.tsv" | sort -k2
