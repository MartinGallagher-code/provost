#!/usr/bin/env bash
# tests/corpus/make_multi_json.sh — build the review workbook's input JSON.
#
# Walks the corpus for inputs that split into MORE THAN ONE dataset under
# `glean --multi`, and emits, for each, the raw input plus every dataset melted
# to a real table — which is what the workbook renders. The first version of
# this was a scratch file that shipped strategy NAMES instead of tables,
# because a per-dataset melt in its own shell timed out; melt.sh is sourced
# ONCE here and called in-process, which is what makes the full run finish.
#
#   make_multi_json.sh -o FILE [-n N] [--marks F]...
#
#   -n N       stop after N multi-dataset inputs (default 100; 0 = all)
#   --marks F  a review-marks TSV whose verdicts get stamped onto the entries
#              so a re-issued workbook never asks for a mark twice. Repeatable.
#
# Output feeds tests/corpus/make_multi_doc.js.
#
# WHY THIS IS BATCHED AND PARALLEL. A `--multi` call costs ~4s against ~0.1s
# for an ordinary parse, because it extracts FOUR candidate segmentations and
# each one re-runs detection over every strategy. Only about one corpus input
# in nine actually splits, so finding 100 means calling it on ~900 inputs —
# over an hour serially. The scan therefore runs a batch of inputs at a time
# through xargs -P, alphabetically, and stops as soon as enough have been
# found, so no more of the corpus is scanned than the answer needs.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
ENGINE="$ROOT/extract/envoy-extract"
IN="$HERE/inputs"

out=""; want=100
marks_files=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o|--output) out="${2:?-o needs a path}"; shift 2 ;;
        -n)          want="${2:?-n needs a number}"; shift 2 ;;
        --marks)     marks_files+=("${2:?--marks needs a path}"); shift 2 ;;
        -h|--help)   sed -n '2,18p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done
[[ -n "$out" ]] || { echo "make_multi_json.sh: -o FILE is required" >&2; exit 2; }

# shellcheck source=/dev/null
source "$ROOT/transform/melt.sh"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/glean-multijson.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# Prior marks: name -> "verdict<TAB>note", so a re-issue can stamp them.
: > "$WORK/marks.tsv"
for mf in "${marks_files[@]+"${marks_files[@]}"}"; do
    [[ -f "$mf" ]] || continue
    awk -F'\t' 'NF >= 2 && $1 !~ /^#/ && $1 != "name" { print }' "$mf" >> "$WORK/marks.tsv"
done

