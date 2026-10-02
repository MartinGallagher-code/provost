#!/usr/bin/env bash
# tests/corpus/holdout/run.sh — generalization check on UNSEEN tool output.
#
# The main corpus (tests/corpus/) freezes one fixture per tool, so it measures
# whether coverage regressed — not whether the parsers GENERALIZE. This holdout
# set holds a second, different output per tool (other hosts, versions, values,
# flag mixes) with NO goldens: each input is only checked for tidy shape
# against expected.tsv, exactly the way an unseen capture would be judged.
#
# Each input runs in FULL mode (hints + all strategies — what glean actually
# does), and the winner is attributed to a tier:
#   generic  — a format parser from strategies/delimited/ or structured/
#   hint     — a hints.tsv row routed it
#   bespoke  — a per-tool strategy script caught it
#
# Passing bar: every input tidy. The tier column is the trend to watch — new
# holdout entries should land generic/hint, not bespoke.
#
# Keep inputs REALISTIC (real tool output, edited only in content), and always
# DIFFERENT from tests/corpus/inputs/<tool>.txt — a holdout that repeats the
# fixture measures nothing.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
ENGINE="$ROOT/extract/provost-extract"
HINTS="$ROOT/extract/hints.tsv"
IN="$HERE/inputs"
MANIFEST="$HERE/expected.tsv"
# shellcheck source=/dev/null
source "$ROOT/transform/melt.sh"

pass=0; fail=0; total=0
declare -A TIER_COUNT
declare -a FAILED

_tier () { # $1 = winner strategy/report name
    local w="$1" f
    for f in "$ROOT/extract/strategies/delimited/$w.sh" "$ROOT/extract/strategies/structured/$w.sh"; do
        [[ -f "$f" ]] && { echo generic; return; }
    done
    if [[ -f "$HINTS" ]] && awk -F'\t' -v n="$w" '$1==n && $1 !~ /^#/ {found=1} END{exit !found}' "$HINTS"; then
        echo hint; return
    fi
    # columnar-specs reports per-tool names; the engine itself is generic
    # (spec rows are written as $'name\t…' — match the \t escape, not a tab)
    if grep -qF "\$'$w\\t" "$ROOT/extract/strategies/delimited/columnar-specs.sh" 2>/dev/null; then
        echo generic; return
    fi
    echo bespoke
}

printf '%-22s %-24s %-8s %6s  %s\n' 'INPUT' 'WINNER' 'TIER' 'CxR' 'TIDY'
printf '%s\n' "----------------------------------------------------------------------"

for f in "$IN"/*.txt; do
    name="$(basename "$f" .txt)"
    total=$((total + 1))
    em="$(mktemp)"
    wide="$(env -u GIT_DIR bash "$ENGINE" --emit-meta -f tsv --max-strategies 1 "$f" 2>"$em")"
    strat="$(awk -F'\t' '/^__EXTRACT_META__/{s=$2} END{print s}' "$em")"; [[ -z "$strat" ]] && strat="(none)"
    rm -f "$em"
    t="$(_core_melt_tidy "$wide" 2>/dev/null || true)"
    c="$(printf '%s\n' "$t" | head -1 | awk -F'\t' '{print NF}')"; [[ -z "$c" ]] && c=0
    r=$(( $(printf '%s\n' "$t" | grep -c .) - 1 )); [[ $r -lt 0 ]] && r=0

    exp="$(awk -F'\t' -v n="$name" '$1==n{print $2"\t"$3"\t"$4; exit}' "$MANIFEST")"
    ekind="$(printf '%s' "$exp" | cut -f1)"; erows="$(printf '%s' "$exp" | cut -f2)"; emin="$(printf '%s' "$exp" | cut -f3)"
    ok=0
    if [[ "$ekind" == "table" ]]; then [[ "$r" -eq "$erows" && "$c" -ge "$emin" ]] && ok=1
    elif [[ "$ekind" == "kv" ]]; then [[ "$r" -ge 1 && "$c" -ge "$emin" ]] && ok=1
    else [[ "$c" -ge 2 && "$r" -ge 1 ]] && ok=1; fi

    tier="$(_tier "$strat")"
    if [[ $ok -eq 1 ]]; then
        mark="tidy"; pass=$((pass + 1)); TIER_COUNT[$tier]=$(( ${TIER_COUNT[$tier]:-0} + 1 ))
    else
        mark="FAIL"; fail=$((fail + 1)); FAILED+=("$name")
    fi
    printf '%-22s %-24s %-8s %6s  %s\n' "$name" "$strat" "$tier" "${c}x${r}" "$mark"
done

echo
echo "holdout: $pass/$total tidy on unseen output — generic ${TIER_COUNT[generic]:-0}, hint ${TIER_COUNT[hint]:-0}, bespoke ${TIER_COUNT[bespoke]:-0}"
[[ $fail -gt 0 ]] && echo "FAILED: ${FAILED[*]}"
[[ $fail -eq 0 ]]
