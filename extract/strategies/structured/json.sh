#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: json
## Description: Extract key/value pairs from JSON input, flattening nested objects with dot notation
## Version: 1.1
## Priority: 10
## Sample: samples/json/benchmark.json

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=85
    _STRATEGY_CONFIDENCE_REASON="input starts with { or ["
    # Apply if input looks like JSON (starts with { or [, possibly with leading whitespace)
    local trimmed="$text"
    # Strip a UTF-8 BOM (EF BB BF) if present — common in JSON exported from
    # Windows tools (PowerShell's Out-File, Notepad's "UTF-8" encoding). Left
    # in place it hides the leading '{'/'[' from the checks below and the
    # file falls through to 'unsorted' instead of being recognized as JSON.
    local bom; bom=$'\xef\xbb\xbf'
    # (prefix test first: a non-matching `#"$bom"` scans every prefix — quadratic)
    if [[ "$trimmed" == "$bom"* ]]; then trimmed="${trimmed#"$bom"}"; fi
    while [[ "$trimmed" == " "* || "$trimmed" == $'\t'* || "$trimmed" == $'\n'* ]]; do
        trimmed="${trimmed#?}"
    done
    # Trailing whitespace/newlines too, so we can check the closing bracket.
    while [[ "$trimmed" == *" " || "$trimmed" == *$'\t' || "$trimmed" == *$'\n' ]]; do
        trimmed="${trimmed%?}"
    done
    # Must open AND close like JSON. This rejects bracket-prefixed logs such as
    # dmesg ("[    0.000000] Linux version …") which open with '[' but do not
    # close with ']'/'}'.
    [[ "$trimmed" == "{"* || "$trimmed" == "["* ]] || return 1
    [[ "$trimmed" == *"}" || "$trimmed" == *"]" ]] || return 1
    return 0
}

strategy_extract () {
    local text="$1"
    if _strat_json_relax "$text"; then
        # A relaxed literal that is an ARRAY of records (`node -p
        # "os.cpus()"`) has no json-array to read it (that parser takes
        # strict JSON): number its elements the way json-array does —
        # `0.model` → `entry1.model`, one row per element.
        local _jr_t="${_JSON_RELAXED#"${_JSON_RELAXED%%[![:space:]]*}"}"
        if [[ "$_jr_t" == '['* ]]; then
            local _jr_out
            if command -v jq &>/dev/null; then
                _jr_out="$(_strat_json_extract_jq "$_JSON_RELAXED")"
            else
                _jr_out="$(_strat_json_extract_fallback "$_JSON_RELAXED")"
            fi
            printf '%s\n' "$_jr_out" | awk '
                $0 == "" { next }
                { L[++n] = $0; if ($1 !~ /^[0-9]+\./) flat = 1 }
                END {
                    if (flat || !n) { for (i = 1; i <= n; i++) print L[i]; exit }
                    for (i = 1; i <= n; i++) {
                        k = L[i]; d = index(k, "."); e = substr(k, 1, d - 1) + 1
                        if (e > m) m = e
                        print "entry" e "." substr(k, d + 1)
                    }
                    print "total_entries " m
                }'
            return 0
        fi
        text="$_JSON_RELAXED"
    fi

    # Try jq first (most reliable), fall back to awk-based parser. Pipe the flat
    # key/value pairs through _list_explode so a single indexed list-of-records
    # (avro `fields`, amtool `Peers`) becomes one tidy row per element instead of
    # a wide `fields.0.* fields.1.*` row whose duplicate leaf names collide.
    if command -v jq &>/dev/null; then
        _strat_json_extract_jq "$text" | _list_explode
    else
        _strat_json_extract_fallback "$text" | _list_explode
    fi
}

