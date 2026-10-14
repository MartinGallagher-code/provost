#!/usr/bin/env bash
# tests/corpus/run.sh — batch tidy-coverage harness for common tool outputs.
#
# For every input under inputs/, run the extract engine in --generic mode (only
# the fundamental parsers) and, when needed, full mode (all strategies), melt the
# result to tidy TSV, and report whether each tool's output comes out tidy.
#
# The point of the corpus: prove that a MINIMAL set of generic strategies can
# tidy the common Linux tool outputs, without a bespoke strategy per tool.
# Generic mode = the format-level parsers (strategies/delimited/ + structured/)
# plus declarative hint rows (extract/hints.tsv). Coverage distinguishes:
#   ✅  tidied by a generic parser via auto-detection (no per-tool anything)
#   ✅ʰ tidied by a generic parser routed by a hints.tsv data row
#   ✅ᵇ tidied only in full mode by a bespoke per-tool strategy script
#
# Modes:
#   run.sh                 report table + summary (development view)
#   run.sh --coverage      markdown coverage table (regenerates COVERAGE.md)
#   run.sh --golden [ERE]   regression: diff generic tidy output vs expected/<name>.tsv
#   run.sh --update-golden [ERE]
#                          (re)write expected/<name>.tsv from current generic output
#   The optional ERE filters tool names, so an iterate loop can re-check only
#   what it touched: run.sh --golden '^iostat'  (counts then cover that set).
#
# Speed: each tool is processed in parallel (job pool sized to the CPU count),
# and each engine invocation uses --emit-meta so the wide output (stdout) and the
# winning-strategy meta (stderr) come from ONE call. Full mode is only run for the
# report/coverage views that need it.
set -u
# Goldens are frozen byte-for-byte, and a few parsers (tree glyphs, check
# marks) measure widths in characters under a UTF-8 locale but in bytes under
# C. Pin the locale so the gate means the same thing on every machine and CI
# runner; the goldens were generated under C.
export LC_ALL=C

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
ENGINE="$ROOT/extract/provost-extract"
IN="$HERE/inputs"
EXP="$HERE/expected"
MANIFEST="$HERE/expected.tsv"
# shellcheck source=/dev/null
source "$ROOT/transform/melt.sh"

mode="${1:-report}"
[[ "$mode" == "--golden" ]] && mode="golden"
[[ "$mode" == "--update-golden" ]] && mode="update"
[[ "$mode" == "--coverage" ]] && mode="coverage"
[[ "$mode" == "update" ]] && mkdir -p "$EXP"

# Optional 2nd arg: an ERE filter on tool names, so an iterate loop can re-run
# only the tools it touched (`run.sh --golden '^iostat'`) instead of all 3705.
# Pass/fail counts then cover only the filtered set — the summary says so.
FILTER="${2:-}"

# Full mode is only needed to show the full-mode winner (report) or bespoke
# coverage (coverage). Skip it for golden/update to halve the engine calls.
need_full=0
[[ "$mode" == "report" || "$mode" == "coverage" ]] && need_full=1

JOBS="${PROVOST_CORPUS_JOBS:-$(nproc 2>/dev/null || echo 4)}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/provost-corpus.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# Melt a wide extract and echo "<cols> <rows>".
_melt_dims () {
    local t; t="$(_core_melt_tidy "$1" 2>/dev/null || true)"
    local c r
    c="$(printf '%s\n' "$t" | head -1 | awk -F'\t' '{print NF}')"; [[ -z "$c" ]] && c=0
    r=$(( $(printf '%s\n' "$t" | grep -c .) - 1 )); [[ $r -lt 0 ]] && r=0
    printf '%s %s' "$c" "$r"
}

