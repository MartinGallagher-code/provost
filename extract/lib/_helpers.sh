#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Helper functions for envoy-extract
##
## Pure-bash utility functions used by strategies and the engine.
## Dependencies: none (standalone)
################################################################################

# ENV-115: initialise clean_text cache slots at source time so nounset in
# envoy-extract doesn't trip when a caller (e.g. stream mode) reaches
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
    # OSC form (ESC ] … BEL) and bare two-byte escapes.
    if _pp_in $'\033'; then
        _PP_OK=0
        text="$(printf '%s' "$text" | sed $'s/\033\\[[0-9;?]*[ -/]*[@-~]//g; s/\033\\][^\007]*\007//g; s/\033[@-Z\\\\-_]//g')"
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
        local _drop_warn=1
        while IFS= read -r _l; do
            _n=$((_n + 1))
            [[ $_n -le 1 ]] && continue
            [[ "$_l" =~ ^(WARNING|ERROR|NOTICE): ]] && _drop_warn=0
        done <<< "$_in"
        _n=0
        while IFS= read -r _l; do
            if [[ $_lead -eq 1 ]]; then
                if [[ -z "${_l//[[:space:]]/}" ]]; then :
                elif [[ "$_l" =~ ^\$\ [A-Za-z] ]]; then continue
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
        '$ '*|WARNING:*|ERROR:*|NOTICE:*|*'******'*|List\ *|Ran\ *)
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
    _FR_SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/envoy-extract.XXXXXX") || { umask "$_fs_um"; _FR_SCRATCH=""; return 1; }
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