# A JavaScript / Python OBJECT LITERAL is not JSON, but it is the same data:
# `node -p` / console.log print `{ rss: 45678592, family: 'IPv4' }` (bare
# keys, single-quoted strings, trailing commas), Python prints `{'a': 1,
# 'ok': True, 'x': None}`. jq rejects it and the extract came out empty, so
# a key:value parser shredded the braces into debris instead. When the text
# is not valid JSON but looks like a literal (a bare `key:` after `{` / `,`,
# or a single quote), this awk pass rewrites it as JSON: bare keys quoted,
# '…' → "…", true/false/null kept, undefined/None → null, True/False →
# true/false, a comma before `}` / `]` dropped. Any other bare word (`NaN`,
# `[Function: f]`, `[Object]`, `<ref *1>`) means it is not plain data: the
# pass prints nothing and the extract stays as it was. (mawk-safe; inputs
# up to 256 KB — a character loop.)
_JSON_RELAX_AWK='
{ s = s $0 "\n" }
END {
    n = length(s); out = ""; i = 1; bad = 0
    while (i <= n) {
        c = substr(s, i, 1)
        if (c == "\"") {
            j = i + 1
            while (j <= n) {
                d = substr(s, j, 1)
                if (d == "\\") { j += 2; continue }
                if (d == "\"") break
                j++
            }
            out = out substr(s, i, j - i + 1); i = j + 1; continue
        }
        if (c == "\047") {
            j = i + 1; buf = ""
            while (j <= n) {
                d = substr(s, j, 1)
                if (d == "\\") {
                    e = substr(s, j + 1, 1)
                    if (e == "\047") buf = buf e; else buf = buf d e
                    j += 2; continue
                }
                if (d == "\047") break
                if (d == "\"") buf = buf "\\\""; else buf = buf d
                j++
            }
            if (j > n) { bad = 1; break }
            out = out "\"" buf "\""; i = j + 1; continue
        }
        if (c ~ /[A-Za-z_$]/) {
            j = i
            while (j <= n && substr(s, j, 1) ~ /[A-Za-z0-9_$]/) j++
            w = substr(s, i, j - i)
            k = j
            while (k <= n && substr(s, k, 1) ~ /[ \t\r\n]/) k++
            if (substr(s, k, 1) == ":") out = out "\"" w "\""
            else if (w == "true" || w == "false" || w == "null") out = out w
            else if (w == "undefined" || w == "None") out = out "null"
            else if (w == "True") out = out "true"
            else if (w == "False") out = out "false"
            else { bad = 1; break }
            i = j; continue
        }
        if (c == ",") {
            k = i + 1
            while (k <= n && substr(s, k, 1) ~ /[ \t\r\n]/) k++
            d = substr(s, k, 1)
            if (d == "}" || d == "]") { i++; continue }
        }
        out = out c; i++
    }
    if (!bad) printf "%s", out
}'

# _strat_json_relax TEXT — sets _JSON_RELAXED and returns 0 when TEXT is an
# object literal that is not already valid JSON (see _JSON_RELAX_AWK).
_strat_json_relax () {
    _JSON_RELAXED=""
    (( ${#1} <= 262144 )) || return 1
    local _jr_key='[{,][[:space:]]*[A-Za-z_$][A-Za-z0-9_$]*[[:space:]]*:'
    [[ "$1" =~ $_jr_key || "$1" == *"'"* ]] || return 1
    if command -v jq &>/dev/null; then
        printf '%s\n' "$1" | jq -e . >/dev/null 2>&1 && return 1
    fi
    _JSON_RELAXED="$(printf '%s\n' "$1" | awk "$_JSON_RELAX_AWK")"
    [[ -n "$_JSON_RELAXED" ]] || return 1
    if command -v jq &>/dev/null; then
        printf '%s\n' "$_JSON_RELAXED" | jq -e . >/dev/null 2>&1 || { _JSON_RELAXED=""; return 1; }
    fi
    return 0
}

_strat_json_extract_jq () {
    local text="$1"

    # Use jq to flatten and extract all leaf key/value pairs
    # Outputs "path value" for each leaf node
    # Uses path(.. | select()) for jq 1.8+ compatibility
    echo "$text" | jq -r '
        path(.. | select(type == "number" or type == "string" or type == "boolean" or type == "null")) as $p |
        ($p | map(if type == "number" then tostring else . end) | join(".")) + " " +
        (getpath($p) | tostring)
    ' 2>/dev/null || true
}

_strat_json_extract_fallback () {
    # No jq: the same leaves, under the same paths, from an awk reader
    # (_json_walk in _helpers.sh). Until v1.1 this read "key": value pairs
    # line by line and stopped at the first nested object or array, so
    # `{"host": …, "cpu": {"count": 64}}` filed `host` alone.
    _json_walk leaves "$1"
}
