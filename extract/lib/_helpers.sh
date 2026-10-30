#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Helper functions for provost-extract
##
## Pure-bash utility functions used by strategies and the engine.
## Dependencies: none (standalone)
################################################################################

# ENV-115: initialise clean_text cache slots at source time so nounset in
# provost-extract doesn't trip when a caller (e.g. stream mode) reaches
# clean_text() before _dispatch.sh's extract-path init runs.
_CLEAN_TEXT_CACHE="${_CLEAN_TEXT_CACHE:-}"
_CLEAN_TEXT_DONE="${_CLEAN_TEXT_DONE:-0}"
_CLEAN_TEXT_RESULT="${_CLEAN_TEXT_RESULT:-}"
_STRIPPED_LINE="${_STRIPPED_LINE:-}"
_FIELD_NAME="${_FIELD_NAME:-}"
_FIELD_VALUE="${_FIELD_VALUE:-}"

# Strip STRAT-name:N<tab> prefix from a line. Result in _STRIPPED_LINE.
strip_strat_prefix () {
    _STRIPPED_LINE="$1"
    case "$_STRIPPED_LINE" in
        STRAT-*$'\t'*) _STRIPPED_LINE="${_STRIPPED_LINE#*$'\t'}" ;;
    esac
}

# Strategy helper: check if text looks like JSON (starts with { or [).
# Available to strategies for quick rejection.
_is_json () {
    case "$1" in
        '{'*|'['*) return 0 ;;
    esac
    return 1
}

# Return 0 if the text repeats two or more DISTINCT top-level (unindented) "key:"
# names — the signature of a multi-record output (git log's Author/Date per
# commit, blank-line-separated records, multi-response HTTP headers). Single-record
# scalar formats (a YAML mapping, /proc/stat, a colon key/value listing) have
# unique top-level keys. The "two or more distinct" threshold avoids misfiring on
# a single record that merely nests one duplicate name (e.g. a WARC response whose
# `Content-Type` appears at both the WARC and HTTP layers). Generic scalar
# strategies use this to decline true multi-record input so it reaches the
# dedicated per-record strategy (which emits entry<N>/record<N> groups the capture
# tidy melt renders one row per record), instead of flattening every record into
# one wide row with duplicate columns.
_has_repeated_top_keys () {
    local _n
    _n=$(printf '%s\n' "$1" | grep -oE '^[A-Za-z][A-Za-z0-9_.-]*:' | sort | uniq -d | grep -c .)
    [[ "$_n" -ge 2 ]]
}

# Trim leading and trailing whitespace (spaces and tabs) from $1. Result in _TRIMMED.
_trim () {
    _TRIMMED="$1"
    while [[ "$_TRIMMED" == [' '$'\t']* ]]; do _TRIMMED="${_TRIMMED#[' '$'\t']}"; done
    while [[ "$_TRIMMED" == *[' '$'\t'] ]]; do _TRIMMED="${_TRIMMED%[' '$'\t']}"; done
}

# THE FIELD STREAM. Strategies emit one `name value` line per field: the NAME
# runs to the first space and the VALUE is everything after it, verbatim —
# _parse_field_line, the formatters (`-f tsv/json/csv/…`) and the tidy melt all
# split on that FIRST space only. So a value may carry spaces and must be
# emitted as-is; only NAMES need sanitising (a space in a name would move the
# split point). Use _clean_field for names and _clean_value for values.

# NAME sanitiser: trim + replace spaces with underscores. Result in _CLEANED.
_clean_field () {
    _trim "$1"
    _CLEANED="${_TRIMMED// /_}"
}

# VALUE sanitiser: trim the edges and keep every inner space exactly. A tab,
# CR or newline inside a value becomes one space — the field stream is
# line-based and the tidy output is TSV, so those are the only characters a
# value cannot carry. Result in _CLEANED.
_clean_value () {
    _trim "$1"
    _CLEANED="${_TRIMMED//[$'\t\r\n']/ }"
}

