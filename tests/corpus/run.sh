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
#   run.sh --full [ERE]    regression, FULL mode (PV-037): the path users get.
#                          Every input whose full-mode winner differs from the
#                          --generic one must be recorded in full-mode.tsv with
#                          that strategy and a reason; a recorded tidy one must
#                          still meet expected.tsv (rows, minimum columns), or
#                          the shape of its own the record gives; one recorded
#                          as not tidy where --generic is tidy is a known
#                          defect, listed by every run. Combines with --golden:
#                          run.sh --golden --full
#                          shares the generic pass (CI runs it that way when a
#                          pull request can change tidy output).
#   run.sh --update-full [ERE]
#                          (re)write full-mode.tsv from the current full mode,
#                          keeping each kept row's reason; a new row's reason
#                          is TODO, which --full refuses until it is written.
#   The optional ERE filters tool names, so an iterate loop can re-check only
#   what it touched: run.sh --golden '^iostat'  (counts then cover that set).
#   PROVOST_CORPUS_COMMANDS=1 gives the full pass each input's command, as
#   `provost run` does (--command, from the input's name: _corpus_cmd).
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

# The record of full mode's own winners (PV-037): name, strategy, tidy, reason.
FULLREC="$HERE/full-mode.tsv"

mode="report" full_check=0 full_update=0 FILTER=""
# An ERE filter on tool names (the argument that is not a mode), so an iterate
# loop can re-run only the tools it touched (`run.sh --golden '^iostat'`)
# instead of all 3,700. Pass/fail counts then cover only the filtered set — the
# summary says so.
for _a in "$@"; do
    case "$_a" in
        --golden)        mode="golden" ;;
        --update-golden) mode="update" ;;
        --coverage)      mode="coverage" ;;
        --full)          full_check=1 ;;
        --update-full)   full_update=1 ;;
        *)               FILTER="$_a" ;;
    esac
done
if (( full_check || full_update )) && [[ "$mode" == report ]]; then mode="full"; fi
if [[ "$mode" != golden && "$mode" != full ]] && (( full_check || full_update )); then
    echo "run.sh: --full / --update-full combine with --golden only" >&2; exit 2
fi
[[ "$mode" == "update" ]] && mkdir -p "$EXP"

# Full mode is only needed to show the full-mode winner (report), bespoke
# coverage (coverage) or the full-mode check. Skip it for golden/update alone
# to halve the engine calls.
need_full=0
[[ "$mode" == "report" || "$mode" == "coverage" ]] && need_full=1
(( full_check || full_update )) && need_full=1

# _corpus_cmd NAME — the command an input's name stands for, as `provost run`
# would pass it to the engine (PROVOST_CORPUS_COMMANDS=1): the name's first
# word, or its first two for a command whose own name has a hyphen. The
# adversarial round's mechanism prefixes (exo-, quo-, tbl- ...) are dropped
# first, and a /proc file (proc-...) is read with cat, a relay.
_corpus_cmd () {
    local n="$1" two
    case "$n" in quo-*|uni-*|tbl-*|num-*|nst-*|exo-*|enc-*|cmb-*) n="${n#*-}" ;; esac
    case "$n" in proc-*) printf 'cat'; return 0 ;; esac
    two="$(printf '%s' "$n" | cut -d- -f1-2)"
    case "$two" in
        pkg-config|nvidia-smi|rocm-smi|apt-get|apt-cache|apt-mark|docker-compose|\
        systemd-analyze|systemd-cgls|systemd-cgtop|systemd-tmpfiles|systemd-resolve|\
        systemd-detect|ssh-keyscan|ssh-keygen|ssh-add|decode-dimms|dpkg-query|\
        update-alternatives|ceph-volume|radosgw-admin|lsb-release|xfs-info|xfs-db|\
        git-annex|iptables-save|ip6tables-save|nft-monitor|mx-check|mx-summarize)
            printf '%s' "$two" ;;
        *)  printf '%s' "${n%%-*}" ;;
    esac
}

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

    # Precomputed by the batch phase, or (when the batch left no record) one
    # generic call: wide on stdout, meta on stderr.
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

    # Optional full-mode result (report/coverage): precomputed by the batch
    # phase like the generic one, or one call when the batch left no record.
    local fstrat="(none)" fconf=0 fc=0 fr=0 ftop="" fraw=""
    if [[ $need_full -eq 1 ]]; then
        local fwide
        if [[ -n "$PRE_FULL" && -f "$PRE_FULL/$name.meta" ]]; then
            fwide="$(cat "$PRE_FULL/$name.wide" 2>/dev/null || true)"
            IFS=$'\t' read -r _ fstrat fconf _ < "$PRE_FULL/$name.meta" || true
        else
            local -a fcmd=()
            [[ "$FULL_CMDS" == 1 ]] && fcmd=(--command "$(_corpus_cmd "$name")")
            fwide="$(env -u GIT_DIR bash "$ENGINE" ${fcmd[@]+"${fcmd[@]}"} --emit-meta -f tsv --max-strategies 1 "$f" 2>"$em")"
            fstrat="$(awk -F'\t' '/^__EXTRACT_META__/{s=$2} END{print s}' "$em")"
            fconf="$(awk -F'\t' '/^__EXTRACT_META__/{c=$3} END{print c+0}' "$em")"
        fi
        [[ -z "$fstrat" ]] && fstrat="(none)"
        [[ -z "$fconf" ]] && fconf=0
        read -r fc fr <<< "$(_melt_dims "$fwide")"
        # with PROVOST_CORPUS_COMMANDS=1: what ranked first with the command's
        # name and without it (the engine's __COMMAND_META__ line)
        if [[ "$FULL_CMDS" == 1 ]]; then
            local cmf="$em"
            [[ -n "$PRE_FULL" && -f "$PRE_FULL/$name.meta" ]] && cmf="$PRE_FULL/$name.meta"
            IFS=$'\t' read -r _ _ _ ftop fraw < <(grep '^__COMMAND_META__' "$cmf" 2>/dev/null || echo) || true
        fi
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
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$name" "$gstrat" "$gconf" "$gc" "$gr" "$fstrat" "$fconf" "$fc" "$fr" \
        "$gtidy_ok" "$ftidy_ok" "${ftop:--}" "${fraw:--}" > "$WORK/$name.rec"
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