# Worker: process one input, write a result record + its generic tidy output.
_worker () {
    local f="$1" name; name="$(basename "$f" .txt)"
    local em="$WORK/$name.err"

    # Precomputed by the batch phase (golden/update), or one generic call
    # (report/coverage): wide on stdout, meta on stderr.
    local gwide gstrat="" gconf=0
    if [[ -n "$PRE_DIR" && -f "$PRE_DIR/$name.meta" ]]; then
        gwide="$(cat "$PRE_DIR/$name.wide" 2>/dev/null || true)"
        IFS=$'\t' read -r _ gstrat gconf _ < "$PRE_DIR/$name.meta" || true
        [[ -z "$gstrat" ]] && gstrat="(none)"
        [[ -z "$gconf" ]] && gconf=0
    else
        gwide="$(env -u GIT_DIR bash "$ENGINE" --generic --emit-meta -f tsv --max-strategies 1 "$f" 2>"$em")"
        gstrat="$(awk -F'\t' '/^__EXTRACT_META__/{s=$2;c=$3} END{print s}' "$em")"; [[ -z "$gstrat" ]] && gstrat="(none)"
        gconf="$(awk -F'\t' '/^__EXTRACT_META__/{c=$3} END{print c+0}' "$em")"
    fi
    local gtidy; gtidy="$(_core_melt_tidy "$gwide" 2>/dev/null || true)"
    printf '%s\n' "$gtidy" > "$WORK/$name.tidy"
    local gc gr; read -r gc gr <<< "$(_melt_dims "$gwide")"

    # Optional full-mode call.
    local fstrat="(none)" fconf=0 fc=0 fr=0
    if [[ $need_full -eq 1 ]]; then
        local fwide
        fwide="$(env -u GIT_DIR bash "$ENGINE" --emit-meta -f tsv --max-strategies 1 "$f" 2>"$em")"
        fstrat="$(awk -F'\t' '/^__EXTRACT_META__/{s=$2} END{print s}' "$em")"; [[ -z "$fstrat" ]] && fstrat="(none)"
        fconf="$(awk -F'\t' '/^__EXTRACT_META__/{c=$3} END{print c+0}' "$em")"
        read -r fc fr <<< "$(_melt_dims "$fwide")"
    fi

    # Manifest expectation.
    local exp ekind erows emin
    exp="$(awk -F'\t' -v n="$name" '$1==n{print $2"\t"$3"\t"$4; exit}' "$MANIFEST")"
    ekind="$(printf '%s' "$exp" | cut -f1)"; erows="$(printf '%s' "$exp" | cut -f2)"; emin="$(printf '%s' "$exp" | cut -f3)"

    local gtidy_ok=0 ftidy_ok=0 want
    # `text`'s min-col bound was silently ignored (hardcoded >=2 regardless of
    # the manifest's recorded `emin`) -- a garbled parse that happened to clear
    # 2 columns passed even when the manifest asked for many more. Honor emin
    # here too (falling back to the >=2 floor only when the manifest genuinely
    # has no column expectation, i.e. emin=='-' -- free text like ASCII art).
    _ok () { # $1=cols $2=rows
        if [[ "$ekind" == "table" ]]; then [[ "$2" -eq "$erows" && "$1" -ge "$emin" ]]
        elif [[ "$ekind" == "kv" ]]; then [[ "$2" -ge 1 && "$1" -ge "$emin" ]]
        elif [[ "$emin" != "-" ]]; then [[ "$1" -ge "$emin" && "$2" -ge 1 ]]
        else [[ "$1" -ge 2 && "$2" -ge 1 ]]; fi
    }
    case "$ekind" in
        table) want="=${erows}r,>=${emin}c" ;;
        kv)    want=">=1r,>=${emin}c" ;;
        *)     if [[ "$emin" != "-" ]]; then want=">=1r,>=${emin}c"; else want="(unlisted)"; fi ;;
    esac
    _ok "$gc" "$gr" && gtidy_ok=1
    _ok "$fc" "$fr" && ftidy_ok=1

    # Result record (tab-separated).
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$name" "$gstrat" "$gconf" "$gc" "$gr" "$fstrat" "$fconf" "$fc" "$fr" \
        "$gtidy_ok" "$ftidy_ok" > "$WORK/$name.rec"
    printf '%s\n' "$want" >> "$WORK/$name.rec"
}

