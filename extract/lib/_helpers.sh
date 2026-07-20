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