# --- batch extraction fast path --------------------------------------------
# One engine process per job slot handles a whole chunk of inputs via
# `--batch --batch-out`, so the ~260-file strategy tree is read and parsed
# JOBS times per run instead of once per input. Workers then consume the
# precomputed .wide/.meta files (PRE_DIR, and PRE_FULL for the full-mode
# result report/coverage also need) instead of spawning the engine per input.
# (coverage used to spawn twice per input and took over an hour; any input a
# batch leaves without a record falls back to the per-input call.)
_batch_pass () { # $1=out dir, $2=1 to give each input its command, rest=engine mode flags
    local _out="$1" _cmds="$2" _chunk=0; shift 2
    local -a _cmdflag=()
    [[ "$_cmds" == 1 ]] && _cmdflag=(--batch-commands)
    mkdir -p "$_out"
    while [[ $_chunk -lt $JOBS ]]; do
        (
            _i=$_chunk
            while [[ $_i -lt ${#INPUTS[@]} ]]; do
                if [[ "$_cmds" == 1 ]]; then
                    printf '%s\t%s\n' "${INPUTS[$_i]}" "$(_corpus_cmd "$(basename "${INPUTS[$_i]}" .txt)")"
                else
                    printf '%s\n' "${INPUTS[$_i]}"
                fi
                _i=$((_i + JOBS))
            done | env -u GIT_DIR bash "$ENGINE" --batch --batch-out "$_out" \
                       ${_cmdflag[@]+"${_cmdflag[@]}"} "$@" -f tsv --max-strategies 1 2>/dev/null
        ) &
        _chunk=$((_chunk + 1))
    done
    wait
}
FULL_CMDS=0
[[ "${PROVOST_CORPUS_COMMANDS:-0}" == 1 ]] && FULL_CMDS=1
PRE_DIR="$WORK/pre"
_batch_pass "$PRE_DIR" 0 --generic
PRE_FULL=""
if [[ $need_full -eq 1 ]]; then
    PRE_FULL="$WORK/pre-full"
    _batch_pass "$PRE_FULL" "$FULL_CMDS"
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

# --- the full-mode record (PV-037) ------------------------------------------
# full-mode.tsv: one row per input whose full-mode winner is not --generic's:
#   name <TAB> strategy <TAB> tidy (yes|no) <TAB> reason
declare -A FR_STRAT=() FR_TIDY=() FR_REASON=() FR_SEEN=()
if [[ -f "$FULLREC" ]]; then
    while IFS=$'\t' read -r _n _st _td _rs; do
        [[ -z "$_n" || "$_n" == \#* ]] && continue
        FR_STRAT[$_n]="$_st"; FR_TIDY[$_n]="${_td:-}"; FR_REASON[$_n]="${_rs:-}"
    done < "$FULLREC"
fi
fpass=0; ffail=0; fskip=0; fdiff=0; fnote=0
declare -a FFAILED=() FDIFF=() FNEW=() FDEFECT=()
declare -A FBY=()
# _full_check — the full-mode verdict on one input (the loop's record fields).
_full_check () {
    local rs="${FR_STRAT[$name]-}" rt="${FR_TIDY[$name]-}" rr="${FR_REASON[$name]-}" why=""
    [[ -n "${FR_STRAT[$name]+x}" ]] && FR_SEEN[$name]=1
    if [[ "$fstrat" != "$gstrat" ]]; then
        fdiff=$((fdiff + 1)); FBY[$fstrat]=$(( ${FBY[$fstrat]:-0} + 1 ))
        FDIFF+=("$(printf '  %-34s full %-24s generic %-20s %s' "$name" "$fstrat" "$gstrat" "${rr:-(no reason recorded)}")")
        if [[ -z "$rs" ]]; then why="full mode uses '$fstrat' where --generic uses '$gstrat', and full-mode.tsv does not record it (run.sh --update-full, then write the reason)"
        elif [[ "$rs" != "$fstrat" ]]; then why="full mode now uses '$fstrat'; full-mode.tsv records '$rs'"
        elif [[ -z "$rr" || "$rr" == TODO* ]]; then why="full-mode.tsv has no reason for '$fstrat' here"
        elif [[ "$rt" =~ ^([0-9]+),([0-9]+)$ ]]; then
            # a deliberate shape of its own: exactly R rows, at least C columns
            (( fr == BASH_REMATCH[1] && fc >= BASH_REMATCH[2] )) \
                || why="full mode ('$fstrat', ${fc}x${fr}) no longer has its recorded shape (${BASH_REMATCH[1]} rows, >=${BASH_REMATCH[2]} columns)"
        elif [[ "$rt" == yes && "$ftidy_ok" -ne 1 ]]; then why="full mode ('$fstrat', ${fc}x${fr}) no longer meets expected.tsv ($want)"
        elif [[ "$rt" == no && "$ftidy_ok" -eq 1 ]]; then
            fnote=$((fnote + 1)); echo "note $name — full mode ('$fstrat') now meets expected.tsv: mark it tidy in full-mode.tsv"
        elif [[ "$rt" == no && "$gtidy_ok" -eq 1 ]]; then
            FDEFECT+=("$name ($fstrat)")
        elif [[ "$rt" != yes && "$rt" != no ]]; then why="full-mode.tsv's tidy column for it is '$rt' (yes, no, or ROWS,COLS)"
        fi
    else
        if [[ -n "$rs" ]]; then why="full-mode.tsv records '$rs', but full mode now uses --generic's winner '$fstrat' (drop the row: run.sh --update-full)"
        elif [[ "$gtidy_ok" -eq 1 && "$ftidy_ok" -ne 1 ]]; then why="full mode ('$fstrat') breaks expected.tsv ($want)"
        elif [[ "$ftidy_ok" -ne 1 ]]; then fskip=$((fskip + 1)); return 0
        fi
    fi
    if [[ -n "$why" ]]; then
        echo "FULL FAIL $name — $why"; ffail=$((ffail + 1)); FFAILED+=("$name")
    else
        fpass=$((fpass + 1))
    fi
}
# _full_update_row — this input's row for the new full-mode.tsv (none when
# full mode agrees with --generic). A kept row keeps its reason.
_full_update_row () {
    [[ "$fstrat" != "$gstrat" ]] || return 0
    local td=no rr="TODO: why full mode uses this parser" ort="${FR_TIDY[$name]-}"
    (( ftidy_ok == 1 )) && td=yes
    (( ftidy_ok != 1 && gtidy_ok == 1 )) && rr="TODO: full mode breaks expected.tsv where --generic meets it: fix the parser, or say why"
    if [[ "${FR_STRAT[$name]-}" == "$fstrat" && -n "${FR_REASON[$name]-}" ]]; then
        rr="${FR_REASON[$name]}"
        # a recorded shape of its own is kept while full mode still has it
        if [[ "$ort" =~ ^([0-9]+),([0-9]+)$ ]] && (( fr == BASH_REMATCH[1] && fc >= BASH_REMATCH[2] )); then td="$ort"; fi
    else FNEW+=("$name"); fi
    printf '%s\t%s\t%s\t%s\n' "$name" "$fstrat" "$td" "$rr" >> "$WORK/full-mode.new"
}
: > "$WORK/full-mode.new"

for rec in "$WORK"/*.rec; do
    [[ -f "$rec" ]] || continue
    total=$((total + 1))
    IFS=$'\t' read -r name gstrat gconf gc gr fstrat fconf fc fr gtidy_ok ftidy_ok ftop fraw < "$rec"
    want="$(sed -n '2p' "$rec")"
    note=""
    [[ "$fstrat" != "$gstrat" && "$fstrat" != "(none)" ]] && { note="full uses bespoke '$fstrat'"; relies=$((relies + 1)); }
    [[ "$FULL_CMDS" == 1 && "$ftop" != "$fraw" ]] && note="${note:+$note; }command '$(_corpus_cmd "$name")' ranked '$ftop' first, not '$fraw'"
    (( full_check )) && _full_check
    (( full_update )) && _full_update_row

    case "$mode" in
      update)
        if [[ "$gtidy_ok" -eq 1 ]]; then cp "$WORK/$name.tidy" "$EXP/$name.tsv"; echo "golden: $name ($gc col x $gr row)"
        else rm -f "$EXP/$name.tsv"; echo "skip (not tidy yet): $name"; fi ;;
      full) ;;
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
if (( full_update )); then
    # Rows for inputs this run did not process (a filtered run) are kept.
    {
        echo "# Full mode's own winners (PV-037): every corpus input whose full-mode winner"
        echo "# differs from --generic's, written by \`tests/corpus/run.sh --update-full\` and"
        echo "# checked by \`run.sh --full\` (CI: \`run.sh --golden --full\`). A difference not"
        echo "# recorded here fails the check, so a tool-specific parser never wins silently."
        echo "#"
        echo "# name <TAB> strategy <TAB> tidy <TAB> reason"
        echo "#   strategy  full mode's winner (a strategy, or the hints.tsv tool that routed it)"
        echo "#   tidy      yes = it meets expected.tsv, and must go on meeting it;"
        echo "#             ROWS,COLS = a deliberate shape of its own (exactly ROWS rows, at"
        echo "#             least COLS columns), which it must keep; no = it does not meet"
        echo "#             expected.tsv: a gap in both modes, or a KNOWN full-mode defect"
        echo "#             where --generic does (listed by every --full run)"
        echo "#   reason    why full mode may use it here (TODO until written: --full refuses)"
        {
            cat "$WORK/full-mode.new"
            if [[ -f "$FULLREC" ]]; then
                for _n in "${!FR_STRAT[@]}"; do
                    [[ -f "$WORK/$_n.rec" ]] && continue
                    printf '%s\t%s\t%s\t%s\n' "$_n" "${FR_STRAT[$_n]}" "${FR_TIDY[$_n]}" "${FR_REASON[$_n]}"
                done
            fi
        } | LC_ALL=C sort -t$'\t' -k1,1
    } > "$FULLREC.tmp" && mv "$FULLREC.tmp" "$FULLREC"
    echo "wrote full-mode.tsv: $(grep -vc '^#' "$FULLREC") recorded difference(s); ${#FNEW[@]} new (reason TODO)${FILTER:+ [filter: $FILTER]}"
    (( ${#FNEW[@]} )) && echo "write a reason for: ${FNEW[*]}"
fi
if (( full_check )); then
    # A recorded row whose input this run processed but no longer differs was
    # caught per input; one whose input is gone from the corpus is caught here.
    if [[ -z "$FILTER" ]]; then
        for _n in "${!FR_STRAT[@]}"; do
            [[ -n "${FR_SEEN[$_n]-}" || -f "$IN/$_n.txt" ]] && continue
            echo "FULL FAIL $_n — full-mode.tsv records an input the corpus no longer has"
            ffail=$((ffail + 1)); FFAILED+=("$_n")
        done
    fi
    echo "full mode differs from --generic on $fdiff input(s) — recorded in full-mode.tsv, by strategy:"
    for _s in "${!FBY[@]}"; do printf '%s\t%s\n' "${FBY[$_s]}" "$_s"; done | LC_ALL=C sort -t$'\t' -k1,1nr -k2,2 \
        | awk -F'\t' '{ line = line (NR > 1 ? ", " : "  ") $2 " " $1 } END { if (line != "") print line }'
    if [[ "${PROVOST_CORPUS_LIST:-1}" == 1 && ${#FDIFF[@]} -gt 0 ]]; then
        echo "each one (name, full mode's winner, --generic's, the recorded reason):"
        printf '%s\n' "${FDIFF[@]}" | LC_ALL=C sort
    fi
    if (( ${#FDEFECT[@]} )); then
        echo "known full-mode defects (recorded 'no' in full-mode.tsv; --generic meets expected.tsv): ${FDEFECT[*]}"
    fi
    echo "full-mode check: $fpass passed, $ffail failed, $fskip not-yet-covered (neither mode meets expected.tsv) of $total${FILTER:+ [filter: $FILTER]}"
    [[ $ffail -gt 0 ]] && echo "full-mode failures: ${FFAILED[*]}"
    (( ffail > 0 )) && fail=$((fail + ffail))
fi
[[ "${fail:-0}" -eq 0 ]]