# --- build the (possibly filtered) input list ------------------------------
INPUTS=()
for f in "$IN"/*.txt; do
    if [[ -n "$FILTER" ]]; then
        _fname="$(basename "$f" .txt)"
        [[ "$_fname" =~ $FILTER ]] || continue
    fi
    INPUTS+=("$f")
done

# --- batch extraction fast path (golden / update) --------------------------
# One engine process per job slot handles a whole chunk of inputs via
# `--batch --batch-out`, so the ~200-file strategy tree is read and parsed
# JOBS times per run instead of once per input. Workers then consume the
# precomputed .wide/.meta files (PRE_DIR) instead of spawning the engine.
# report/coverage keep the per-input spawn: they need a second full-mode
# call per input anyway and are not the CI hot path.
PRE_DIR=""
if [[ "$mode" == "golden" || "$mode" == "update" ]]; then
    PRE_DIR="$WORK/pre"
    mkdir -p "$PRE_DIR"
    _chunk=0
    while [[ $_chunk -lt $JOBS ]]; do
        (
            _i=$_chunk
            while [[ $_i -lt ${#INPUTS[@]} ]]; do
                printf '%s\n' "${INPUTS[$_i]}"
                _i=$((_i + JOBS))
            done | env -u GIT_DIR bash "$ENGINE" --batch --batch-out "$PRE_DIR" \
                       --generic -f tsv --max-strategies 1 2>/dev/null
        ) &
        _chunk=$((_chunk + 1))
    done
    wait
fi

# --- fan out over inputs with a bounded job pool ---------------------------
for f in "${INPUTS[@]}"; do
    _worker "$f" &
    while [[ "$(jobs -r | wc -l)" -ge "$JOBS" ]]; do wait -n 2>/dev/null || break; done
done
wait

# --- aggregate + render (deterministic order) ------------------------------
pass=0; fail=0; total=0; relies=0; besp=0; hint=0; skip=0
declare -a FAILED

# Coverage is the queryable record: write it to COVERAGE.md (and still echo to
# the terminal) so the committed file can never silently drift from the live
# result — `run.sh --coverage` alone regenerates it, no manual redirect needed.
if [[ "$mode" == "coverage" ]]; then exec > >(tee "$HERE/COVERAGE.md"); fi

if [[ "$mode" == "report" ]]; then
    printf '%-16s %-18s %-18s %6s %-6s %s\n' 'TOOL' 'FULL(conf)' 'GENERIC(conf)' 'CxR' 'TIDY' 'NOTE'
    printf '%s\n' "--------------------------------------------------------------------------------"
elif [[ "$mode" == "coverage" ]]; then
    echo "# provost — common-tool tidy coverage"; echo
    echo "Generated by \`tests/corpus/run.sh --coverage\`. ✅ = tidied by a **generic**"
    echo "parser (auto-detected, no per-tool rule); ✅ʰ = tidied by a generic parser"
    echo "routed by a **hint row** (one data line in \`extract/hints.tsv\`); ✅ᵇ ="
    echo "tidied by a **bespoke** strategy script; ⏳ = not yet tidy."; echo
    echo "| Tool | Covered | Parser |"; echo "|---|:---:|---|"
fi

# Map hint tool names -> target strategy (for the ✅ʰ tier in coverage mode).
HINTS_TSV="$ROOT/extract/hints.tsv"
_hint_target () { # $1=winner name; echoes target strategy or nothing
    [[ -f "$HINTS_TSV" ]] || return 0
    awk -F'\t' -v n="$1" '$1==n && $1 !~ /^#/ {print $4; exit}' "$HINTS_TSV"
}

for rec in "$WORK"/*.rec; do
    [[ -f "$rec" ]] || continue
    total=$((total + 1))
    IFS=$'\t' read -r name gstrat gconf gc gr fstrat fconf fc fr gtidy_ok ftidy_ok < "$rec"
    want="$(sed -n '2p' "$rec")"
    note=""
    [[ "$fstrat" != "$gstrat" && "$fstrat" != "(none)" ]] && { note="full uses bespoke '$fstrat'"; relies=$((relies + 1)); }

    case "$mode" in
      update)
        if [[ "$gtidy_ok" -eq 1 ]]; then cp "$WORK/$name.tidy" "$EXP/$name.tsv"; echo "golden: $name ($gc col x $gr row)"
        else rm -f "$EXP/$name.tsv"; echo "skip (not tidy yet): $name"; fi ;;
      golden)
        if [[ ! -f "$EXP/$name.tsv" ]]; then skip=$((skip + 1))
        elif diff -q "$WORK/$name.tidy" "$EXP/$name.tsv" >/dev/null 2>&1; then pass=$((pass + 1))
        else echo "FAIL $name — differs from golden"; fail=$((fail + 1)); FAILED+=("$name"); fi ;;
      report)
        local_mark="FAIL"; if [[ "$gtidy_ok" -eq 1 ]]; then local_mark="tidy"; pass=$((pass + 1)); else fail=$((fail + 1)); FAILED+=("$name"); fi
        [[ -n "$note" ]] && note="want $want | $note" || note="want $want"
        printf '%-16s %-18s %-18s %6s %-6s %s\n' "$name" "$fstrat($fconf)" "$gstrat($gconf)" "${gc}x${gr}" "$local_mark" "$note" ;;
      coverage)
        if [[ "$gtidy_ok" -eq 1 ]]; then
            htarget="$(_hint_target "$gstrat")"
            if [[ -n "$htarget" ]]; then mark="✅ʰ"; parser="$htarget (hint: $gstrat)"; hint=$((hint + 1))
            else mark="✅"; parser="$gstrat"; pass=$((pass + 1)); fi
        elif [[ "$ftidy_ok" -eq 1 ]]; then mark="✅ᵇ"; parser="$fstrat (bespoke)"; besp=$((besp + 1))
        else mark="⏳"; parser="—"; fail=$((fail + 1)); FAILED+=("$name"); fi
        printf '| %s | %s | %s |\n' "$name" "$mark" "$parser" ;;
    esac
done

echo
case "$mode" in
  update)   echo "wrote goldens to expected/ ($total tools processed)${FILTER:+ [filter: $FILTER]}" ;;
  golden)   echo "golden regression: $pass passed, $fail failed, $skip not-yet-covered of $total${FILTER:+ [filter: $FILTER]}" ;;
  report)   echo "generic-tidy: $pass/$total pass, $fail fail   |   $relies tool(s) currently rely on a bespoke strategy in full mode"
            [[ $fail -gt 0 ]] && echo "not tidy under --generic: ${FAILED[*]}" ;;
  coverage) echo "**Coverage: $((pass + hint + besp)) / $total** — ✅ $pass via a generic parser, ✅ʰ $hint via a hint row, ✅ᵇ $besp via a bespoke strategy."
            [[ $fail -gt 0 ]] && echo "⏳ not yet tidy: ${FAILED[*]}" ;;
esac
[[ "${fail:-0}" -eq 0 ]]
