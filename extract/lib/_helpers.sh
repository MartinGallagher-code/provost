#!/bin/bash
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

# Strategy helper: extract a value from text by grep pattern.
# Usage: _extract_value "$text" "grep_pattern" "field_name"
# Appends "field_name value" to $result if found.
# NOTE: Spaces in extracted values are replaced with underscores to ensure
# single-token values in the "field_name value" output format. Strategy authors
# should be aware of this normalization when extracting multi-word values.
_extract_value () {
    local _ev_text="$1" _ev_pattern="$2" _ev_field="$3"
    local _ev_line _ev_value
    while IFS= read -r _ev_line; do
        if [[ "$_ev_line" == *"$_ev_pattern"* ]]; then
            # Extract value: everything after last colon or equals, trimmed
            _ev_value="${_ev_line##*: }"
            if [[ "$_ev_value" == "$_ev_line" ]]; then
                _ev_value="${_ev_line##*=}"
            fi
            # Trim whitespace
            while [[ "$_ev_value" == " "* ]]; do _ev_value="${_ev_value# }"; done
            while [[ "$_ev_value" == *" " ]]; do _ev_value="${_ev_value% }"; done
            # Replace spaces with underscores
            _ev_value="${_ev_value// /_}"
            if [[ -n "$_ev_value" ]]; then
                result+="${_ev_field} ${_ev_value}"$'\n'
            fi
            return 0
        fi
    done <<< "$_ev_text"
    return 1
}

# Trim leading and trailing whitespace (spaces and tabs) from $1. Result in _TRIMMED.
_trim () {
    _TRIMMED="$1"
    while [[ "$_TRIMMED" == [' '$'\t']* ]]; do _TRIMMED="${_TRIMMED#[' '$'\t']}"; done
    while [[ "$_TRIMMED" == *[' '$'\t'] ]]; do _TRIMMED="${_TRIMMED%[' '$'\t']}"; done
}

# Trim + replace spaces with underscores. Result in _CLEANED.
_clean_field () {
    _trim "$1"
    _CLEANED="${_TRIMMED// /_}"
}

# Count non-empty lines in $1. Result in _LINE_COUNT.
_count_lines () {
    _LINE_COUNT=0
    local _cl_line
    while IFS= read -r _cl_line; do
        [[ -n "$_cl_line" ]] && _LINE_COUNT=$((_LINE_COUNT + 1))
    done <<< "$1"
}

# Parse a "name value" line into _FIELD_NAME and _FIELD_VALUE globals.
_parse_field_line () {
    _FIELD_NAME="${1%% *}"
    _FIELD_VALUE="${1#* }"
}

