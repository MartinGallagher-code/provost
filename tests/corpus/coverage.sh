#!/usr/bin/env bash
# tests/corpus/coverage.sh — how much of each input survives into its parse?
#
# The reviewer's recurring complaint across the corpus rounds is "you lost
# information" (btrfs-filesystem-show, biosdecode, clpeak-run, arp-scan,
# R-sessioninfo). That is measurable: COVERAGE is the fraction of an input's
# significant tokens that appear in some cell of its parsed output. This walks
# the corpus and reports it, lowest first, so lossy parses surface by themselves
# instead of being found by eye.
#
# It uses the same scorer the extract engine uses to choose between candidate
# segmentations (extract/lib/_score.sh), so the number here is the number the
# engine acts on.
#
#   coverage.sh                 report every input, lowest coverage first
#   coverage.sh --threshold 70  only inputs below 70%
#   coverage.sh --multi         score the --multi parse instead of the default
#   coverage.sh -o FILE         write TSV (name, coverage, strategy) to FILE
#
# IMPORTANT — coverage is a REVIEW SIGNAL, not a gate. It works well
# RELATIVELY (same input, two candidate parses: that is what the engine uses it
# for) but only roughly in ABSOLUTE terms across different tools, because many
# parses legitimately drop chrome, units and decoration. Measured against the
# reviewer's own marks, the lossy group scored 13-68% and the agreed group
# 59-100% — clearly separated on average, overlapping in the middle. Treat a low
# score as "look at this", never as "this is broken".
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
ENGINE="$ROOT/extract/envoy-extract"
IN="$HERE/inputs"

threshold=101
multi=0
out=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --threshold) threshold="${2:?--threshold needs a number}"; shift 2 ;;
        --multi)     multi=1; shift ;;
        -o|--output) out="${2:?-o needs a path}"; shift 2 ;;
        -h|--help)   sed -n '2,30p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

# shellcheck source=/dev/null
source "$ROOT/extract/lib/_score.sh"

# Coverage alone, without the tidiness/veto machinery: re-derive it here so the
# report says exactly "how much survived", which is what a reviewer wants to
# see, rather than the composite the engine ranks on.
_coverage_of () {
    awk '
        function norm(s) {
            gsub(/^[^A-Za-z0-9]+/, "", s); gsub(/[^A-Za-z0-9]+$/, "", s); return s
        }
        NR == FNR {
            n = split($0, a, /[ \t_]+/)
            for (i = 1; i <= n; i++) { t = norm(a[i]); if (t ~ /[A-Za-z0-9]/ && !(t in si)) { si[t] = 1; ntok++ } }
            next
        }
        {
            if ($0 == "") next
            sp = index($0, " "); val = (sp ? substr($0, sp + 1) : "")
            fname = (sp ? substr($0, 1, sp - 1) : $0)
            n = split(val, b, /[ \t_]+/)
            for (i = 1; i <= n; i++) { t = norm(b[i]); if (t ~ /[A-Za-z0-9]/) so[t] = 1 }
            # Field names count as survival too — see _score.sh.
            nm = fname
            sub(/^d[0-9]+_/, "", nm); sub(/^entry[0-9]+\./, "", nm)
            if (nm !~ /^line[0-9]+$/ && nm != "total_entries" && nm !~ /^[A-Z][A-Z]?$/) {
                n = split(nm, k, /[ \t_.]+/)
                for (i = 1; i <= n; i++) { t = norm(k[i]); if (t ~ /[A-Za-z0-9]/) so[t] = 1 }
            }
        }
        END {
            if (ntok == 0) { print 100; exit }
            for (t in si) if (t in so) hit++
            printf "%d\n", hit * 100 / ntok
        }
    ' "$1" "$2"
}

JOBS="${GLEAN_CORPUS_JOBS:-$(nproc 2>/dev/null || echo 4)}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/glean-coverage.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

_one () {
    local f="$1" name w fields cov strat
    name="$(basename "$f" .txt)"
    local margs=(-f plain --raw --max-strategies 1)
    [[ $multi -eq 1 ]] && margs=(--multi "${margs[@]}")
    w="$(timeout 60 bash "$ENGINE" "${margs[@]}" --emit-meta "$f" 2>"$WORK/$name.err")" || true
    strat="$(grep '^__EXTRACT_META__' "$WORK/$name.err" 2>/dev/null | tail -1 | cut -f2)"
    [[ -n "$strat" ]] || strat="(none)"
    printf '%s\n' "$w" | grep -v '^__DATASET__' | sed 's/^STRAT-[^\t]*\t//' > "$WORK/$name.fields"
    cov="$(_coverage_of "$f" "$WORK/$name.fields")"
    rm -f "$WORK/$name.err" "$WORK/$name.fields"
    printf '%s\t%s\t%s\n' "$name" "$cov" "$strat"
}
export -f _one _coverage_of
export ENGINE WORK multi

ls "$IN"/*.txt | xargs -P "$JOBS" -I{} bash -c '_one "$@"' _ {} 2>/dev/null \
    | sort -t$'\t' -k2,2n -k1,1 > "$WORK/all.tsv"

total=$(wc -l < "$WORK/all.tsv")
flagged=$(awk -F'\t' -v t="$threshold" '$2 < t' "$WORK/all.tsv" | wc -l)

if [[ -n "$out" ]]; then
    { printf 'name\tcoverage\tstrategy\n'; awk -F'\t' -v t="$threshold" '$2 < t' "$WORK/all.tsv"; } > "$out"
    echo "wrote $out — $flagged of $total inputs below ${threshold}%"
else
    printf '%-40s %9s  %s\n' "INPUT" "COVERAGE" "STRATEGY"
    awk -F'\t' -v t="$threshold" '$2 < t { printf "%-40s %8s%%  %s\n", $1, $2, $3 }' "$WORK/all.tsv"
    echo
    echo "$flagged of $total inputs below ${threshold}% coverage"
fi