_json_str () {
    # JSON-escape stdin as one string literal (no trailing newline).
    #
    # C0 CONTROL BYTES ARE REWRITTEN TO CARET NOTATION FIRST. They are legal in
    # JSON as , and the workbook renderer passes them straight through —
    # but XML 1.0 forbids them outright, ESCAPED OR NOT, so a single ANSI colour
    # code anywhere in a raw corpus input yields a .docx that Word refuses to
    # open. Caret notation also happens to be what a reviewer wants to see:
    # `^[[0;32m` says "this input carries colour codes", which is part of what
    # the parse has to cope with.
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

# --- scan phase: find the inputs that split, in parallel, a batch at a time --
JOBS="${GLEAN_CORPUS_JOBS:-$(nproc 2>/dev/null || echo 4)}"
BATCH="${GLEAN_MULTI_BATCH:-300}"
mkdir -p "$WORK/wide"

_scan_one () {
    local f="$1" name
    name="$(basename "$f" .txt)"
    timeout 60 bash "$ENGINE" --multi -f tsv --max-strategies 1 "$f" 2>/dev/null \
        > "$WORK/wide/$name.wide" || true
    if [[ "$(grep -c '^__DATASET__' "$WORK/wide/$name.wide" 2>/dev/null || echo 0)" -le 1 ]]; then
        rm -f "$WORK/wide/$name.wide"
    fi
}
export -f _scan_one
export ENGINE WORK

all=()
while IFS= read -r f; do all+=("$f"); done < <(ls "$IN"/*.txt | sort)
total=${#all[@]}
hits=(); off=0
while [[ $off -lt $total ]]; do
    if [[ $want -gt 0 && ${#hits[@]} -ge $want ]]; then break; fi
    printf '%s\n' "${all[@]:$off:$BATCH}" \
        | xargs -P "$JOBS" -I{} bash -c '_scan_one "$@"' _ {} 2>/dev/null
    off=$((off + BATCH))
    hits=()
    for f in "${all[@]:0:$off}"; do
        n="$(basename "$f" .txt)"
        [[ -f "$WORK/wide/$n.wide" ]] && hits+=("$f")
    done
    echo "  scanned $off/$total inputs — ${#hits[@]} split into multiple datasets" >&2
done

# --- emit phase: melt each hit in-process (cheap next to the scan) -----------
emitted=0
first=1
{
printf '[\n'
for f in "${hits[@]+"${hits[@]}"}"; do
    [[ $want -gt 0 && $emitted -ge $want ]] && break
    name="$(basename "$f" .txt)"
    wide="$(cat "$WORK/wide/$name.wide")"
    nds="$(printf '%s\n' "$wide" | grep -c '^__DATASET__')"

    emitted=$((emitted + 1))
    [[ $first -eq 1 ]] || printf ',\n'
    first=0

    printf '{"rank":%d,"name":%s,"n":%d,' "$emitted" "$(printf '%s' "$name" | _json_str)" "$nds"

    # Raw input, capped so one huge input cannot swamp the document.
    printf '"input":['
    ln=0
    while IFS= read -r line; do
        ln=$((ln + 1))
        [[ $ln -gt 40 ]] && { printf ',%s' "$(printf '%s' "… (input truncated)" | _json_str)"; break; }
        [[ $ln -eq 1 ]] || printf ','
        printf '%s' "$(printf '%s' "$line" | _json_str)"
    done < "$f"
    printf '],'

    # Each dataset: its separator line carries index/strategy/confidence, and
    # the wide block after it melts to the table the reviewer actually reads.
    printf '"datasets":['
    di=0
    cur=""; strat=""; conf=""
    _flush_ds () {
        [[ -n "$strat" ]] || return 0
        di=$((di + 1))
        [[ $di -eq 1 ]] || printf ','
        printf '{"strategy":%s,"conf":%s,"table":[' \
            "$(printf '%s' "$strat" | _json_str)" "${conf:-0}"
        local tidy rowi=0
        tidy="$(_core_melt_tidy "${cur%$'\n'}" 2>/dev/null || true)"
        while IFS= read -r trow; do
            [[ -n "$trow" ]] || continue
            rowi=$((rowi + 1))
            [[ $rowi -gt 60 ]] && break
            [[ $rowi -eq 1 ]] || printf ','
            printf '['
            local ci=0 fld
            while IFS= read -r fld; do
                ci=$((ci + 1))
                [[ $ci -eq 1 ]] || printf ','
                printf '%s' "$(printf '%s' "$fld" | _json_str)"
            # `printf '%s\n'`, NOT `printf '%s'`: without the terminating
            # newline `read` returns non-zero on the final field and the loop
            # body never runs for it, so EVERY table silently lost its LAST
            # COLUMN. That shipped, and the reviewer duly marked half a dozen
            # tools as "missing data" that were parsing perfectly.
            done < <(printf '%s\n' "$trow" | tr '\t' '\n')
            printf ']'
        done <<< "$tidy"
        printf ']}'
        cur=""
    }
    while IFS= read -r line; do
        if [[ "$line" == __DATASET__* ]]; then
            _flush_ds
            strat="$(printf '%s' "$line" | cut -f3)"
            conf="$(printf '%s' "$line" | cut -f4)"
            [[ "$conf" =~ ^[0-9]+$ ]] || conf=0
            continue
        fi
        cur+="$line"$'\n'
    done <<< "$wide"
    _flush_ds
    printf '],'

    prior="$(awk -F'\t' -v n="$name" '$1 == n { print $2 "\t" $3; exit }' "$WORK/marks.tsv")"
    if [[ -n "$prior" ]]; then
        pv="${prior%%$'\t'*}"; pn="${prior#*$'\t'}"
        # Marks are recorded as `OK=x` / `FormatOff=x` / `Horrible=x`.
        pv="${pv%%=*}"
        printf '"prior":%s,"priornote":%s' \
            "$(printf '%s' "$pv" | _json_str)" "$(printf '%s' "$pn" | _json_str)"
    else
        printf '"prior":null,"priornote":null'
    fi
    printf '}'
done
printf '\n]\n'
} > "$out"

echo "wrote $out — $emitted multi-dataset inputs"