# Clean and normalize text for extraction.
# Consolidates date-fix and parentheses-fix that were previously duplicated
# in every strategy. Result in _CLEAN_TEXT_RESULT (no subshell needed).
# Caching: after first call, returns cached result from _CLEAN_TEXT_CACHE.
clean_text () {
    local input="$1"

    # Return cached result if available
    if [[ $_CLEAN_TEXT_DONE -eq 1 ]]; then
        _CLEAN_TEXT_RESULT="$_CLEAN_TEXT_CACHE"
        return
    fi

    # Pure-bash replacements (no sed forks)
    # Date pattern: " Mon 01 12:30:45 2024" -> "Mon_01_12_30_45_2024"
    local _date_re=' ([A-Za-z]{3}) ([0-9]{2}) ([0-9]{2}):([0-9]{2}):([0-9]{2}) ([0-9]{4})'
    # Paren pattern: spaces inside () -> underscores
    local _paren_re
    _paren_re='[(][^) ]*[ ]'

    local result="" _line
    while IFS= read -r _line; do
        # Date normalization (only lines with colons)
        if [[ "$_line" == *":"* ]]; then
            while [[ "$_line" =~ $_date_re ]]; do
                local _dm="${BASH_REMATCH[0]}"
                local _dr="${BASH_REMATCH[1]}_${BASH_REMATCH[2]}_${BASH_REMATCH[3]}_${BASH_REMATCH[4]}_${BASH_REMATCH[5]}_${BASH_REMATCH[6]}"
                _line="${_line/$_dm/$_dr}"
            done
        fi
        # Parentheses space normalization (only lines with parens)
        if [[ "$_line" == *"("* ]]; then
            while [[ "$_line" =~ $_paren_re ]]; do
                local _pm="${BASH_REMATCH[0]}"
                local _pr="${_pm% }_"
                _line="${_line/$_pm/$_pr}"
            done
        fi
        result+="$_line"$'\n'
    done <<< "$input"
    result="${result%$'\n'}"

    _CLEAN_TEXT_CACHE="$result"
    _CLEAN_TEXT_DONE=1
    _CLEAN_TEXT_RESULT="$result"
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
preprocess_input_text () {
    local local_vt_to _banner_out _bl _lc_first
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
    if [[ "$text" == *$'\r'* || "$text" == *$'\013'* || "$text" == *$'\014'* \
          || "$text" == *$'\302\205'* || "$text" == *$'\342\200\250'* || "$text" == *$'\342\200\251'* ]]; then
        local_vt_to=$'\n'
        [[ "$text" == *$'\n'* ]] && local_vt_to=' '
        text="$(printf '%s' "$text" | sed 's/\r$//' | tr '\r\013\014' $'\n'"${local_vt_to}"$'\n' \
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
    if [[ "$text" == *$'\302\240'* || "$text" == *$'\342\200'* || "$text" == *$'\342\201\237'* \
          || "$text" == *$'\343\200\200'* ]]; then
        text="$(printf '%s' "$text" | LC_ALL=C sed $'s/\302\240/ /g; s/\342\200[\200-\212]/ /g; s/\342\200\257/ /g; s/\342\201\237/ /g; s/\343\200\200/ /g')"
    fi

    # Delete ZERO-WIDTH SPACE (U+200B) — invisible in the terminal, so it can only
    # corrupt: a header token carrying one (`user​name`) prints as one word but
    # compares unequal to its plain form and pollutes the melted field name. Only
    # ZWSP is dropped; ZWNJ/ZWJ (U+200C/D) are orthographically REAL (Farsi
    # half-space, emoji family joins) and stay. Gated on the byte pair.
    if [[ "$text" == *$'\342\200\213'* ]]; then
        text="$(printf '%s' "$text" | LC_ALL=C sed $'s/\342\200\213//g')"
    fi

    # Normalise FULLWIDTH digits (U+FF10–FF19, CJK tables: `８０`) and the fullwidth
    # colon (U+FF1A) to their ASCII forms so numeric-contrast header detection and
    # `key: value` splitting see them the way a reader does. Gated on the FF-block
    # lead bytes being present.
    if [[ "$text" == *$'\357\274'* ]]; then
        text="$(printf '%s' "$text" | LC_ALL=C sed $'s/\357\274\220/0/g; s/\357\274\221/1/g; s/\357\274\222/2/g; s/\357\274\223/3/g; s/\357\274\224/4/g; s/\357\274\225/5/g; s/\357\274\226/6/g; s/\357\274\227/7/g; s/\357\274\230/8/g; s/\357\274\231/9/g; s/\357\274\232/:/g')"
    fi

    # Strip ANSI/VT escape sequences (colored output: ls --color, gh, git, kubectl,
    # systemctl status dots, terraform plan, npm/cargo, …) so a color code can never
    # split or pollute a data cell. Gated on an ESC byte being present, so it is a
    # true no-op — no subprocess — for the overwhelming majority of inputs that carry
    # none. Matches the ECMA-48 CSI form (ESC [ params intermediates final) plus the
    # OSC form (ESC ] … BEL) and bare two-byte escapes.
    if [[ "$text" == *$'\033'* ]]; then
        text="$(printf '%s' "$text" | sed $'s/\033\\[[0-9;?]*[ -/]*[@-~]//g; s/\033\\][^\007]*\007//g; s/\033[@-Z\\\\-_]//g')"
    fi

    # Strip terminal-bell and backspace control bytes (BEL \a, BS \b) — decoration
    # or erase intent, never data; leaving them embeds invisible bytes in a cell.
    # Runs AFTER the ANSI strip: BEL terminates an OSC sequence, so deleting it
    # first would orphan `ESC]…BEL` sequences the OSC rule needs intact. Gated on
    # presence, a no-op otherwise.
    if [[ "$text" == *$'\007'* || "$text" == *$'\010'* ]]; then
        text="$(printf '%s' "$text" | tr -d '\007\010')"
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
    # Interspersed `== section ==` banner lines (apptainer inspect's
    # `== labels ==` / `== runscript ==`) are pure section decoration — drop a
    # line delimited by EXACTLY-two-equals runs (`== word ==`). Longer runs
    # (`=== SET ===`, `====== JOB MAP ======`) are GROUP-LABEL banners that the
    # embedded-table / kv-under-group parsers legitimately consume, so the
    # exact-`==` shape is the discriminator. Gated on the byte pair.
    if [[ "$text" == *'== '* ]]; then
        _banner_out=""
        while IFS= read -r _bl; do
            if [[ "$_bl" =~ ^[[:space:]]*==[[:space:]]+[A-Za-z0-9][^=]*[[:space:]]+==[[:space:]]*$ ]]; then
                continue
            fi
            _banner_out+="$_bl"$'\n'
        done <<< "$text"
        text="${_banner_out%$'\n'}"
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
