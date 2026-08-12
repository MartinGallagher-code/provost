#!/usr/bin/env bash
# tests/benchmark/make_doc_json.sh — build the benchmark workbook's input JSON.
#
# For every held-out benchmark input: the raw text, the DEFAULT parse melted to
# a real table, the `--multi` segmentation when it differs, and the rating from
# ratings.tsv. Feeds tests/benchmark/make_doc.js.
#
#   make_doc_json.sh -o FILE
#
# melt.sh is sourced ONCE and called in-process — a per-input melt in its own
# shell is what made the corpus version of this too slow to finish.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
ENGINE="$ROOT/extract/envoy-extract"

out=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o|--output) out="${2:?-o needs a path}"; shift 2 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done
[[ -n "$out" ]] || { echo "make_doc_json.sh: -o FILE is required" >&2; exit 2; }

# shellcheck source=/dev/null
source "$ROOT/transform/melt.sh"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/glean-benchjson.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

_json_str () {
    # JSON-escape stdin as one string literal. C0 control bytes are rewritten
    # to caret notation FIRST: they are legal in JSON but XML 1.0 forbids them
    # outright, escaped or not, so one ANSI colour code yields a .docx Word
    # refuses to open. That shipped once already.
    python3 -c '
import json, sys
s = sys.stdin.read()
out = []
for ch in s:
    o = ord(ch)
    if ch in "\t\n" or o >= 32:
        out.append(ch)
    elif o < 32:
        out.append("^" + chr(o + 64))
    else:
        out.append("^?")
sys.stdout.write(json.dumps("".join(out)))'
}

# name -> rating<TAB>multi<TAB>cluster<TAB>note
awk -F'\t' 'NF >= 5 && $1 !~ /^#/ { print }' "$HERE/ratings.tsv" > "$WORK/ratings.tsv"

# Melt a field stream to TSV rows, then emit them as a JSON array of arrays.
_emit_table () {
    local stream="$1" tidy rowi=0 ci fld
    printf '['
    tidy="$(_core_melt_tidy "${stream%$'\n'}" 2>/dev/null || true)"
    while IFS= read -r trow; do
        [[ -n "$trow" ]] || continue
        rowi=$((rowi + 1))
        [[ $rowi -gt 60 ]] && break
        [[ $rowi -eq 1 ]] || printf ','
        printf '['
        ci=0
        # `printf '%s\n'`, NOT `printf '%s'`: without the terminating newline
        # `read` returns non-zero on the final field and the loop body never
        # runs for it, so every table silently loses its LAST COLUMN.
        while IFS= read -r fld; do
            ci=$((ci + 1))
            [[ $ci -eq 1 ]] || printf ','
            printf '%s' "$(printf '%s' "$fld" | _json_str)"
        done < <(printf '%s\n' "$trow" | tr '\t' '\n')
        printf ']'
    done <<< "$tidy"
    printf ']'
}

rank=0
first=1
{
printf '[\n'
for f in "$HERE"/inputs/*.txt; do
    name="$(basename "$f" .txt)"
    rank=$((rank + 1))
    [[ $first -eq 1 ]] || printf ',\n'
    first=0

    rating="$(awk -F'\t' -v n="$name" '$1 == n { print $2 }' "$WORK/ratings.tsv")"
    multiv="$(awk -F'\t' -v n="$name" '$1 == n { print $3 }' "$WORK/ratings.tsv")"
    cluster="$(awk -F'\t' -v n="$name" '$1 == n { print $4 }' "$WORK/ratings.tsv")"
    note="$(awk -F'\t' -v n="$name" '$1 == n { print $5 }' "$WORK/ratings.tsv")"

    # --emit-meta writes its banner to STDERR, not into the field stream. Reading
    # it off stdout instead silently yields an empty strategy for every input,
    # and the document then reports all fifty as parsed by "none".
    body="$("$ENGINE" -f plain --max-strategies 1 --emit-meta <"$f" 2>"$WORK/meta")"
    meta="$(grep -m1 '^__EXTRACT_META__' "$WORK/meta" || true)"
    strat="$(printf '%s' "$meta" | cut -f2)"
    conf="$(printf '%s' "$meta" | cut -f3)"
    [[ "$conf" =~ ^[0-9]+$ ]] || conf=0

    printf '{"rank":%d,"name":%s,"rating":%s,"multi":%s,"cluster":%s,"note":%s,' \
        "$rank" \
        "$(printf '%s' "$name"        | _json_str)" \
        "$(printf '%s' "${rating:-?}" | _json_str)" \
        "$(printf '%s' "${multiv:-}"  | _json_str)" \
        "$(printf '%s' "${cluster:-}" | _json_str)" \
        "$(printf '%s' "${note:-}"    | _json_str)"

    printf '"strategy":%s,"conf":%d,' "$(printf '%s' "${strat:-none}" | _json_str)" "$conf"

    # Raw input, capped so one huge input cannot swamp the document.
    printf '"input":['
    ln=0
    while IFS= read -r line; do
        ln=$((ln + 1))
        [[ $ln -gt 45 ]] && { printf ',%s' "$(printf '%s' "… (input truncated)" | _json_str)"; break; }
        [[ $ln -eq 1 ]] || printf ','
        printf '%s' "$(printf '%s' "$line" | _json_str)"
    done < "$f"
    printf '],'

    printf '"table":'
    _emit_table "$body"

    # The --multi segmentation, but ONLY where the rating says it differs:
    # printing an identical second rendering for 47 of 50 inputs would bury
    # the three cases where segmentation is the story.
    printf ',"multi_datasets":['
    if [[ "$multiv" == "better" || "$multiv" == "worse" ]]; then
        wide="$("$ENGINE" -f plain --multi <"$f" 2>/dev/null)"
        di=0; cur=""; mstrat=""; mconf=""
        _flush_ds () {
            [[ -n "$mstrat" ]] || return 0
            di=$((di + 1))
            [[ $di -eq 1 ]] || printf ','
            printf '{"strategy":%s,"conf":%s,"table":' \
                "$(printf '%s' "$mstrat" | _json_str)" "${mconf:-0}"
            _emit_table "$cur"
            printf '}'
            cur=""
        }
        while IFS= read -r line; do
            if [[ "$line" == __DATASET__* ]]; then
                _flush_ds
                mstrat="$(printf '%s' "$line" | cut -f3)"
                mconf="$(printf '%s' "$line" | cut -f4)"
                [[ "$mconf" =~ ^[0-9]+$ ]] || mconf=0
                continue
            fi
            cur+="$line"$'\n'
        done <<< "$wide"
        _flush_ds
    fi
    printf ']}'
done
printf '\n]\n'
} > "$out"

printf 'wrote %s (%d inputs)\n' "$out" "$rank"