# Count non-empty lines in $1. Result in _LINE_COUNT.
_count_lines () {
    _LINE_COUNT=0
    # BIG input: one awk pass (a bash walk costs ~µs per line; the fork only
    # pays off on large text — see _FR_BIG_BYTES).
    if (( ${#1} > _FR_BIG_BYTES )); then
        _LINE_COUNT=$(printf '%s\n' "$1" | awk '$0 != "" { n++ } END { print n + 0 }')
        return 0
    fi
    # (mapfile + array walk: same lines as `while read … <<< "$1"`, without a
    # read builtin call per line)
    local _cl_line _cl_all
    mapfile -t _cl_all <<< "$1"
    for _cl_line in "${_cl_all[@]}"; do
        [[ -n "$_cl_line" ]] && _LINE_COUNT=$((_LINE_COUNT + 1))
    done
    return 0
}

# Parse a "name value" line into _FIELD_NAME and _FIELD_VALUE globals.
_parse_field_line () {
    _FIELD_NAME="${1%% *}"
    _FIELD_VALUE="${1#* }"
}

# Sentinels clean_text uses to PROTECT a span without rewriting it: a space
# inside a ctime-style date or inside parentheses becomes _CT_SP, and a date's
# time colons become _CT_CO. Neither is a space, a colon or [[:space:]], so the
# key/value splitting the text feeds sees each protected span as one token with
# no delimiter in it — the same decisions the old `_` rewrite produced — while
# restore_text_values puts the original characters back into the VALUES
# afterwards. (The old rewrite was one-way: `Jan 26 12:30:45 2024` came out as
# `Jan_26_12_30_45_2024` and `(Ubuntu 13.3.0)` as `(Ubuntu_13.3.0)`.)
_CT_SP=$'\x1e'
_CT_CO=$'\x1f'

# Clean and normalize text for extraction.
# Consolidates date-fix and parentheses-fix that were previously duplicated
# in every strategy. Result in _CLEAN_TEXT_RESULT (no subshell needed).
# Caching: after first call, returns cached result from _CLEAN_TEXT_CACHE.
# A strategy that calls this MUST pass its field stream through
# restore_text_values before emitting it.
clean_text () {
    local input="$1"

    # Return cached result if available — for THIS input only (keyed on the
    # text, so a detector handed the bounded detection sample can never leave
    # a sample-derived result behind for the full-text extract).
    if [[ $_CLEAN_TEXT_DONE -eq 1 && "$input" == "${_CLEAN_TEXT_KEY-}" ]]; then
        _CLEAN_TEXT_RESULT="$_CLEAN_TEXT_CACHE"
        return
    fi

    # Pure-bash replacements (no sed forks)
    # Date pattern: " Mon 01 12:30:45 2024" -> one protected token
    local _date_re=' ([A-Za-z]{3}) ([0-9]{2}) ([0-9]{2}):([0-9]{2}):([0-9]{2}) ([0-9]{4})'
    # Paren pattern: spaces inside () -> protected (_CT_SP)
    local _paren_re
    _paren_re='[(][^) ]*[ ]'

    local result="" _line
    while IFS= read -r _line; do
        # Date normalization (only lines with colons)
        if [[ "$_line" == *":"* ]]; then
            while [[ "$_line" =~ $_date_re ]]; do
                local _dm="${BASH_REMATCH[0]}"
                # The match includes its LEADING SPACE — the replacement must
                # keep it, or the underscored date welds onto the preceding
                # word (`built on: Mon Jan 26 …` became `MonJan_26_…`).
                local _dr=" ${BASH_REMATCH[1]}${_CT_SP}${BASH_REMATCH[2]}${_CT_SP}${BASH_REMATCH[3]}${_CT_CO}${BASH_REMATCH[4]}${_CT_CO}${BASH_REMATCH[5]}${_CT_SP}${BASH_REMATCH[6]}"
                # Quoted pattern AND replacement: unquoted, glob characters in
                # the text act as a pattern and (bash >= 5.2, patsub_replacement)
                # an `&` in the replacement re-inserts the match — a line like
                # `K=(x&y z)` then grew forever.
                _line="${_line/"$_dm"/"$_dr"}"
            done
        fi
        # Parentheses space normalization (only lines with parens)
        if [[ "$_line" == *"("* ]]; then
            while [[ "$_line" =~ $_paren_re ]]; do
                local _pm="${BASH_REMATCH[0]}"
                local _pr="${_pm% }${_CT_SP}"
                _line="${_line/"$_pm"/"$_pr"}"
            done
        fi
        result+="$_line"$'\n'
    done <<< "$input"
    result="${result%$'\n'}"

    _CLEAN_TEXT_CACHE="$result"
    _CLEAN_TEXT_KEY="$input"
    _CLEAN_TEXT_DONE=1
    _CLEAN_TEXT_RESULT="$result"
}

# restore_text_values <field-stream> — undo clean_text's protection in a
# `name value` field stream. In a VALUE the sentinels become the original space
# and colon again; in a NAME (which must stay one token) both become `_`, the
# spelling names have always had. Result in _RESTORED_TEXT.
restore_text_values () {
    _RESTORED_TEXT="$1"
    [[ "$_RESTORED_TEXT" == *[$_CT_SP$_CT_CO]* ]] || return 0
    local _rt_out="" _rt_line _rt_name _rt_val
    while IFS= read -r _rt_line || [[ -n "$_rt_line" ]]; do
        _rt_name="${_rt_line%% *}"
        _rt_name="${_rt_name//[$_CT_SP$_CT_CO]/_}"
        if [[ "$_rt_line" == *" "* ]]; then
            _rt_val="${_rt_line#* }"
            _rt_val="${_rt_val//$_CT_SP/ }"
            _rt_val="${_rt_val//$_CT_CO/:}"
            _rt_out+="${_rt_name} ${_rt_val}"$'\n'
        else
            _rt_out+="${_rt_name}"$'\n'
        fi
    done <<< "$1"
    # keep the input's trailing-newline shape
    [[ "$1" == *$'\n' ]] || _rt_out="${_rt_out%$'\n'}"
    _RESTORED_TEXT="$_rt_out"
}

# _col_letter <1-based index> — spreadsheet-style label for a nameless column:
# 1->A .. 26->Z, 27->AA, 28->BB, 29->CC ... (repeated-letter convention).
# Used by the generic parsers to name headerless columns A,B,C instead of c1,c2.
_col_letter () {
    local i="$1" reps rem ch out="" k
    reps=$(( (i - 1) / 26 + 1 )); rem=$(( (i - 1) % 26 ))
    printf -v ch '%b' "\\$(printf '%03o' $(( 65 + rem )))"
    for (( k = 0; k < reps; k++ )); do out="${out}${ch}"; done
    printf '%s' "$out"
}

# _list_explode — pivot a flat "key value" record that has EXACTLY ONE indexed
# list field (keys `<prefix>.<N>` or `<prefix>.<N>.<sub>`, N a 0-based integer)
# into one record per element, repeating the scalar (non-list) keys. Reads the
# pair lines on stdin, writes the (possibly transformed) pairs on stdout.
# Passthrough unchanged when there is not exactly one indexed list or it has
# fewer than 2 elements. Lets json/yaml render a list-of-records (avro schema
# `fields`, amtool `Peers`) as tidy rows instead of one wide `field.0.* field.1.*`
# row whose duplicate leaf names collide in the melt.
_list_explode () {
    mawk '
    {
        key = $1; val = ""
        if (length($0) > length(key) + 1) val = substr($0, length(key) + 2)
        K[NR] = key; V[NR] = val; n = NR
    }
    END {
        np = 0
        for (i = 1; i <= n; i++) {
            k = K[i]
            # A list key needs a NON-EMPTY named prefix before its `.N`; a bare
            # `.0`/`.1` (empty prefix — a jq array-boundary artifact in
            # multi-array JSON like kubectl config) is not a real named list.
            if (match(k, /\.[0-9]+(\.|$)/) && RSTART > 1) {
                pre = substr(k, 1, RSTART - 1)
                rest = substr(k, RSTART + 1)
                idx = rest; sub(/\..*$/, "", idx)
                sfx = ""
                if (rest ~ /\./) { sfx = rest; sub(/^[0-9]+\./, "", sfx) }
                PRE[i] = pre; IDX[i] = idx + 0; SFX[i] = sfx; ISLIST[i] = 1
                if (!(pre in seenpre)) { seenpre[pre] = 1; np++; onlypre = pre }
            } else { ISLIST[i] = 0 }
        }
        maxidx = -1; has_subkey = 0; nscalar = 0
        for (i = 1; i <= n; i++) {
            if (!ISLIST[i]) { nscalar++; continue }
            if (np == 1 && PRE[i] == onlypre) {
                if (IDX[i] > maxidx) maxidx = IDX[i]
                if (SFX[i] != "") has_subkey = 1
            }
        }
        # Explode a list of RECORDS (elements carry sub-keys) always; a list of
        # bare SCALARS only when it DOMINATES the record (element count >= the
        # number of scalar sibling keys). This keeps a kv snapshot with a small
        # incidental list (a config tags list, npm maintainers) as one wide row,
        # while a record whose content IS the list (amtool Peers, skopeo Tags)
        # becomes one row per element.
        nelem = maxidx + 1
        if (np != 1 || maxidx < 1 || (!has_subkey && nelem < nscalar)) {
            for (i = 1; i <= n; i++) print K[i] " " V[i]
        } else {
            entry = 0
            for (e = 0; e <= maxidx; e++) {
                entry++
                for (i = 1; i <= n; i++) if (!ISLIST[i]) print "entry" entry "." K[i] " " V[i]
                for (i = 1; i <= n; i++)
                    if (ISLIST[i] && PRE[i] == onlypre && IDX[i] == e) {
                        if (SFX[i] == "") print "entry" entry "." PRE[i] " " V[i]
                        else print "entry" entry "." PRE[i] "." SFX[i] " " V[i]
                    }
            }
            print "total_entries " entry
        }
    }'
}

# ---------------------------------------------------------------------------
# _json_walk MODE TEXT — JSON read without jq, printing what the jq filters
# in the json and jsonl strategies print, so a machine without jq files the
# same rows as one with it (the corpus goldens are jq's).
#
#   leaves   every scalar under its path, `a.b.0.c VALUE`: arrays indexed
#            from 0, strings decoded (escapes, \uXXXX and surrogate pairs to
#            UTF-8), numbers, true, false and null as written — what
#            `path(..|scalars) as $p | ($p|join(".")) + " " + getpath($p)`
#            prints. Several top-level values are a stream, as in jq: each
#            one's leaves print once it has parsed, and the walk stops at
#            the first that does not.
#   entries  one JSON object per line, as JSON Lines: blank lines skipped,
#            and lines whose first non-blank character is `#` (a comment —
#            no JSON line starts with one). Each object's top-level keys
#            print as `line<N>.KEY VALUE`, a nested object or array as its
#            compact JSON text — jq's `to_entries[] | "\(.key) \(.value)"`.
#            N counts the lines that are not blank or comments.
#
# Unlike jq, a number in exponent form keeps its spelling (jq 1.7 prints
# `1e3` as `1E+3`), and a nested value's compact text keeps its string
# escapes as written. (mawk-safe; LC_ALL=C so `%c` writes one byte.)
# ---------------------------------------------------------------------------
_JSON_WALK_AWK='
function ws() { while (P <= N && index(" \t\r\n", substr(S, P, 1)) > 0) P++ }
function hex(h,   i, v, d) {
    v = 0; h = tolower(h)
    for (i = 1; i <= 4; i++) {
        d = index("0123456789abcdef", substr(h, i, 1)) - 1
        if (d < 0) { BAD = 1; return 0 }
        v = v * 16 + d
    }
    return v
}
function utf8(cp) {
    if (cp < 128) return sprintf("%c", cp)
    if (cp < 2048) return sprintf("%c%c", 192 + int(cp / 64), 128 + cp % 64)
    if (cp < 65536) return sprintf("%c%c%c", 224 + int(cp / 4096), \
        128 + int(cp / 64) % 64, 128 + cp % 64)
    return sprintf("%c%c%c%c", 240 + int(cp / 262144), \
        128 + int(cp / 4096) % 64, 128 + int(cp / 64) % 64, 128 + cp % 64)
}
# The string opening at P, decoded; P is left past its closing quote.
function str(   out, c, e, cp, lo) {
    P++; out = ""
    while (P <= N) {
        c = substr(S, P, 1)
        if (c == "\"") { P++; return out }
        if (c != "\\") { out = out c; P++; continue }
        e = substr(S, P + 1, 1)
        if (e == "n") out = out "\n"
        else if (e == "t") out = out "\t"
        else if (e == "r") out = out "\r"
        else if (e == "b") out = out "\b"
        else if (e == "f") out = out "\f"
        else if (e == "u") {
            cp = hex(substr(S, P + 2, 4)); P += 4
            if (cp >= 55296 && cp < 56320 && substr(S, P + 2, 2) == "\\u") {
                lo = hex(substr(S, P + 4, 4))
                if (lo >= 56320 && lo < 57344) {
                    cp = 65536 + (cp - 55296) * 1024 + (lo - 56320); P += 6
                }
            }
            out = out utf8(cp)
        }
        else out = out e
        P += 2
    }
    BAD = 1; return out
}
# The value at P, its scalars added to OUT under path PATH (D: its depth).
function val(path, d,   c, k, i) {
    ws(); c = substr(S, P, 1)
    if (c == "{") {
        P++; ws()
        if (substr(S, P, 1) == "}") { P++; return }
        while (P <= N && !BAD) {
            ws()
            if (substr(S, P, 1) != "\"") { BAD = 1; return }
            k = str(); ws()
            if (substr(S, P, 1) != ":") { BAD = 1; return }
            P++
            val(d ? path "." k : k, d + 1)
            ws(); c = substr(S, P, 1)
            if (c == ",") { P++; continue }
            if (c == "}") { P++; return }
            BAD = 1; return
        }
        BAD = 1; return
    }
    if (c == "[") {
        P++; ws()
        if (substr(S, P, 1) == "]") { P++; return }
        i = 0
        while (P <= N && !BAD) {
            val(d ? path "." i : i "", d + 1); i++
            ws(); c = substr(S, P, 1)
            if (c == ",") { P++; continue }
            if (c == "]") { P++; return }
            BAD = 1; return
        }
        BAD = 1; return
    }
    c = scalar()
    if (!BAD) OUT = OUT path " " c "\n"
}
# The string, number, true, false or null at P, as jq prints it.
function scalar(   start, lit) {
    if (substr(S, P, 1) == "\"") return str()
    start = P
    while (P <= N && index(",}] \t\r\n", substr(S, P, 1)) == 0) P++
    lit = substr(S, start, P - start)
    if (lit !~ /^(-?[0-9][0-9]*(\.[0-9]+)?([eE][-+]?[0-9]+)?|true|false|null)$/)
        BAD = 1
    return lit
}
# A nested value at P skipped, and its text with no space outside strings.
function compact(   start, depth, c, out, esc, instr) {
    start = P; depth = 0; out = ""; instr = 0; esc = 0
    while (P <= N) {
        c = substr(S, P, 1); P++
        if (instr) {
            out = out c
            if (esc) esc = 0; else if (c == "\\") esc = 1; else if (c == "\"") instr = 0
            continue
        }
        if (c == "\"") { instr = 1; out = out c; continue }
        if (index(" \t\r\n", c) > 0) continue
        out = out c
        if (c == "{" || c == "[") depth++
        else if (c == "}" || c == "]") { depth--; if (depth == 0) return out }
    }
    BAD = 1; return out
}
# One JSON Lines object: its top-level keys, nested values as compact text.
function entries(n,   c, k) {
    ws()
    if (substr(S, P, 1) != "{") { BAD = 1; return }
    P++; ws()
    if (substr(S, P, 1) == "}") return
    while (P <= N && !BAD) {
        ws()
        if (substr(S, P, 1) != "\"") { BAD = 1; return }
        k = str(); ws()
        if (substr(S, P, 1) != ":") { BAD = 1; return }
        P++; ws(); c = substr(S, P, 1)
        if (c == "{" || c == "[") c = compact(); else c = scalar()
        if (BAD) return
        OUT = OUT "line" n "." k " " c "\n"
        ws(); c = substr(S, P, 1)
        if (c == ",") { P++; continue }
        if (c == "}") return
        BAD = 1; return
    }
    BAD = 1
}
MODE == "entries" {
    s = $0; sub(/^[ \t\r]+/, "", s)
    if (s == "" || substr(s, 1, 1) == "#") next
    LINE++; S = $0; N = length(S); P = 1; BAD = 0; OUT = ""
    entries(LINE)
    if (!BAD) printf "%s", OUT
    next
}
# leaves: the whole input is one record (RS is \001, which JSON text never
# holds), or one line at a time when it does hold one
WHOLE { T = $0; next }
{ T = T $0 "\n" }
END {
    if (MODE != "leaves") exit
    S = T; N = length(S); P = 1
    while (1) {
        ws(); if (P > N) break
        BAD = 0; OUT = ""
        val("", 0)
        if (BAD) break
        printf "%s", OUT
    }
}'

_json_walk () {
    if [[ "$1" == leaves && "$2" != *$'\001'* ]]; then
        printf '%s' "$2" | LC_ALL=C awk -v MODE=leaves -v WHOLE=1 -v RS=$'\001' "$_JSON_WALK_AWK"
    else
        printf '%s\n' "$2" | LC_ALL=C awk -v MODE="$1" -v WHOLE=0 "$_JSON_WALK_AWK"
    fi
}

# ---------------------------------------------------------------------------
# preprocess_input_text — the input-normalisation pipeline, applied to the
# global $text BEFORE strategy detection. Factored out of the single-file
# main path so batch mode runs the IDENTICAL pipeline: before this existed,
# `--batch` skipped every step below, so the same file could pick a different
# winner in batch than alone (adb-devices: `tsv` alone, `aligned-columns` in
# batch, because the leading-chrome strip never removed its banner line).
# Operates on the global `text`, in the same order as before:
#   line-terminator normalisation, exotic-space normalisation, ZWSP delete,
#   fullwidth digit/colon mapping, ANSI/OSC strip, BEL/BS strip,
#   `== section ==` banner drop, and the leading-chrome strip (_lc_strip).
# ---------------------------------------------------------------------------
# Gate presence for preprocess_input_text: every normalisation step below is
# gated on "the text contains LITERAL". On a BIG text those ~20 full-text
# pattern scans cost seconds (bash pattern matching is ~10 ns/byte), so one
# awk pass answers them all up front (_pp_presence), and _pp_in reads the
# answer — exactly the substring test it replaces. A step that REWRITES the
# text clears _PP_OK, and every later gate falls back to the direct test.
_PP_LITS=$'\r\n\013\n\014\n\302\205\n\342\200\250\n\342\200\251\n\302\240\n\342\200\n\342\201\237\n\343\200\200\n\342\224\200\n\342\224\201\n\342\225\220\n\342\200\213\n\357\274\n\033[0m\033[\n\033\n\007\n\010\n%]\n\302\257\n\\\n== '
_PP_OK=0
declare -A _PP_PRESENT=()
_pp_presence () {
    _PP_OK=0
    _PP_PRESENT=()
    (( ${#text} > _FR_BIG_BYTES )) || return 0
    local _pp_found _pp_l
    _pp_found="$(_fr_absent_literals "$text" "$_PP_LITS")" || return 0
    local -a _pp_lits=() _pp_abs=()
    local -A _pp_isabs=()
    mapfile -t _pp_lits <<< "$_PP_LITS"
    [[ -n "$_pp_found" ]] && mapfile -t _pp_abs <<< "$_pp_found"
    for _pp_l in ${_pp_abs[@]+"${_pp_abs[@]}"}; do _pp_isabs[$_pp_l]=1; done
    for _pp_l in "${_pp_lits[@]}"; do
        [[ -n "${_pp_isabs[$_pp_l]:-}" ]] || _PP_PRESENT[$_pp_l]=1
    done
    _PP_OK=1
}
# _pp_in LITERAL — does $text contain LITERAL? (from _pp_presence when valid)
_pp_in () {
    if [[ $_PP_OK -eq 1 ]]; then
        [[ -n "${_PP_PRESENT[$1]:-}" ]]
    else
        [[ "$text" == *"$1"* ]]
    fi
}

preprocess_input_text () {
    local local_vt_to _banner_out _bl _lc_first
    _pp_presence
    # Normalise alternate line terminators to \n so record splitting — which keys on
    # \n throughout — sees every logical line. Covers Windows CRLF, bare-CR (classic
    # Mac), vertical-tab / form-feed page breaks, and the Unicode line separators
    # NEL (U+0085), LS (U+2028) and PS (U+2029). Without this, a capture that uses any
    # of these instead of \n collapses to a single physical line and no rows are found.
    # Gated on such a byte being present, so it is a true no-op for ordinary \n input.
    # Order matters: strip CRLF's trailing CR first, then map any remaining bare CR /
    # VT / FF, then the multibyte separators — so CRLF never becomes a blank line.
    #
    # VT is context-sensitive: when the input ALREADY has real \n lines, a VT is not
    # a line break at all — it's a stray control byte INSIDE a cell (`disk\vfailure`)
    # and becomes a SPACE, keeping the row whole. Only in a \n-less capture (VT as
    # the sole line separator — the adversarial breaker this block was built for)
    # does VT map to \n.
    if _pp_in $'\r' || _pp_in $'\013' || _pp_in $'\014' \
          || _pp_in $'\302\205' || _pp_in $'\342\200\250' || _pp_in $'\342\200\251'; then
        _PP_OK=0
        local_vt_to=$'\n'
        [[ "$text" == *$'\n'* ]] && local_vt_to=' '
        text="$(printf '%s' "$text" | sed 's/\r$//')"
        # CR-REDRAW collapse. An INTERIOR \r on an \n-terminated line is a
        # terminal overwrite (progress bars: `…[  0%]\r…[ 45%]\r…[100%] done`),
        # not a line break — the terminal shows only the final state, and even
        # that is transient chrome, not data. When the first and last
        # \r-segments of a line share a >=8-char prefix (the redraw signature:
        # same label redrawn with a new value), the whole line is DROPPED —
        # provided at least 2 non-blank lines remain to be the data (otherwise
        # the collapsed final state is kept: it is all the input has). Leading
        # blanks exposed by a drop go with it. Segments that DON'T share a
        # prefix (spinner glyphs vary their first char; \r-separated log
        # records) fall through to the historical CR -> \n mapping below, so
        # classic-Mac files and \r-separated logs split into lines as before.
        if [[ "$text" == *$'\r'* && "$text" == *$'\n'* ]]; then
            text="$(printf '%s' "$text" | awk '
                {
                    line = $0; redraw = 0
                    n = split(line, seg, "\r")
                    if (n >= 2) {
                        a = seg[1]; b = seg[n]
                        # an erase-in-line (ESC[K / ESC[2K) right after the
                        # CR is part of the redraw, not of the label: compare
                        # the segments without it
                        sub(/^\033\[[0-9]*K/, "", a); sub(/^\033\[[0-9]*K/, "", b)
                        m = length(a); if (length(b) < m) m = length(b)
                        p = 0
                        while (p < m && substr(a, p + 1, 1) == substr(b, p + 1, 1)) p++
                        if (p >= 8) { line = b; redraw = 1 }
                    }
                    buf[NR] = line; isr[NR] = redraw
                    if (!redraw && line !~ /^[ \t]*$/) keep++
                }
                END {
                    lead = 1
                    for (i = 1; i <= NR; i++) {
                        if (keep >= 2 && isr[i]) continue
                        if (keep >= 2 && lead && buf[i] ~ /^[ \t]*$/) continue
                        lead = 0
                        print buf[i]
                    }
                }')"
        fi
        text="$(printf '%s' "$text" | tr '\r\013\014' $'\n'"${local_vt_to}"$'\n' \
                | sed $'s/\302\205/\\\n/g; s/\342\200\250/\\\n/g; s/\342\200\251/\\\n/g')"
        unset local_vt_to
    fi


    # Normalise exotic Unicode horizontal spaces to ASCII space so column splitting
    # — which keys on runs of 0x20 — sees the alignment the terminal showed. Covers
    # NBSP (U+00A0, also used as locale thousands grouping — a SINGLE space inside a
    # number survives the 2+-space column rule, so "1 234,56" stays one cell while
    # NBSP-padded column gaps still split), narrow NBSP (U+202F), medium math space
    # (U+205F), the U+2000–U+200A quad/en/em/thin/hair family, and the ideographic
    # space (U+3000) CJK tables pad with. Gated on such a byte being present; the
    # U+2028/29 line separators were already mapped to \n above, and curly quotes
    # (U+2018-201D) fall outside the mapped ranges.
    if _pp_in $'\302\240' || _pp_in $'\342\200' || _pp_in $'\342\201\237' \
          || _pp_in $'\343\200\200'; then
        _PP_OK=0
        text="$(printf '%s' "$text" | LC_ALL=C sed $'s/\302\240/ /g; s/\342\200[\200-\212]/ /g; s/\342\200\257/ /g; s/\342\201\237/ /g; s/\343\200\200/ /g')"
    fi

    # Normalise UNICODE RULE LINES to ASCII dashes. tokei and scc draw their
    # separators with box-drawing horizontals (─ U+2500, ━ U+2501, ═ U+2550),
    # and every rule-line test downstream keys on `[=-]` — so the header never
    # applied and the whole table fell through to verbatim lines. Only a line
    # consisting WHOLLY of these characters (plus whitespace) is rewritten;
    # a real box frame's corners and junctions (┌ ├ ┼ ┤ …) are different code
    # points, so bordered tables keep their frames for the box strategies.
    # LC_ALL=C: the address is a BYTE class (e2/94/95/80/81/90), and the
    # line-anchored full match means every byte on the line must be one of
    # them — a corner byte anywhere disqualifies the line. Gated on the lead
    # sequences being present, a no-op otherwise.
    if _pp_in $'\342\224\200' || _pp_in $'\342\224\201' || _pp_in $'\342\225\220'; then
        _PP_OK=0
        text="$(printf '%s' "$text" | LC_ALL=C sed $'/^[ \t]*[\342\224\225\200\201\220 \t]\\{1,\\}$/ { s/\342\224\200/-/g; s/\342\224\201/-/g; s/\342\225\220/-/g; }')"
    fi

    # Delete ZERO-WIDTH SPACE (U+200B) — invisible in the terminal, so it can only
    # corrupt: a header token carrying one (`user​name`) prints as one word but
    # compares unequal to its plain form and pollutes the melted field name. Only
    # ZWSP is dropped; ZWNJ/ZWJ (U+200C/D) are orthographically REAL (Farsi
    # half-space, emoji family joins) and stay. Gated on the byte pair.
    if _pp_in $'\342\200\213'; then
        _PP_OK=0
        text="$(printf '%s' "$text" | LC_ALL=C sed $'s/\342\200\213//g')"
    fi

    # Normalise FULLWIDTH digits (U+FF10–FF19, CJK tables: `８０`) and the fullwidth
    # colon (U+FF1A) to their ASCII forms so numeric-contrast header detection and
    # `key: value` splitting see them the way a reader does. Gated on the FF-block
    # lead bytes being present.
    if _pp_in $'\357\274'; then
        _PP_OK=0
        text="$(printf '%s' "$text" | LC_ALL=C sed $'s/\357\274\220/0/g; s/\357\274\221/1/g; s/\357\274\222/2/g; s/\357\274\223/3/g; s/\357\274\224/4/g; s/\357\274\225/5/g; s/\357\274\226/6/g; s/\357\274\227/7/g; s/\357\274\230/8/g; s/\357\274\231/9/g; s/\357\274\232/:/g')"
    fi

    # COLOR-AS-SEPARATOR recovery — runs BEFORE the ANSI strip, which would
    # otherwise weld the fields together irrecoverably. Some TUIs emit columns
    # with NO whitespace between them, each field its own SGR span:
    #   ESC[31m1420ESC[0mESC[32mrootESC[0mESC[33m12.4ESC[0m  ->  1420root12.4
    # There the reset-abuts-next-SGR boundary IS the column separator, so a TAB
    # is inserted at each one. Gated per line: only when the stripped line has
    # NO 2+-space run (color is the only separator present). That gate is what
    # protects the counter-shapes — a space-aligned table whose one cell is
    # recolored mid-value (`ESC[33m10ESC[0mESC[36m01ESC[0m` inside "1001"),
    # gauge bars, and box tables all carry real space runs and pass untouched.
    if _pp_in $'\033[0m\033['; then
        _PP_OK=0
        text="$(printf '%s' "$text" | awk '
            BEGIN { esc = sprintf("%c", 27) }
            {
                line = $0
                bnd = esc "\\[0m" esc "\\[[0-9;]*m"
                if (line ~ bnd) {
                    stripped = line
                    gsub(esc "\\[[0-9;?]*[@-~]", "", stripped)
                    if (stripped !~ /  / && stripped ~ /[^ ]/) {
                        gsub(esc "\\[0m" esc "\\[", esc "[0m\t" esc "[", line)
                    }
                }
                print line
            }')"
    fi

    # Strip ANSI/VT escape sequences (colored output: ls --color, gh, git, kubectl,
    # systemctl status dots, terraform plan, npm/cargo, …) so a color code can never
    # split or pollute a data cell. Gated on an ESC byte being present, so it is a
    # true no-op — no subprocess — for the overwhelming majority of inputs that carry
    # none. Matches the ECMA-48 CSI form (ESC [ params intermediates final) plus the
    # OSC form — terminated by BEL or by the String Terminator ESC-backslash
    # (OSC 8 hyperlinks: `ESC]8;;URL ESC\ text ESC]8;; ESC\` keeps just
    # `text`; with only the BEL form, the bare-escape rule ate `ESC]` and left
    # `8;;URL` welded into the cell) — and bare two-byte escapes.
    if _pp_in $'\033'; then
        _PP_OK=0
        text="$(printf '%s' "$text" | sed $'s/\033\\[[0-9;?]*[ -/]*[@-~]//g; s/\033\\][^\007\033]*\033\\\\//g; s/\033\\][^\007]*\007//g; s/\033[@-Z\\\\-_]//g')"
    fi

    # Strip terminal-bell and backspace control bytes (BEL \a, BS \b) — decoration
    # or erase intent, never data; leaving them embeds invisible bytes in a cell.
    # Runs AFTER the ANSI strip: BEL terminates an OSC sequence, so deleting it
    # first would orphan `ESC]…BEL` sequences the OSC rule needs intact. Gated on
    # presence, a no-op otherwise.
    if _pp_in $'\007' || _pp_in $'\010'; then
        _PP_OK=0
        text="$(printf '%s' "$text" | tr -d '\007\010')"
    fi

    # Collapse pre-baked CR-REDRAW progress welds. A `\r`-redrawn progress line
    # whose CRs were consumed upstream of the capture arrives as ONE line
    # holding every redraw state welded together:
    #   Building image  [  0%]Building image  [ 45%]Building image  [100%] done
    # A terminal would show only the LAST state, and even that is transient
    # chrome — so a weld line is DROPPED when at least 2 non-blank lines remain
    # to be the data (kept, collapsed to its final state, otherwise). The weld
    # signature is the line's first 12 characters recurring later in the SAME
    # line; guards: the prefix must contain a letter and at least 3 distinct
    # characters (a `====` banner's repeating prefix is one char and stays).
    # Runs AFTER the ANSI strip (the weld's color codes are already gone) and
    # is gated on a `%]` byte pair — the progress-percent tail — so ordinary
    # input never pays the awk pass. The interior-\r flavor of the same redraw
    # is handled at the line-terminator step above.
    if _pp_in '%]'; then
        _PP_OK=0
        text="$(printf '%s' "$text" | awk '
            {
                line = $0; weld = 0
                if (length(line) >= 30) {
                    pre = substr(line, 1, 12)
                    if (pre ~ /[A-Za-z]/) {
                        d = 0
                        for (i = 1; i <= 12; i++) {
                            c = substr(pre, i, 1); seen[c] = 1
                        }
                        for (c in seen) d++
                        delete seen
                        if (d >= 3 && index(substr(line, 2), pre) > 0) {
                            rest = line; off = 0
                            while ((p = index(substr(rest, 2), pre)) > 0) {
                                off += p
                                rest = substr(line, off + 1)
                            }
                            line = rest; weld = 1
                        }
                    }
                }
                buf[NR] = line; isw[NR] = weld
                if (!weld && line !~ /^[ \t]*$/) keep++
            }
            END {
                lead = 1
                for (i = 1; i <= NR; i++) {
                    if (keep >= 2 && isw[i]) continue
                    if (keep >= 2 && lead && buf[i] ~ /^[ \t]*$/) continue
                    lead = 0
                    print buf[i]
                }
            }')"
    fi

    # LEADING-CHROME strip — lines a capture drags in ABOVE the data (reviewer
    # round R3). Only the LEADING run of a block with >=2 remaining lines is
    # touched, each form gated to leading-only so real content is never lost:
    #   * `$ command` shell-prompt echoes (`$ amass intel -org …`);
    #   * `WARNING:`/`ERROR:`/`NOTICE:` stderr noise when no later line starts
    #     the same way (apk's cache warning);
    #   * `NAME ********…` banner rules (ansible's `PLAY RECAP ****`).
    _lc_strip () {
        local _in="$1" _out="" _body="" _l _lead=1 _n=0
        local _drop_warn=1 _drop_sqlc=0 _sqlc_seen=0
        while IFS= read -r _l; do
            _n=$((_n + 1))
            # `-- Query 1 (…)` SQL-comment banners directly above a JSON
            # document (surreal sql) — dropped only when the first other
            # non-blank line opens the document with `[` or `{`.
            if [[ $_sqlc_seen -eq 0 && -n "${_l//[[:space:]]/}" && "$_l" != "-- "* ]]; then
                _sqlc_seen=1
                [[ $_n -gt 1 && "$_l" =~ ^[[:space:]]*[\[{] ]] && _drop_sqlc=1
            fi
            [[ $_n -le 1 ]] && continue
            [[ "$_l" =~ ^(WARNING|ERROR|NOTICE): ]] && _drop_warn=0
        done <<< "$_in"
        _n=0
        while IFS= read -r _l; do
            if [[ $_lead -eq 1 ]]; then
                if [[ -z "${_l//[[:space:]]/}" ]]; then :
                elif [[ "$_l" =~ ^\$\ [A-Za-z] ]]; then continue
                elif [[ $_drop_sqlc -eq 1 && "$_l" == "-- "* ]]; then continue
                elif [[ $_drop_warn -eq 1 && "$_l" =~ ^(WARNING|ERROR|NOTICE): ]]; then continue
                elif [[ "$_l" =~ \*{6,}[[:space:]]*$ && "$_l" =~ ^[A-Z] ]]; then continue
                elif [[ "$_l" =~ ^[A-Z][a-z]+([[:space:]]+[a-z]+){2,}$ ]] && \
                     [[ "$_l" =~ [[:space:]](of|the|to|in|for|with|and|on|at|by|from|is|are)[[:space:]] ]]; then
                    # prose title ("List of devices attached") — Titlecase word +
                    # lowercase words incl. a function word, no colon/digits
                    continue
                else _lead=0
                fi
            fi
            _body+="$_l"$'\n'
            [[ -n "${_l//[[:space:]]/}" ]] && _n=$((_n + 1))
        done <<< "$_in"
        if [[ $_n -ge 2 && "$_body" != "$_in"$'\n' ]]; then
            printf '%s' "${_body%$'\n'}"
        else
            printf '%s' "$_in"
        fi
    }
    # ASCII-ART GUTTER. Some tools print a logo down the left margin and their
    # real output to the right of it, on the same lines — `cilium status` draws
    # a hexagon out of `/`, `\`, `_` and `¯` (U+00AF) beside `Cilium: OK`. The
    # art is not a column: it made the kv parser read the key as
    # `/¯¯\__/¯¯\    Cilium`. Strip a LEADING run of art characters when it is
    # separated from the content by a column gap (2+ spaces), and drop the
    # art-only lines with it.
    #
    # Gated hard, because a left margin is usually meaningful: the run must
    # contain a `/`, `\` or `¯` (a run of only spaces and underscores is
    # indentation, not a logo), 2+ lines must carry art AND content, and 3+
    # lines must be involved in total. Byte-oriented (LC_ALL=C with the U+00AF
    # bytes written out) so the multibyte glyph is matched exactly rather than
    # depending on the locale awk or grep happens to run under.
    # `grep -c` exits 1 when the count is zero and the engine runs under
    # `set -e`, so every count below is guarded — an unguarded one killed the
    # engine outright on any input with no art.
    local _art_bs='\'
    if _pp_in $'\302\257' || _pp_in "$_art_bs"; then
        local _art_set=" /${_art_bs}_"$'\302\257' _art_re _art_only_re _art_n=0 _art_only=0
        _art_re="^[${_art_set}]*[/${_art_bs}"$'\302\257'"][${_art_set}]*  +[^ ]"
        _art_only_re="^[${_art_set}]*[/${_art_bs}"$'\302\257'"][${_art_set}]*$"
        _art_n=$(printf '%s\n' "$text" | LC_ALL=C grep -cE "$_art_re" || true)
        _art_only=$(printf '%s\n' "$text" | LC_ALL=C grep -cE "$_art_only_re" || true)
        if [[ ${_art_n:-0} -ge 2 && $((${_art_n:-0} + ${_art_only:-0})) -ge 3 ]]; then
            # `\%…%d` for the delete address: the pattern itself contains `/`,
            # so the usual `/…/d` form would end the address mid-regex.
            _PP_OK=0
            text="$(printf '%s' "$text" | LC_ALL=C sed -E \
                -e "\\%${_art_only_re}%d" \
                -e "s%^([${_art_set}]*[/${_art_bs}"$'\302\257'"][${_art_set}]*)  +%%")"
        fi
    fi

    # Interspersed `== section ==` banner lines (apptainer inspect's
    # `== labels ==` / `== runscript ==`) are pure section decoration — drop a
    # line delimited by EXACTLY-two-equals runs (`== word ==`). Longer runs
    # (`=== SET ===`, `====== JOB MAP ======`) are GROUP-LABEL banners that the
    # embedded-table / kv-under-group parsers legitimately consume, so the
    # exact-`==` shape is the discriminator. Gated on the byte pair.
    if _pp_in '== '; then
        _PP_OK=0
        if (( ${#text} > _FR_BIG_BYTES )); then
            # BIG: the loop below in one awk pass (the sentinel keeps every
            # trailing newline, so exactly one is dropped, as below)
            _banner_out="$(cat <<< "$text" | awk '
                !/^[ \t\n\v\f\r]*==[ \t\n\v\f\r]+[A-Za-z0-9][^=]*[ \t\n\v\f\r]+==[ \t\n\v\f\r]*$/'; printf .)"
            _banner_out="${_banner_out%.}"
            text="${_banner_out%$'\n'}"
            _banner_out=""
        else
        _banner_out=""
        while IFS= read -r _bl; do
            if [[ "$_bl" =~ ^[[:space:]]*==[[:space:]]+[A-Za-z0-9][^=]*[[:space:]]+==[[:space:]]*$ ]]; then
                continue
            fi
            _banner_out+="$_bl"$'\n'
        done <<< "$text"
        text="${_banner_out%$'\n'}"
        fi
    fi

    case "$text" in
        '$ '*|WARNING:*|ERROR:*|NOTICE:*|*'******'*|List\ *|Ran\ *|'-- '*)
            text="$(_lc_strip "$text")" ;;
        [A-Z]*)
            # prose-title first line — cheap pre-check before the full pass
            _lc_first="${text%%$'\n'*}"
            if [[ "$_lc_first" =~ ^[A-Z][a-z]+([[:space:]]+[a-z]+){2,}$ ]]; then
                text="$(_lc_strip "$text")"
            fi
            ;;
    esac
}

################################################################################
## FAST LINE / TOKEN HELPERS (perf)
##
## bash reads a here-string that fits in a pipe buffer ONE BYTE PER read(2):
## a `while IFS= read -r l; do …; done <<< "$text"` loop costs a syscall per
## input byte, and a per-line `read -ra arr <<< "$line"` adds a pipe per call
## on top. Command substitution (`x="$(helper …)"`) forks. In the hot generic
## parsers those three idioms were most of the run time. The helpers below
## give the same line / token / name views without any of that; each one is
## an output-identical replacement for the idiom named in its comment.
################################################################################

# Size (in characters) above which the whole-output passes — store,
# _count_lines, deduplicate_output's record build, the prefix strip and
# format_tsv — hand the text to ONE mawk-safe awk pass instead of a bash
# per-line walk. Both paths are output-identical; below the threshold the
# fork is not worth it. Overridable (export _FR_BIG_BYTES=0 forces the awk
# paths — how their equivalence is tested).
_FR_BIG_BYTES="${_FR_BIG_BYTES:-32768}"

# _fr_lines TEXT — the global array _FR_LINES holds, element for element, the
# lines that `while IFS= read -r l; do …; done <<< "$TEXT"` iterates (the
# here-string's appended newline terminates the last line; embedded empty
# lines are kept). Memoised on the text itself: the dispatcher hands every
# detector the same input, so the split is paid once per input. A
# `for l in "${_FR_LINES[@]}"` loop expands its word list up front, so calling
# _fr_lines again inside the loop body is safe; index-based loops that call
# other helpers must copy the array first.
_FR_LINES=()
_FR_LINES_KEY=""
_FR_LINES_OK=0
_fr_lines () {
    if [[ $_FR_LINES_OK -eq 1 && "$1" == "$_FR_LINES_KEY" ]]; then
        return 0
    fi
    mapfile -t _FR_LINES <<< "$1"
    _FR_LINES_KEY="$1"
    _FR_LINES_OK=1
}

# _fr_absent_literals TEXT LITERALS — print each of the newline-separated
# LITERALS that does NOT occur in TEXT (byte-exact, LC_ALL=C). Literals hold
# no newline, so this is also "occurs in no line". The text is read in \001-
# separated records — for ordinary text ONE record, so one index() scan per
# literal (~100 literals over 10 MB in ~0.1 s) instead of one per line.
#
# BIG text: a literal found in the first 64 KB occurs (a prefix is a
# substring), and the rest are first put to ONE `grep -F` over the whole text —
# no line holds any of them means every one is absent (literals hold no
# newline). Only when that grep finds something do they get the per-literal
# scan, which costs a full pass per ABSENT literal (~0.6 s on 10 MB).
_fr_absent_literals () {
    if (( ${#1} > 65536 )); then
        local _fal_rest
        _fal_rest="$(_fr_absent_literals_scan "${1:0:65536}" "$2")" || return
        [[ -n "$_fal_rest" ]] || return 0
        if ! LC_ALL=C grep -qaF -e "$_fal_rest" <<< "$1"; then
            printf '%s\n' "$_fal_rest"
            return 0
        fi
        _fr_absent_literals_scan "$1" "$_fal_rest"
        return
    fi
    _fr_absent_literals_scan "$1" "$2"
}
_fr_absent_literals_scan () {
    # (RS = \001 always: no literal holds a \001 or a newline, so none can
    # span a record boundary and "occurs in some record" is exact either way)
    _FAL="$2" LC_ALL=C awk -v RS=$'\001' '
        BEGIN { n = split(ENVIRON["_FAL"], P, "\n"); left = n }
        {
            for (k = 1; k <= n; k++)
                if (!(k in F) && index($0, P[k])) { F[k] = 1; if (--left == 0) exit }
        }
        END { for (k = 1; k <= n; k++) if (!(k in F)) print P[k] }' <<< "$1"
}

# _fr_scratch — make sure _FR_SCRATCH names a private (umask 077) scratch
# directory for big-input file passes, created on first use and removed when
# the (sub)shell that created it exits. A strategy's extract runs in a
# subshell: a directory made there is that subshell's, one inherited from the
# engine is shared (file names carry $BASHPID where that matters).
_FR_SCRATCH=""
_fr_scratch () {
    [[ -n "$_FR_SCRATCH" && -d "$_FR_SCRATCH" ]] && return 0
    local _fs_um; _fs_um=$(umask); umask 077
    _FR_SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/provost-extract.XXXXXX") || { umask "$_fs_um"; _FR_SCRATCH=""; return 1; }
    umask "$_fs_um"
    trap '_fr_scratch_cleanup' EXIT
    return 0
}
_fr_scratch_cleanup () {
    [[ -n "${_FR_SCRATCH:-}" && -d "$_FR_SCRATCH" ]] && rm -rf "$_FR_SCRATCH"
    _FR_SCRATCH=""
    return 0
}

# _fr_split_out OUT — _FR_OUT holds exactly the lines `mapfile -t` reads from a
# stream carrying OUT (a command's full output, captured with a sentinel so
# no trailing newline is lost). `mapfile < <(cmd)` reads its pipe ONE BYTE
# per read(2) — 0.2 s per MB — while a captured string splits in
# milliseconds (the here-string is seekable).
_fr_split_out () {
    if [[ -z "$1" ]]; then _FR_OUT=(); return 0; fi
    if [[ "${1: -1}" == $'\n' ]]; then
        mapfile -t _FR_OUT <<< "${1:0:${#1}-1}"
    else
        mapfile -t _FR_OUT <<< "$1"
    fi
}

# _fr_tok STRING — the global array _FR_TOK holds exactly the words
# `read -ra arr <<< "$STRING"` would store: read takes the FIRST line of the
# here-string and splits it on the CURRENT $IFS (an `IFS=x _fr_tok …` prefix or
# a caller's `local IFS` applies just as it would to read), leading/trailing
# IFS whitespace dropped, no backslash processing — and, via noglob for the
# split only, no pathname expansion. Pure expansion: no here-string pipe, no
# fork (read's here-string is a pipe it drains one byte per syscall).
_fr_tok () {
    if [[ "$1" == *$'\n'* ]]; then
        # multi-line argument: read would only see the first line
        local _fr_l="${1%%$'\n'*}"
        _fr_tok "$_fr_l"
        return 0
    fi
    if [[ $- == *f* ]]; then
        # shellcheck disable=SC2206
        _FR_TOK=($1)
    else
        set -f
        # shellcheck disable=SC2206
        _FR_TOK=($1)
        set +f
    fi
}

# _fr_modal N… — the modal value of a list of integers in _FR_MODE and its
# count in _FR_MODE_N (0 and 0 for an empty list); ties go to the value that
# occurs FIRST. Output-identical to the nested idiom
#     for a in "${c[@]}"; do k=0; for b in "${c[@]}"; do
#         [[ "$b" -eq "$a" ]] && k=$((k + 1)); done
#         [[ $k -gt $best ]] && { best=$k; mode=$a; }; done
# in O(n) instead of O(n²) — that idiom runs over EVERY data row in several
# parsers (3.5k rows = 12M comparisons, per parser). Values must be canonical
# non-negative integers (token / cell / segment counts), so string equality of
# the keys is numeric equality.
_fr_modal () {
    local -A _fm_c=()
    local _fm_v
    for _fm_v in "$@"; do _fm_c[$_fm_v]=$(( ${_fm_c[$_fm_v]:-0} + 1 )); done
    _FR_MODE=0; _FR_MODE_N=0
    for _fm_v in "$@"; do
        if (( ${_fm_c[$_fm_v]} > _FR_MODE_N )); then
            _FR_MODE_N=${_fm_c[$_fm_v]}; _FR_MODE=$_fm_v
        fi
    done
    return 0
}

# _fr_strip_awk < lines — the prefix strip as a stdin filter: each non-empty
# line, minus a leading `STRAT-…<TAB>` label (strip_strat_prefix).
_fr_strip_awk () {
    awk '$0 != "" {
        s = $0
        if (substr(s, 1, 6) == "STRAT-") { i = index(s, "\t"); if (i) s = substr(s, i + 1) }
        print s
    }'
}

# _fr_strip_prefix_lines TEXT — _FR_STRIPPED = TEXT's non-empty lines, each
# through strip_strat_prefix, newline-joined with no trailing newline: exactly
# what `while IFS= read -r l; do [[ -z $l ]] && continue; strip_strat_prefix
# "$l"; x+="$_STRIPPED_LINE"$'\n'; done <<< "$TEXT"; x="${x%$'\n'}"` builds,
# in linear time (that `x+=` re-copies the growing string per line).
_fr_strip_prefix_lines () {
    if (( ${#1} > _FR_BIG_BYTES )); then
        # awk twin of the loop below (sentinel keeps the trailing newline so
        # exactly one is dropped, as the loop's `%$'\n'` does)
        _FR_STRIPPED="$(printf '%s\n' "$1" | _fr_strip_awk; printf .)"
        _FR_STRIPPED="${_FR_STRIPPED%.}"
        _FR_STRIPPED="${_FR_STRIPPED%$'\n'}"
        return 0
    fi
    local _fsp_all _fsp_l
    local -a _fsp_out=()
    mapfile -t _fsp_all <<< "$1"
    for _fsp_l in "${_fsp_all[@]}"; do
        [[ -z "$_fsp_l" ]] && continue
        strip_strat_prefix "$_fsp_l"
        _fsp_out+=("$_STRIPPED_LINE")
    done
    _FR_STRIPPED=""
    if [[ ${#_fsp_out[@]} -gt 0 ]]; then
        printf -v _FR_STRIPPED '%s\n' "${_fsp_out[@]}"
        _FR_STRIPPED="${_FR_STRIPPED%$'\n'}"
    fi
}

# _fr_col_letter N — _col_letter's spreadsheet label (1->A … 26->Z, 27->AA)
# in the global _FR_LETTER instead of on stdout, so naming a column costs no
# command-substitution fork (`$(_col_letter …)` forks twice per call).
_FR_ABC=ABCDEFGHIJKLMNOPQRSTUVWXYZ
_fr_col_letter () {
    if (( $1 < 1 )); then
        _FR_LETTER="$(_col_letter "$1")"
        return 0
    fi
    local _fr_rem=$(( ($1 - 1) % 26 )) _fr_reps=$(( ($1 - 1) / 26 + 1 )) _fr_k
    local _fr_ch="${_FR_ABC:_fr_rem:1}"
    _FR_LETTER=""
    for (( _fr_k = 0; _fr_k < _fr_reps; _fr_k++ )); do _FR_LETTER+="$_fr_ch"; done
}

# ---------------------------------------------------------------------------
# RESULT-SET FOOTERS — the line a client prints UNDER a table to count it or
# sign off, never a row of it: `(5 rows affected)` (sqlcmd, isql), `4 rows
# selected.` / `no rows selected` (SQL*Plus), `3 record(s) selected.` (DB2),
# `12 row(s) retrieved.` (Informix), `(3 rows)` (psql-style clients), `2 rows
# in set (0.00 sec)` (MySQL), `The command completed successfully.` (Windows
# `net`), `Done in 0.84s.` (yarn). One ERE (bash `=~` and awk alike),
# matched against the line with its edge whitespace trimmed.
_FR_FOOTER_RE='^\(?[0-9][0-9,]* (rows?|records?|record\(s\)|row\(s\)|items?|entries) (affected|selected|returned|retrieved|fetched|found|deleted|updated|inserted)\)?\.?$|^\([0-9][0-9,]* rows?\)$|^[0-9][0-9,]* rows? in set( \([0-9.]+ sec\))?$|^no rows selected\.?$|^The command completed successfully\.?$|^Done in [0-9.]+ ?m?s\.?$'
# _fr_is_footer LINE — 0 when LINE is such a footer.
_fr_is_footer () {
    local _ff="${1#"${1%%[![:space:]]*}"}"
    _ff="${_ff%"${_ff##*[![:space:]]}"}"
    [[ "$_ff" =~ $_FR_FOOTER_RE ]]
}
# What a client may print AFTER its footer, before the output ends: its next
# prompt (`SQL>`, `1>`, `mysql>`, `db2 =>`) or a timing line (`Elapsed:
# 00:00:00.01`, `Time: 0.512 ms`).
_FR_AFTER_FOOTER_RE='^[A-Za-z0-9_]+( ?=)?>$|^Elapsed: [0-9:.]+$|^Time: [0-9.]+ ms'
# _fr_footer_cut — over the rows in the global array _FR_FC (blank lines
# allowed), sets _FR_FC_N to how many leading entries are the table: when
# the last line that is not blank, a prompt or a timing line is a footer
# (and a row precedes it), the table ends above it — the footer and what
# follows are dropped, as are blank lines left at the end; else all of them.
_fr_footer_cut () {
    local _fc_i=$(( ${#_FR_FC[@]} - 1 )) _fc_l
    _FR_FC_N=${#_FR_FC[@]}
    while [[ $_fc_i -ge 1 ]]; do
        _fc_l="${_FR_FC[$_fc_i]#"${_FR_FC[$_fc_i]%%[![:space:]]*}"}"
        _fc_l="${_fc_l%"${_fc_l##*[![:space:]]}"}"
        if [[ -z "$_fc_l" || "$_fc_l" =~ $_FR_AFTER_FOOTER_RE ]]; then _fc_i=$((_fc_i - 1)); continue; fi
        [[ "$_fc_l" =~ $_FR_FOOTER_RE ]] || return 0
        break
    done
    [[ $_fc_i -ge 1 ]] || return 0
    while [[ $_fc_i -ge 1 && "${_FR_FC[$((_fc_i - 1))]}" != *[![:space:]]* ]]; do _fc_i=$((_fc_i - 1)); done
    _FR_FC_N=$_fc_i
}

# ---------------------------------------------------------------------------
# GUTTER GRID — assign the cells of a whitespace-aligned table by character
# offsets. Input: the table lines; when nh=1 the first is the header, and
# when rl=1 the next is a rule line (`----  -----` / `==== ===`) whose runs
# give the label spans exactly. Output: `entry<N>.<name> <value>` lines and
# `total_entries N`, or NOTHING when the offsets cannot be trusted (the
# caller then falls back to its token paths). mawk-safe; run under LC_ALL=C.
#
# How: every position some line prints on (header, rule or data) belongs to a
# SEGMENT; the runs of positions that are blank in ALL of them are GUTTERS. A
# segment under one header label is that column, whatever its cells hold
# (`Number of message queues`, `Oct  2`, `10/14/2026 9:02 AM`); right-aligned
# numbers end on their label, so a value wider than its label still lands in
# its segment. Then:
#   * a segment under several labels was crossed by data: single-spaced words
#     (`Data directory`, `IDLE TIME`) are ONE label, unless every row holds
#     exactly that many tokens there (an unpadded table: token order); labels
#     2+ spaces apart (or separate rule runs) split at the least-occupied
#     position between them, which at most 1 row in 10 may cross;
#   * a labelled segment with no data, single-spaced to its neighbour in the
#     header (`Used` of `Used (GB)`, `on` of `Mounted on`), joins that label;
#     two or more spaces away it is a genuinely empty column and stays;
#   * a segment under no label (a value split by a gutter of its own) joins a
#     neighbour: leading -> right, trailing -> left, interior -> left unless
#     the right column is right-aligned only;
#   * an empty cell stays empty — nothing shifts left.
# Duplicate names get `_2`, `_3`; tail-wrapped / leading-overflow rows are
# rejoined as the positional grid does. Offsets are CHARACTER offsets
# (UTF-8 aware, wide characters two columns, then one — see "UTF-8" below).
# It WITHDRAWS (prints nothing) on < 2 columns, an unresolvable segment, a
# cell overflowing into the next column with one space, or when fewer than
# 80% of the cells start at their column modal start or end at its modal end
# (prose and ragged text are not offset-aligned). Shared by aligned-columns
# (bash and big-input paths alike, so they stay byte-identical) and
# fixed-width.
# ---------------------------------------------------------------------------
_FR_AWK_GRID='
function untab(s,    o, k, col) {
    o = ""; col = 0
    while ((k = index(s, "\t")) > 0) {
        o = o substr(s, 1, k - 1); col += k - 1
        do { o = o " "; col++ } while (col % 8)
        s = substr(s, k + 1)
    }
    return o s
}
# palign(q): RA / LA = 1 when every cell of part q ends / starts at one
# position (right- / left-aligned); 0 when the part holds no cell
function palign(q,    r, t, fs, fe, cs, ce) {
    RA = 1; LA = 1; cs = -1; ce = -1
    for (r = d0; r <= n; r++) {
        fs = 0; fe = 0
        for (t = FT[r]; t < FT[r] + NT[r]; t++) if (TP[t] == q) { if (!fs) fs = TS[t]; fe = TE[t] }
        if (!fs) continue
        if (ce < 0) { ce = fe; cs = fs } else { if (fe != ce) RA = 0; if (fs != cs) LA = 0 }
    }
    if (ce < 0) { RA = 0; LA = 0 }
}
# isunit(v): a unit word (`GiB`, `ms`, `ago`, ...)
function isunit(v) {
    return v ~ /^([KMGTPE]i?B|[KMGTPE]|[kKMGTP]?[Bb]|bytes|[mun]?s|sec|min|hours?|days?|ago|%)$/
}
# pcells(q): every non-empty cell of part q is a number-led value (ISNUM) /
# a unit word or one constant short word (ISUNIT; a word is only seen to be
# constant in 2+ rows); PROWS marks the rows holding a cell
function pcells(q,    r, t, v, c, v0, nc, cw) {
    ISNUM = 1; ISUNIT = 1; PROWS = ""; v0 = ""; nc = 0; cw = 0
    for (r = d0; r <= n; r++) {
        v = ""; c = 0
        for (t = FT[r]; t < FT[r] + NT[r]; t++) if (TP[t] == q) { v = (c++ ? v " " : "") TX[t] }
        if (c == 0) { PROWS = PROWS "0"; continue }
        PROWS = PROWS "1"; nc++
        if (v !~ /^[-+]?[0-9]/ || c > 1) ISNUM = 0
        if (v0 == "") v0 = v
        if (c > 1 || !(isunit(v) || (v == v0 && v ~ /^[A-Za-z]+$/ && length(v) <= 5))) ISUNIT = 0
        if (!isunit(v)) cw = 1
    }
    if (cw && nc < 2) ISUNIT = 0
}
# sgok(a, b): the stretch a..b-1 is a soft gutter — the text left of it is
# printed by most rows, and every row printing in it has its next cell 2+
# columns past the text before it
function sgok(a, b,    r, t, hit, lt) {
    lt = 0
    for (r = d0; r <= n; r++) {
        hit = 0
        for (t = FT[r]; t < FT[r] + NT[r]; t++) {
            if (TS[t] < a && TE[t] >= SS[k]) lt++
            if (TE[t] >= a && TS[t] < b) hit = t
            else if (hit && TS[t] >= b) { if (TS[t] - TE[t - 1] < 3) return 0; break }
        }
    }
    return (lt * 2 >= nrow)
}
# splits1(p, lo): in how many rows a cut at p (tokens from p on go right)
# separates two words one space apart of which the left one lies in the gap
# (ends at lo or later)
function splits1(p, lo,    r, t, m) {
    m = 0
    for (r = d0; r <= n; r++)
        for (t = FT[r] + 1; t < FT[r] + NT[r]; t++)
            if (TS[t] >= p && TS[t - 1] < p) {
                if (TE[t - 1] >= lo && TS[t] - TE[t - 1] == 2) m++
                break
            }
    return m
}
# dsplit(k, ng): GB[1..ng-1], the boundaries between the label groups of
# segment k, from the data-only gutters; 0 when they cannot be assigned
function dsplit(k, ng,    p, ns_, a, b, g, best, bov, lo, hi, ov, dd, bd, last, SA, SB, SG) {
    ns_ = 0; a = 0
    for (p = SS[k]; p <= SE[k] + 1; p++) {
        if (p <= SE[k] && OC[p] > 0) { if (!a) a = p }
        else if (a) { ns_++; SA[ns_] = a; SB[ns_] = p - 1; a = 0 }
    }
    if (ns_ < ng) return 0
    last = 1
    for (b = 1; b <= ns_; b++) {
        best = 0; bov = 0; bd = 0
        for (g = 1; g <= ng; g++) {
            lo = LS[G1[g]]; hi = LE[G1[g] + GN[g] - 1]
            ov = ((SB[b] < hi) ? SB[b] : hi) - ((SA[b] > lo) ? SA[b] : lo) + 1
            if (ov > 0) bd++
            if (ov > bov) { bov = ov; best = g }
        }
        # (a sub-column under two label groups says nothing about either)
        if (!best || bd > 1) return 0
        if (best < last || best > last + 1) return 0
        SG[b] = best; last = best
    }
    if (last != ng) return 0
    for (b = 2; b <= ns_; b++) if (SG[b] != SG[b - 1]) GB[SG[b - 1]] = SA[b] - 1
    return 1
}
function isbar(v) { return v == "|" || v == "\342\224\202" || v == "\342\224\203" }
function letter(i,    r, k, s) {
    r = (i - 1) % 26 + 1; k = int((i - 1) / 26) + 1; s = ""
    while (k-- > 0) s = s substr("ABCDEFGHIJKLMNOPQRSTUVWXYZ", r, 1)
    return s
}
# --- UTF-8: offsets count CHARACTERS, not bytes (mawk counts bytes) ---
# A line holding bytes >= 0x80 is re-coded before any offset is taken:
# each UTF-8 character becomes ONE placeholder byte \001 (two, \001\002,
# for a wide East Asian / emoji character in display mode), and its bytes
# are kept in SQ[line, i] for the i-th placeholder; a zero-width mark
# (combining accent, ZWJ, variation selector) rides on the character before
# it. Cells are decoded back to their bytes (u8dec) as tokens are read.
# u8w(q): display width of one UTF-8 sequence — 0, 1 or 2
function u8w(q) {
    if (q ~ /^(\314[\200-\277]|\315[\200-\257]|\342\200[\213-\217]|\342\203[\220-\277]|\357\270[\200-\217])$/) return 0
    if (q ~ /^(\341\204|\341\205[\200-\237]|\342[\272-\277]|\343|\344|\345|\346|\347|\350|\351|\352[\200-\222]|\352[\260-\277]|\353|\354|\355[\200-\236]|\357[\244-\253]|\357\270[\260-\277]|\357\271[\200-\257]|\357\274|\357\275[\200-\240]|\357\277[\240-\246])/) return 2
    if (q ~ /^\342(\214[\232\233]|\217[\251-\254\260\263]|\227[\275\276]|\230[\224\225]|\231[\210-\223\277]|\232[\223\241\252\253\275\276]|\233[\204\205\216\224\252\262\263\265\272\275]|\234[\205\212\213\250]|\235[\214\216\223-\225\227]|\236[\225-\227\260\277]|\254[\233\234]|\255[\220\225])$/) return 2
    if (q ~ /^\360(\237[\210-\213\214-\233\244-\253]|[\240-\277])/) return 2
    return 1
}
function u8enc(s, r,    o, q, w, k, z) {
    o = ""; k = 0
    while (match(s, /[\200-\377][\200-\277]*/)) {
        o = o substr(s, 1, RSTART - 1)
        q = substr(s, RSTART, RLENGTH); s = substr(s, RSTART + RLENGTH)
        w = (uw == 2) ? u8w(q) : 1
        if (w != 1) WIDE = 1
        # (a Unicode space next to another space — `a<thin><thin>1` — is
        # padding, a plain space; a lone one inside a cell, the thousands
        # separator of `67<nbsp>390<nbsp>000`, stays part of the cell)
        if (q ~ /^(\302\240|\342\200[\200-\212]|\342\200\257|\343\200\200)$/ \
            && (substr(o, length(o), 1) == " " || s ~ /^( |\302\240|\342\200[\200-\212]|\342\200\257|\343\200\200)/)) {
            o = o ((w == 2) ? "  " : " "); continue
        }
        if (w == 0) {
            z = substr(o, length(o), 1)
            if (z == "\001" || z == "\002") { SQ[r, k] = SQ[r, k] q; continue }
            if (z != "" && z != " " && z != "\t") {
                o = substr(o, 1, length(o) - 1) "\001"; SQ[r, ++k] = z q; continue
            }
            w = 1
        }
        SQ[r, ++k] = q; o = o "\001"
        if (w == 2) o = o "\002"
    }
    return o s
}
# u8dec(r, a, x): the bytes of display text x found at offset a of line r
function u8dec(r, a, x,    c, pre, o, j) {
    if (!U[r]) return x
    pre = substr(L[r], 1, a - 1); c = gsub(/\001/, "", pre)
    gsub(/\002/, "", x); o = ""
    while ((j = index(x, "\001")) > 0) { o = o substr(x, 1, j - 1) SQ[r, ++c]; x = substr(x, j + 1) }
    return o x
}
function prep(s, r) {
    if (U[r]) s = u8enc(s, r)
    if (index(s, "\t")) { s = untab(s); TAB[r] = 1 }
    sub(/ +$/, "", s)
    return s
}
function greset() {
    delete HS; delete HE; delete HX; delete HD; delete QS; delete QE; delete OD
    delete TS; delete TE; delete TX; delete FT; delete NT; delete HM; delete OC
    delete SS; delete SE; delete LS; delete LE; delete LN; delete LG; delete SL1
    delete SLN; delete PA; delete PB; delete PL1; delete PLN; delete PO; delete G1
    delete GN; delete TP; delete PN; delete OW; delete CID; delete PC; delete CN
    delete CO; delete CA; delete CB; delete UP; delete NW; delete PU; delete WW
    delete NM; delete SEEN; delete CELL; delete CS; delete CTK; delete CEND
    delete MS; delete ME; delete OUTC; delete DROP; delete GB; delete PGN; delete MST; delete MEN; delete ROWT; delete CG2; delete MKC
    nord = 0
}
BEGIN { if (pfx == "") pfx = "entry"; uw = 2 }
{
    s = $0
    sub(/\r$/, "", s)
    n++
    if (s ~ /[\001\002\200-\377]/) {
        if (s ~ /[\001\002]/) bad = 1
        if (s ~ /[\200-\377]/) { U[n] = 1; R[n] = s }
        L[n] = prep(s, n)
    } else {
        if (index(s, "\t")) { s = untab(s); TAB[n] = 1 }
        sub(/ +$/, "", s)
        L[n] = s
    }
}
# Wide characters are first counted as two columns (what a terminal shows:
# `column`, `ls`, util-linux tables); when the offsets do not hold, as one
# (tools that pad by character count: Go tabwriter, Python ljust).
END {
    if (bad) exit
    if (grid() || !WIDE) exit
    uw = 1
    for (r = 1; r <= n; r++) if (U[r]) L[r] = prep(R[r], r)
    grid()
}
# grid(): 1 when it printed the table, 0 when it withdrew (printed nothing)
function grid() {
    greset()
    d0 = nh + rl + 1
    hx = nh
    # a header printed with TABs over data printed with spaces (or the other
    # way round) has offsets that say nothing about the data
    if (nh && n >= d0) {
        dt = 0
        for (r = d0; r <= n; r++) if (TAB[r]) { dt = 1; break }
        if (TAB[hx] != dt) return 0
    }
    if (n < d0) return 0
    W = 0
    for (r = 1; r <= n; r++) if (length(L[r]) > W) W = length(L[r])
    # --- header tokens ---
    nht = 0
    if (nh) {
        s = L[hx]; off = 0
        while (match(s, /[^ ]+/)) {
            nht++; HS[nht] = off + RSTART; HE[nht] = HS[nht] + RLENGTH - 1
            HX[nht] = substr(s, RSTART, RLENGTH); off = HE[nht]
            if (U[hx]) HX[nht] = u8dec(hx, HS[nht], HX[nht])
            s = substr(s, RSTART + RLENGTH)
            HD[HS[nht]]++; HD[HE[nht] + 1]--
        }
        if (nht == 0) return 0
        # a `label: value` line (`pool: tank`) is a caption, not labels
        if (nht <= 3 && HX[1] ~ /:$/) return 0
    }
    # --- rule runs ---
    nr = 0
    if (rl) {
        s = L[nh + 1]
        if (s !~ /^ *[-=]+( +[-=]+)* *$/) return 0
        off = 0
        while (match(s, /[-=]+/)) {
            nr++; QS[nr] = off + RSTART; QE[nr] = QS[nr] + RLENGTH - 1
            off = QE[nr]; s = substr(s, RSTART + RLENGTH)
        }
        # (one unbroken rule names no columns: it is only skipped)
        if (nr >= 2) { for (j = 1; j <= nr; j++) { HD[QS[j]]++; HD[QE[j] + 1]-- } }
        else nr = 0
    }
    ur = (nr >= 2)
    hgap = 0
    if (nh) { hl = L[hx]; sub(/^ +/, "", hl); hgap = (hl ~ /[^ ]  +[^ ]/) }
    # --- data tokens + occupancy ---
    nt = 0; nrow = 0
    for (r = d0; r <= n; r++) {
        s = L[r]; off = 0; FT[r] = nt + 1; ur_ = (r in U)
        while (match(s, /[^ ]+/)) {
            nt++; TS[nt] = off + RSTART; TE[nt] = TS[nt] + RLENGTH - 1
            TX[nt] = substr(s, RSTART, RLENGTH); off = TE[nt]
            if (ur_) TX[nt] = u8dec(r, TS[nt], TX[nt])
            s = substr(s, RSTART + RLENGTH)
            OD[TS[nt]]++; OD[TE[nt] + 1]--
        }
        NT[r] = nt - FT[r] + 1
        if (NT[r] > 0) nrow++
    }
    if (nrow == 0) return 0
    # a LABEL-LIKE first row (at most 1 token in 4 a number) over rows that
    # are numbers (4 rows in 5 of the rest at least half numeric tokens) is a
    # second header line (`KB/s in  KB/s out` under `eth0  wlan0`, `1 min
    # swpd free` under `loadavg memory`), not data: this header names nothing
    # below it
    if (nh) {
        fr = 0; dg = 0; ot = 0
        for (r = d0; r <= n; r++) {
            if (!NT[r]) continue
            c = 0
            for (t = FT[r]; t < FT[r] + NT[r]; t++) if (TX[t] ~ /^[-+]?[0-9]/) c++
            if (!fr) { fr = r; fc = c; continue }
            ot++; if (c * 2 >= NT[r]) dg++
        }
        if (fr && fc * 4 <= NT[fr] && ot >= 2 && dg * 10 >= ot * 8) return 0
    }
    hc = 0; oc = 0
    for (p = 1; p <= W; p++) { hc += HD[p]; oc += OD[p]; HM[p] = (hc > 0); OC[p] = oc }
    # --- segments: maximal runs of positions some line (header, rule or
    # data) prints on; the runs between them are GUTTERS ---
    ns = 0; in_ = 0
    for (p = 1; p <= W; p++) {
        if (HM[p] || OC[p] > 0) { if (!in_) { ns++; SS[ns] = p; in_ = 1 } }
        else if (in_) { SE[ns] = p - 1; in_ = 0 }
    }
    if (in_) SE[ns] = W
    # headerless (nh=0): a SOFT gutter — a stretch (2+ wide) inside a segment
    # that at most 1 row in 10 prints on (at least 1 from 5 rows), with
    # printing on both sides — is a gutter that a few over-long cells run
    # through, as when a TAB-separated listing pushes the next field of one row to
    # the following stop (`-Wanalyzer-exposure-through-uninit-copy` among
    # short options). Split there only when, in every row printing in the
    # stretch, the first cell after it sits 2+ columns past the text before
    # it (a gutter in that row too): a long multi-word cell running INTO
    # the next column has a single space there and keeps the segment whole.
    if (!nh && nrow >= 5) {
        al = int((nrow + 5) / 10)
        for (k = 1; k <= ns; k++) {
            vs = 0
            for (p = SS[k] + 1; p <= SE[k]; p++) {
                low = (OC[p] <= al)
                if (low && !vs) vs = p
                if (!low && vs) {
                    if (p - vs >= 2 && sgok(vs, p)) {
                        for (x = ns; x > k; x--) { SS[x + 1] = SS[x]; SE[x + 1] = SE[x] }
                        ns++; SS[k + 1] = p; SE[k + 1] = SE[k]; SE[k] = p - 1
                        break
                    }
                    vs = 0
                }
            }
        }
    }
    # --- labels: rule runs (named by the header tokens over them), else the
    # header tokens themselves ---
    nl = 0
    if (ur) {
        nl = nr
        for (j = 1; j <= nl; j++) { LS[j] = QS[j]; LE[j] = QE[j]; LN[j] = "" }
        for (t = 1; t <= nht; t++) {
            bj = 0; bo = 0
            for (j = 1; j <= nl; j++) {
                lo = (HS[t] > QS[j]) ? HS[t] : QS[j]; hi = (HE[t] < QE[j]) ? HE[t] : QE[j]
                if (hi - lo + 1 > bo) { bo = hi - lo + 1; bj = j }
            }
            if (!bj) {
                bd = -1
                for (j = 1; j <= nl; j++) {
                    dd = (HE[t] < QS[j]) ? QS[j] - HE[t] : HS[t] - QE[j]
                    if (bd < 0 || dd < bd) { bd = dd; bj = j }
                }
            }
            LN[bj] = (LN[bj] == "") ? HX[t] : LN[bj] " " HX[t]
            if (HS[t] < LS[bj]) LS[bj] = HS[t]
            if (HE[t] > LE[bj]) LE[bj] = HE[t]
        }
    } else if (nh) {
        nl = nht
        for (j = 1; j <= nl; j++) { LS[j] = HS[j]; LE[j] = HE[j]; LN[j] = HX[j] }
    }
    # label -> segment (both in left-to-right order)
    k = 1
    for (j = 1; j <= nl; j++) {
        while (k < ns && LS[j] > SE[k]) k++
        LG[j] = k
        if (!(k in SL1)) SL1[k] = j
        SLN[k]++
    }
    # a table every row of which holds exactly one token per header label
    # reads the same by tokens: nothing for offsets to fix (and an unpadded,
    # single-spaced table has no trustworthy offsets at all)
    cnteq = 0
    if (!ur && nh) {
        same = 1
        for (r = d0; r <= n; r++) if (NT[r] && NT[r] != nl) { same = 0; break }
        cnteq = same
        if (same) return 0
    }
    # --- parts: each segment becomes one or more parts ---
    np = 0
    for (k = 1; k <= ns; k++) {
        m = SLN[k] + 0
        if (m == 0) { np++; PA[np] = SS[k]; PB[np] = SE[k]; PL1[np] = 0; PLN[np] = 0; PO[np] = 0; continue }
        j1 = SL1[k]
        # groups of labels: a rule run, or a 2+-space header gap, starts one
        ng = 1; G1[1] = j1; GN[1] = 1
        for (j = j1 + 1; j < j1 + m; j++) {
            if (ur || LS[j] - LE[j - 1] - 1 >= 2) { ng++; G1[ng] = j; GN[ng] = 1 }
            else GN[ng]++
        }
        # soft boundaries between groups: the least-occupied header-blank
        # position; a few overflowing rows may cross it, no more
        bad_ = 0
        for (g = 1; g < ng; g++) {
            lo = LE[G1[g] + GN[g] - 1] + 1; hi = LS[G1[g + 1]] - 1
            # (the least-occupied position, nearest the middle — but not one
            # between two words of a cell that crosses the gap, `Full Repair
            # | Needed`, in more rows than the 1-in-10 allowance: candidates
            # are tried best first, so a clean table pays for one test per
            # boundary)
            mid = (lo + hi) / 2; delete REJ
            while (1) {
                bp = 0; bo = -1
                for (p = lo; p <= hi; p++) {
                    if (p in REJ) continue
                    dd = p - mid; if (dd < 0) dd = -dd
                    if (bo < 0 || OC[p] < bo || (OC[p] == bo && dd < bdd)) { bo = OC[p]; bp = p; bdd = dd }
                }
                if (!bp || splits1(bp, lo) <= int(nrow / 10)) break
                REJ[bp] = 1
            }
            if (bp == 0) bp = hi + 1
            # (beyond 1 row in 10, ONE row may cross in a small table when
            # its cell starts left of the gap and ends at most a column
            # into it: `Full Repair Needed` a character past its label)
            if (bo == 1 && nrow >= 5 && bo > int(nrow / 10)) {
                for (r = d0; r <= n; r++)
                    for (t = FT[r]; t < FT[r] + NT[r]; t++)
                        if (TS[t] <= bp && TE[t] >= bp && (TS[t] >= lo || TE[t] > lo)) bo = 2
            }
            if (bo < 0 || bo > int(nrow / 10) && bo != 1) { bad_ = 1; break }
            if (bo == 1 && nrow < 5 && int(nrow / 10) < 1) { bad_ = 1; break }
            GB[g] = bp - 1
        }
        # (the rows cross a boundary in force: the header was printed with a
        # format of its own, `method  crc     date  time` over `defla
        # 1c2b3a4d Oct  1 08:01`. Then the DATA must align among themselves:
        # their own gutters, blank in every row, cut the segment into
        # sub-columns, each going to the ONE label group it overlaps, left
        # to right, every group getting one)
        # (not when every row holds one token per label: the token reading
        # is right there, and a loose header gives nothing better)
        if (bad_ && (cnteq || !dsplit(k, ng))) return 0
        ga = SS[k]
        for (g = 1; g <= ng; g++) {
            gb = (g < ng) ? GB[g] : SE[k]
            gm = GN[g]
            if (gm == 1) {
                np++; PA[np] = ga; PB[np] = gb; PL1[np] = G1[g]; PLN[np] = 1; PO[np] = 0
            } else {
                # single-spaced words: separate columns only when EVERY row
                # holds exactly that many tokens here (an unpadded table —
                # token order is then the answer); otherwise one label
                # (not when a bare `/` or `|` joins the tokens — one
                # composite value, `1.2MB / 3.4MB` — nor when the values run
                # on into a label-less segment next door)
                allm = 1; any = 0; nu = (gm == 2); u0 = ""; uc = 1; n2 = 0
                # (in the LAST label group of the line a row may stop short —
                # an empty trailing cell, lsblk `0 disk` under `RO TYPE
                # MOUNTPOINTS` — or run on past the words, `[total of 2
                # files]` on a totals row, as long as one row, or 1 in 5,
                # runs on; each token still sits under its word)
                lastg = (g == ng && k == ns); nex = 0; nrw = 0; nro = 0
                if (g == ng && k < ns && !SLN[k + 1]) allm = 0
                for (r = d0; r <= n && allm; r++) {
                    c = 0; lastp = 0
                    for (t = FT[r]; t < FT[r] + NT[r]; t++) if (TS[t] >= ga && TS[t] <= gb) {
                        c++
                        if (lastp) allm = 0
                        lastp = (TX[t] ~ /^[\/|]$/)
                        if (c == 1 && TX[t] !~ /^[-+]?[0-9]/) nu = 0
                        if (c == 2) {
                            n2++
                            if (u0 == "") u0 = TX[t]; else if (TX[t] != u0) uc = 0
                            if (!isunit(TX[t]) && TX[t] !~ /^[A-Za-z]+$/) nu = 0
                            if (length(TX[t]) > 5 && !isunit(TX[t])) nu = 0
                        }
                    }
                    if (c > 0) {
                        any = 1; nrw++
                        if (c == gm) nex++
                        else if (c > gm && lastg) nro++
                        else if (!lastg) allm = 0
                    }
                }
                if (allm && nro > 1 && nro * 5 > nrw) allm = 0
                if (allm && !nex) allm = 0
                # (a number and its unit, `512 MiB` / `412034 SOL`, is one
                # value: a unit word, or one constant short word — constant
                # only when 2+ rows show it: one row proves nothing)
                if (nu && n2 < 2) uc = 0
                if (nu && (uc || isunit(u0))) {
                    for (r = d0; r <= n && nu; r++)
                        for (t = FT[r]; t < FT[r] + NT[r]; t++)
                            if (TS[t] >= ga && TS[t] <= gb && TX[t] ~ /^[A-Za-z]+$/ && !isunit(TX[t]) && !uc) nu = 0
                    if (nu) allm = 0
                }
                # ...and the i-th token sits under the i-th word (its start or
                # end on the word, +-1) in 4 rows out of 5
                for (j = 0; j < gm && allm && any; j++) {
                    jj = G1[g] + j; hit = 0; den = 0
                    for (r = d0; r <= n; r++) {
                        c = 0
                        for (t = FT[r]; t < FT[r] + NT[r]; t++) {
                            if (TS[t] < ga || TS[t] > gb) continue
                            if (c++ != j) continue
                            den++
                            dd = TS[t] - LS[jj]; if (dd < 0) dd = -dd
                            de = TE[t] - LE[jj]; if (de < 0) de = -de
                            if (dd <= 1 || de <= 1) hit++
                        }
                    }
                    if (den == 0 || hit * 10 < den * 8) allm = 0
                }
                if (any && allm) {
                    for (j = 0; j < gm; j++) { np++; PA[np] = ga; PB[np] = gb; PL1[np] = G1[g] + j; PLN[np] = 1; PO[np] = j + 1; PGN[np] = gm }
                    nord++
                } else if (gm <= 4) {
                    np++; PA[np] = ga; PB[np] = gb; PL1[np] = G1[g]; PLN[np] = gm; PO[np] = 0
                } else return 0
            }
            ga = gb + 1
        }
    }
    # --- tokens -> parts ---
    for (r = d0; r <= n; r++) {
        q = 1; curg = 0; oi = 0
        for (t = FT[r]; t < FT[r] + NT[r]; t++) {
            while (q < np && TS[t] > PB[q]) q++
            # (an ordered group shares one span, and the lookup lands on its
            # first part: the i-th token of the row there takes part i)
            if (PO[q] > 0) {
                if (q != curg) { curg = q; oi = 0 }
                tq = q + ((oi < PGN[q]) ? oi : PGN[q] - 1); oi++
            } else tq = q
            TP[t] = tq
            PN[tq]++
        }
    }
    # --- merge parts into columns: OW[q] = the part q joins ---
    for (q = 1; q <= np; q++) OW[q] = q
    # a data-empty labelled part, single-spaced in the header to a neighbour
    # label (`Used` of `Used (GB)`, `on` of `Mounted on`, `All time` of `All
    # time blocked`), is part of that label: it joins the side whose values
    # it sits nearer, through any other data-empty words of the label
    if (!ur) {
        for (q = 1; q <= np; q++) {
            if (PN[q] || !PLN[q] || PO[q]) continue
            # nearest data-bearing labelled part reachable through single
            # spaces, each way
            dl = -1; for (x = q - 1; x >= 1; x--) {
                if (!PLN[x] || LS[PL1[x + 1]] - LE[PL1[x] + PLN[x] - 1] - 1 != 1) break
                if (PN[x]) { dl = x; break }
            }
            dr = -1; for (x = q + 1; x <= np; x++) {
                if (!PLN[x] || LS[PL1[x]] - LE[PL1[x - 1] + PLN[x - 1] - 1] - 1 != 1) break
                if (PN[x]) { dr = x; break }
            }
            if (dl > 0 && dr > 0) {
                # nearer to whose values?
                le_ = 0; rs_ = 0
                for (t = 1; t <= nt; t++) { if (TP[t] == dl && TE[t] > le_) le_ = TE[t]; if (TP[t] == dr && (!rs_ || TS[t] < rs_)) rs_ = TS[t] }
                if (rs_ - LE[PL1[q] + PLN[q] - 1] < LS[PL1[q]] - le_) dl = -1; else dr = -1
            }
            if (dl > 0) OW[q] = dl; else if (dr > 0) OW[q] = dr
        }
        # a number split from its unit by a one-space gutter under a
        # one-space label (`RAW USE` over `180 GiB`) is one value
        for (q = 1; q < np; q++) {
            if (!PLN[q] || !PLN[q + 1] || !PN[q] || !PN[q + 1] || PO[q] || PO[q + 1]) continue
            if (LS[PL1[q + 1]] - LE[PL1[q] + PLN[q] - 1] - 1 != 1 || PA[q + 1] - PB[q] - 1 != 1) continue
            pcells(q); nu = ISNUM; rq = PROWS
            pcells(q + 1)
            if (nu && ISUNIT && PROWS == rq) OW[q + 1] = q
        }
        # two labels ONE space apart over parts ONE column apart, the left
        # holding the SAME single word in every row and the right several
        # tokens in some: one label over one cell whose constant first word
        # ends in the same place in every row (`CREATED BY` over `/bin/sh -c
        # #(nop)  CMD ...`), not two columns
        for (q = 1; q < np; q++) {
            if (!PLN[q] || !PLN[q + 1] || !PN[q] || !PN[q + 1] || PO[q] || PO[q + 1] || OW[q + 1] != q + 1) continue
            if (LS[PL1[q + 1]] - LE[PL1[q] + PLN[q] - 1] - 1 != 1 || PA[q + 1] - PB[q] - 1 != 1) continue
            # (the right cell runs on through any label-less parts after it)
            l1 = 1; r2 = 0; qe = q + 1; w1 = ""
            while (qe < np && !PLN[qe + 1]) qe++
            if (qe == np && !PLN[qe]) qe = q + 1
            for (r = d0; r <= n && l1; r++) {
                cl = 0; cr = 0
                for (t = FT[r]; t < FT[r] + NT[r]; t++) {
                    if (TP[t] == q) { cl++; if (w1 == "") w1 = TX[t]; else if (TX[t] != w1) l1 = 0 }
                    else if (TP[t] > q && TP[t] <= qe) cr++
                }
                if (cl != 1) l1 = 0
                if (cr > 1) r2 = 1
            }
            if (l1 && r2 && w1 ~ /[A-Za-z]/) OW[q + 1] = q
        }
    }
    # a run of label-less parts: a LEADING run is a column of its own (the
    # row labels of `free`, `numastat`, /proc/interrupts); a TRAILING run
    # continues the last column unless that one is right-aligned numbers
    # (then each of its parts is a column of its own); an interior run joins
    # the left neighbour, unless the right one is right-aligned and in EVERY
    # row the run sits closer to its value than to the previous one (a value
    # right-aligned under a short label)
    fl = 0; ll = 0
    for (q = 1; q <= np; q++) if (PLN[q]) { if (!fl) fl = q; ll = q }
    if (nh && !fl) return 0
    q = 1
    while (nh && q <= np) {
        if (PLN[q]) { q++; continue }
        a = q; while (q <= np && !PLN[q]) q++; b = q - 1
        if (a < fl) tgt = a
        else if (b > ll) {
            # (beyond the last label of a single-spaced header the data has
            # columns the header never names: no offsets to trust)
            if (!hgap && !ur) return 0
            palign(ll)
            if (RA && !LA) { for (x = a; x <= b; x++) OW[x] = x; continue }
            tgt = ll
        }
        else {
            palign(b + 1); right = (RA && !PO[b + 1]); seen = 0
            for (r = d0; r <= n && right; r++) {
                fs = 0; fe = 0; pe = -1; ns = -1
                for (t = FT[r]; t < FT[r] + NT[r]; t++) {
                    if (TP[t] < b) pe = TE[t]
                    else if (TP[t] == b) { if (!fs) fs = TS[t]; fe = TE[t] }
                    else if (ns < 0) ns = TS[t]
                }
                if (!fs) continue
                seen = 1
                if (ns < 0 || (pe >= 0 && ns - fe >= fs - pe)) right = 0
            }
            tgt = (right && seen) ? b + 1 : a - 1
            # (a run holding only a one-character marker, `>` / `*`, on the
            # rows it marks is a marker column of its own)
            # (set off by 2+ spaces on both sides)
            mk = 1
            for (r = d0; r <= n && mk; r++)
                for (t = FT[r]; t < FT[r] + NT[r]; t++) {
                    if (TP[t] < a || TP[t] > b) continue
                    if (TX[t] !~ /^[^A-Za-z0-9]$/) { mk = 0; break }
                    if (t > FT[r] && TS[t] - TE[t - 1] < 3) { mk = 0; break }
                    if (t + 1 < FT[r] + NT[r] && TS[t + 1] - TE[t] < 3) { mk = 0; break }
                }
            if (mk) tgt = a
            # (...and so is a run holding the SAME lone sign in every row,
            # the `±` between a score and its error)
            if (!mk) {
                mk = 1; mv = ""
                for (r = d0; r <= n && mk; r++) {
                    c = 0
                    for (t = FT[r]; t < FT[r] + NT[r]; t++) {
                        if (TP[t] < a || TP[t] > b) continue
                        c++
                        if (TX[t] ~ /[A-Za-z0-9]/ || length(TX[t]) > 2) { mk = 0; break }
                        if (mv == "") mv = TX[t]; else if (TX[t] != mv) mk = 0
                    }
                    if (c != 1) mk = 0
                }
                if (mk && mv ~ /^[-+]$/) mk = 0
                if (mk) tgt = a
            }
        }
        for (x = a; x <= b; x++) OW[x] = tgt
    }
    # a bare `/` label over bare `/` cells (`Total / Used / Free` over
    # `4 TiB / 2.1 TiB / 1.9 TiB`) is the inside of ONE composite column:
    # it joins its left neighbour, and so does the right one
    for (q = 2; q < np; q++) {
        if (PLN[q] != 1 || LN[PL1[q]] != "/" || !PN[q]) continue
        ok = 1
        for (t = 1; t <= nt && ok; t++) if (TP[t] == q && TX[t] != "/") ok = 0
        if (!ok || !PLN[q - 1] || !PLN[q + 1]) continue
        o = q - 1; while (OW[o] != o) o = OW[o]
        OW[q] = o
        o2 = q + 1; while (OW[o2] != o2) o2 = OW[o2]
        if (o2 > q) OW[o2] = o
    }
    # headerless (nh=0): with no header to say so, a ONE-space gutter is a
    # space inside a cell when, in 2+ rows, the text on both sides touches it
    # (`Microsoft Remote Desktop` over `Slack for Desktop`) — unless the
    # left side is right-aligned numbers (the counts of `uniq -c`) or a flag
    # column (one value, or at most 2 characters: `ii`); a gutter only the
    # widest cell reaches is column padding
    if (!nh) {
        for (q = 2; q <= np; q++) {
            gp = PB[q - 1] + 1
            if (PA[q] - PB[q - 1] - 1 != 1) continue
            palign(q - 1); pcells(q - 1)
            if (RA && ISNUM) continue
            ab = 0; fl1 = 1; fv = ""; sh = 1; nlr = 0; nrr_ = 0
            for (r = d0; r <= n; r++) {
                le = 0; rs = 0; lv = ""
                for (t = FT[r]; t < FT[r] + NT[r]; t++) {
                    if (TP[t] == q - 1) { le = TE[t]; lv = (lv == "") ? TX[t] : lv " " TX[t] }
                    if (TP[t] == q && !rs) rs = TS[t]
                }
                if (lv != "") { nlr++; if (fv == "") fv = lv; else if (lv != fv) fl1 = 0; if (length(lv) > 2) sh = 0 }
                if (rs) nrr_++
                if (le == gp - 1 && rs == gp + 1) ab++
            }
            # (text the right side holds in FEWER rows than the left is the
            # tail of a longer cell, never a column of its own)
            if (nrr_ >= nlr && (fl1 || sh || ab < 2)) continue
            o = q - 1; while (OW[o] != o) o = OW[o]
            OW[q] = o
        }
    }
    # column ids, left to right (an owner may itself have joined another)
    nc = 0
    for (q = 1; q <= np; q++) {
        o = OW[q]; while (OW[o] != o) o = OW[o]
        if (!(o in CID)) CID[o] = ++nc
        PC[q] = CID[o]
    }
    if (nc < 2) return 0
    # column names: label words in order
    for (q = 1; q <= np; q++) {
        c = PC[q]
        for (j = PL1[q]; j < PL1[q] + PLN[q]; j++) CN[c] = (CN[c] == "") ? LN[j] : CN[c] " " LN[j]
        if (PO[q]) CO[c] = 1
    }
    # group row (nh=2): each word prefixes the ONE column it sits over; a
    # word spanning two columns (`----memory----`) is a different header
    # shape, so the grid withdraws
    if (nh == 2) {
        for (q = 1; q <= np; q++) {
            c = PC[q]
            if (!(c in CA) || PA[q] < CA[c]) CA[c] = PA[q]
            if (!(c in CB) || PB[q] > CB[c]) CB[c] = PB[q]
        }
        s = L[1]; off = 0
        while (match(s, /[^ ]+/)) {
            us = off + RSTART; ue = us + RLENGTH - 1; ux = u8dec(1, us, substr(s, RSTART, RLENGTH))
            off = ue; s = substr(s, RSTART + RLENGTH)
            bc = 0; bo = 0; nov = 0
            for (c = 1; c <= nc; c++) {
                lo = (us > CA[c]) ? us : CA[c]; hi = (ue < CB[c]) ? ue : CB[c]
                if (hi >= lo) { nov++; if (hi - lo + 1 > bo) { bo = hi - lo + 1; bc = c } }
            }
            if (nov > 1 || !bc) return 0
            UP[bc] = (UP[bc] == "") ? ux : UP[bc] " " ux
        }
        for (c = 1; c <= nc; c++) if (UP[c] != "") CN[c] = (CN[c] == "") ? UP[c] : UP[c] " " CN[c]
    }
    for (c = 1; c <= nc; c++) {
        nw = split(CN[c], WW, " "); NW[c] = 0; PU[c] = 0
        for (x = 1; x <= nw; x++) { if (WW[x] ~ /[A-Za-z0-9]/) NW[c]++; else PU[c] = 1 }
        nm = CN[c]; if (nm ~ /[A-Za-z0-9]\.$/) sub(/\.$/, "", nm)
        gsub(/\./, "_", nm); gsub(/ /, "_", nm); gsub(/__+/, "_", nm)
        if (nm == "") nm = letter(c)
        if (nm in SEEN) { SEEN[nm]++; nm = nm "_" SEEN[nm] } else SEEN[nm] = 1
        NM[c] = nm
    }
    # --- cells ---
    nrr = 0
    for (r = d0; r <= n; r++) {
        if (!NT[r]) continue
        nrr++
        ROWT[nrr] = TAB[r]
        for (t = FT[r]; t < FT[r] + NT[r]; t++) {
            c = PC[TP[t]]
            if (CELL[nrr, c] == "") { CELL[nrr, c] = TX[t]; CS[nrr, c] = TS[t] }
            else { CELL[nrr, c] = CELL[nrr, c] " " TX[t]; if (TS[t] - TE[t - 1] > 2) CG2[nrr, c] = 1 }
            CTK[nrr, c]++
            CEND[nrr, c] = TE[t]
        }
    }
    # a header is not a data row: a label that every row repeats as its cell
    # (`Nintendo` over `Nintendo`) means the "header" is the first record;
    # and in a header with no 2+-space gap anywhere, a label of 3+ words over
    # cells of as many words in EVERY row is a sentence, not a label
    # (`Getting image source signatures` over `Copying blob a1b2c3d4 done`)
    for (c = 1; c <= nc && nh; c++) {
        if (CN[c] !~ /[A-Za-z0-9]/) continue
        eq = 1; full = 1
        for (i = 1; i <= nrr; i++) {
            if (CELL[i, c] != CN[c]) eq = 0
            if (CTK[i, c] < NW[c]) full = 0
        }
        if (eq || (NW[c] >= 3 && !PU[c] && !CO[c] && full && !hgap)) return 0
    }
    # headerless (nh=0): only a grid every row FILLS (no empty cell — nothing
    # names an empty column), 2-8 columns, each aligned on its own (4 cells
    # in 5 at its modal start or end); else the token reading stands
    if (!nh) {
        if (nc > 8) return 0
        # (an empty cell is allowed only where nothing needs naming: in a
        # sparse LEADING column — a group label printed on the first row of
        # its group, the source line number of a disassembly — and at the END of
        # a row, an optional last cell; never a hole between filled cells.
        # Each column holds 2+ cells.)
        # (and half the rows, at least, fill every column but the first;
        # and in a row printed with TABs no cell spans a wide gap — a TAB
        # expanded past the next stop, `events<TAB>topic` among longer
        # names, is a column boundary the offsets cannot show)
        # (a MARKER column — every cell one or two punctuation characters,
        # the `>>` of a jump target — may be empty anywhere)
        for (c = 1; c <= nc; c++) {
            MKC[c] = 1
            for (i = 1; i <= nrr && MKC[c]; i++) if (CELL[i, c] != "" && CELL[i, c] !~ /^[^A-Za-z0-9 ][^A-Za-z0-9 ]?$/) MKC[c] = 0
        }
        nfull = 0
        for (i = 1; i <= nrr; i++) {
            if (ROWT[i]) for (c = 1; c <= nc; c++) if (CG2[i, c]) return 0
            f = 0; gap = 0; e2 = 0
            for (c = 1; c <= nc; c++) {
                if (MKC[c]) continue
                if (CELL[i, c] != "") { if (gap) return 0; f++ }
                else { if (f || c > 1) gap = 1; if (c > 1) e2 = 1 }
            }
            if (!f) return 0
            if (!e2) nfull++
        }
        if (nfull * 2 < nrr) return 0
        for (c = 1; c <= nc; c++) {
            delete MS; delete ME; bs = 0; be = 0; nf = 0
            for (i = 1; i <= nrr; i++) {
                if (CELL[i, c] == "") continue
                nf++
                x = ++MS[CS[i, c]]; if (x > bs) bs = x
                x = ++ME[CEND[i, c]]; if (x > be) be = x
            }
            if (nf < 2 || (bs > be ? bs : be) * 10 < nf * 8) return 0
        }
    }
    # alignment gate: a cell is aligned when it starts at the column modal
    # start or ends at its modal end (token-order columns excepted)
    tot = 0; ali = 0
    for (c = 1; c <= nc; c++) {
        if (CO[c]) continue
        delete MS; delete ME; bs = 0; be = 0; vs = 0; ve = 0
        for (i = 1; i <= nrr; i++) {
            if (CELL[i, c] == "") continue
            x = ++MS[CS[i, c]]; if (x > bs) { bs = x; vs = CS[i, c] }
            x = ++ME[CEND[i, c]]; if (x > be) { be = x; ve = CEND[i, c] }
        }
        for (i = 1; i <= nrr; i++) {
            if (CELL[i, c] == "") continue
            tot++
            if (CS[i, c] == vs || CEND[i, c] == ve) ali++
        }
        MST[c] = vs; MEN[c] = ve
    }
    if (tot == 0 || ali * 10 < tot * 8) return 0
    # a cell that overflows and runs into the next column with a single
    # space (`9 (2m ago)` pushed left under `RESTARTS      AGE`) is cut by
    # the gutter the other rows leave there: when the cells on both sides
    # of such a one-space gap sit neither at their column modal start nor at
    # its modal end, the offsets of that row cannot be trusted
    if (nh && !ur) {
        ovr = 0
        for (r = d0; r <= n; r++)
            for (t = FT[r] + 1; t < FT[r] + NT[r]; t++) {
                if (TS[t] - TE[t - 1] != 2) continue
                c = PC[TP[t]]
                if (PC[TP[t - 1]] != c - 1 || CO[c] || CO[c - 1]) continue
                for (x = t; x + 1 < FT[r] + NT[r] && PC[TP[x + 1]] == c; x++) ;
                if (TS[t] == MST[c] || TE[x] == MEN[c]) continue
                # (...and the cell before it is out of place too: a tree
                # column indents its cells, after a well-aligned neighbour)
                for (y = t - 1; y > FT[r] && PC[TP[y - 1]] == c - 1; y--) ;
                if (TS[y] != MST[c - 1] && TE[t - 1] != MEN[c - 1]) { ovr++; break }
            }
        # (beyond the 1-in-10 allowance of misplaced rows)
        if (ovr > int(nrow / 10)) return 0
    }
    # --- wrapped cells: a row holding only its LAST cell continues the row
    # above; a row holding only its FIRST cell, over a row whose first cell is
    # empty, is the first cell of that row, printed early ---
    ne = 0
    for (i = 1; i <= nrr; i++) {
        f = 0; only1 = (CELL[i, 1] != ""); onlyl = (CELL[i, nc] != "")
        for (c = 1; c <= nc; c++) if (CELL[i, c] != "") f++
        if (f == 1 && onlyl && ne > 0) {
            OUTC[ne, nc] = (OUTC[ne, nc] == "") ? CELL[i, nc] : OUTC[ne, nc] " " CELL[i, nc]
            continue
        }
        if (f == 1 && only1 && i < nrr && CELL[i + 1, 1] == "") {
            nf = 0; for (c = 1; c <= nc; c++) if (CELL[i + 1, c] != "") nf++
            if (nf >= 1) { CELL[i + 1, 1] = CELL[i, 1]; continue }
        }
        ne++
        for (c = 1; c <= nc; c++) OUTC[ne, c] = CELL[i, c]
    }
    # a column that only ever holds the `|` its label is (a drawn column
    # rule: `Task  |  Runtime ms  |`) is a separator, not data
    for (c = 1; c <= nc; c++) {
        # (or a box-drawing bar, `│` / `┃`, whatever label word the bar
        # of the header was glued to: `ON │`)
        if (CN[c] != "|" && CN[c] != "" && !isbar(CN[c]) && CN[c] !~ / (\||\342\224\202|\342\224\203)$/) continue
        sep = 0
        for (i = 1; i <= ne; i++) {
            if (OUTC[i, c] == "") continue
            if (!isbar(OUTC[i, c])) { sep = 0; break }
            sep = 1
        }
        if (sep) DROP[c] = 1
    }
    # a labelled column empty in EVERY row, while 1 row in 2 of another
    # column holds a 2+-space gap inside its cell, and every row holds one
    # token per label: the data were laid out
    # for a header of another width (escape codes or overstrikes in the
    # header: `CORE   UTIL      TEMP` over `cpu0   41%   58°C`), and the
    # values of the empty column sit inside their neighbour
    # (only when every row holds one token per label: the tokens fit the
    # header where the offsets do not)
    for (c = 1; c <= nc && cnteq; c++) {
        if (CN[c] !~ /[A-Za-z0-9]/) continue
        f = 0
        for (i = 1; i <= nrr; i++) if (CELL[i, c] != "") { f = 1; break }
        if (f) continue
        for (c2 = 1; c2 <= nc; c2++) {
            g2 = 0; f2 = 0
            for (i = 1; i <= nrr; i++) if (CELL[i, c2] != "") { f2++; if (CG2[i, c2]) g2++ }
            if (f2 && g2 * 2 >= f2) return 0
        }
    }
    # Emission order: row by row — unless the first row leaves a column
    # empty that a later row fills. The melt names columns in the order they
    # first appear, so then the cells go column by column, which keeps the
    # header order (`Name Used (GB) Free (GB) Provider`, not `Name Provider
    # Used (GB)`).
    cm = 0
    for (c = 1; c <= nc && !cm; c++) {
        if (DROP[c] || OUTC[1, c] != "") continue
        for (i = 2; i <= ne; i++) if (OUTC[i, c] != "") { cm = 1; break }
    }
    if (cm) {
        for (c = 1; c <= nc; c++)
            if (!DROP[c]) for (i = 1; i <= ne; i++)
                if (OUTC[i, c] != "") printf "%s%d.%s %s\n", pfx, i, NM[c], OUTC[i, c]
    } else {
        for (i = 1; i <= ne; i++)
            for (c = 1; c <= nc; c++)
                if (!DROP[c] && OUTC[i, c] != "") printf "%s%d.%s %s\n", pfx, i, NM[c], OUTC[i, c]
    }
    printf "total_entries %d\n", ne
    return 1
}
'
# _fr_gutter_grid NH RL [PREFIX] < table-lines — run the gutter grid (bytes:
# LC_ALL=C); records are PREFIX<N>.<name> (default `entry`).
_fr_gutter_grid () {
    LC_ALL=C awk -v nh="$1" -v rl="$2" -v pfx="${3:-entry}" "$_FR_AWK_GRID"
}
