#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: gnu-version
## Description: Extract tool/version/copyright/license fields from a GNU-style `--version` banner
## Version: 1.1
## Priority: 22
## Sample: samples/gnu-version/basic.txt

# The GNU coreutils `--version` convention: a "<tool> <version>" line, a
# "Copyright (C) <year> <holder>" line, a "License ..." line, then boilerplate
# ("This is free software...", "There is NO WARRANTY...") and optional trailers
# ("Written by ...", "Packaged by ..."). Generic parsers see five unrelated
# prose lines and fall through to a weak catch-all parse, losing the schema
# the banner actually has.
#
# One wide key/value record (no entryN.*): tool, version, copyright, license,
# license_url, warranty, author — and EVERYTHING ELSE the banner carries, so
# the claim never drops part of the input (v1.1). A `--version` banner is often
# the head of a longer report: component versions (`libgcrypt 1.9.4`), a home
# directory, lists of supported algorithms or features wrapped over several
# lines, build notes, help addresses. Those used to be dropped silently while
# the strategy claimed the whole input at 92. Now:
#   - `Label: value` becomes a field named after the label (lower-cased,
#     non-alphanumerics folded to `_`; a clash gets `_2`, `_3` …); deeper
#     indented lines, and lines after a value ending in `,`, continue it; a bare
#     `Label:` over indented lines takes them as its value; a bare `Label:`
#     over more labels is only a heading and adds nothing;
#   - a `<name> <version>` line after the first is a component: field `name`;
#   - a value that is a single `<url>` (optionally followed by `.`) loses the
#     angle brackets;
#   - any other non-boilerplate line is kept, space-joined, in `notes`.
#
# Three first-line shapes are recognised, all of them in the wild:
#   provost 2.0.1                                  <- plain "<tool> <version>"
#   grep (GNU grep) 3.11                           <- coreutils "<tool> (<pkg>) <ver>"
#   GNU bash, version 5.2.21(1)-release (x86_64…)  <- bash's "<pkg>, version <ver>"
# and the license id is taken from either "License: GPL-3.0-only <url>" (SPDX
# style) or "License GPLv3+: GNU GPL version 3 or later <url>." (FSF style).
#
# Detect needs ALL THREE of first-line-parses + Copyright + License. A bare
# "name 1.2.3" line is far too common (banners, package listings, benchmark
# headers) to detect on by itself.

# Is $1 shaped like a version number? Digits with at least one dot, an optional
# `v` prefix, and any suffix GNU tools actually print (`-rc1`, `1.2.3a`,
# `5.2.21(1)-release`, `2.30~beta`).
_gnuver_is_version () {
    local re_ver='^[vV]?[0-9]+\.[0-9]+[0-9A-Za-z.+~:_()-]*$'
    [[ "$1" =~ $re_ver ]]
}

# Is $1 a plausible program-name word (no prose punctuation)?
_gnuver_is_word () {
    local re_word='^[A-Za-z0-9][A-Za-z0-9._+-]*$'
    [[ "$1" =~ $re_word ]]
}

# First non-blank line of $1, whitespace-trimmed. Echoes "" if none.
# _gnuver_first_line_v TEXT — `$(_gnuver_first_line TEXT)` in _GNUVER_FIRST,
# without the fork (the printed line is trimmed, so the capture strips nothing).
_gnuver_first_line_v () {
    local line
    _GNUVER_FIRST=""
    _fr_lines "$1"
    for line in "${_FR_LINES[@]}"; do
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -z "$line" ]] && continue
        _GNUVER_FIRST="$line"
        return 0
    done
    return 0
}

_gnuver_first_line () {
    local line
    _fr_lines "$1"
    for line in "${_FR_LINES[@]}"; do
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -z "$line" ]] && continue
        printf '%s' "$line"
        return 0
    done
    printf ''
}

# Parse a banner's first line into _GNUVER_TOOL / _GNUVER_VERSION.
# Returns 1 when the line is not a "<program> <version>" banner at all.
_gnuver_parse_head () {
    local head="$1"
    local re_comma='^(.+),[[:space:]]+version[[:space:]]+([^[:space:]]+)([[:space:]].*)?$'
    local re_paren='^([^[:space:]]+)[[:space:]]+\(([^)]*)\)[[:space:]]+([^[:space:]]+)([[:space:]].*)?$'
    _GNUVER_TOOL=""
    _GNUVER_VERSION=""

    # "GNU bash, version 5.2.21(1)-release (x86_64-pc-linux-gnu)"
    if [[ "$head" =~ $re_comma ]]; then
        local name="${BASH_REMATCH[1]}" ver="${BASH_REMATCH[2]}"
        if _gnuver_is_version "$ver"; then
            name="${name#GNU }"
            [[ -n "$name" ]] || return 1
            _GNUVER_TOOL="$name"
            _GNUVER_VERSION="$ver"
            return 0
        fi
        return 1
    fi

    # "grep (GNU grep) 3.11" / "ls (GNU coreutils) 9.4"
    if [[ "$head" =~ $re_paren ]]; then
        local name="${BASH_REMATCH[1]}" ver="${BASH_REMATCH[3]}"
        if _gnuver_is_word "$name" && _gnuver_is_version "$ver"; then
            _GNUVER_TOOL="$name"
            _GNUVER_VERSION="$ver"
            return 0
        fi
        return 1
    fi

    # "provost 2.0.1" / "GNU Make 4.3" — last token is the version, the words
    # before it are the name (with a leading "GNU" dropped).
    local toks=()
    { _fr_tok "$head"; toks=("${_FR_TOK[@]}"); }
    local n=${#toks[@]}
    [[ $n -ge 2 ]] || return 1
    _gnuver_is_version "${toks[$((n - 1))]}" || return 1
    local name="" i
    for ((i = 0; i < n - 1; i++)); do
        _gnuver_is_word "${toks[$i]}" || return 1
        name+="${name:+ }${toks[$i]}"
    done
    name="${name#GNU }"
    [[ -n "$name" ]] || return 1
    _GNUVER_TOOL="$name"
    _GNUVER_VERSION="${toks[$((n - 1))]}"
    return 0
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1

    local head
    _gnuver_first_line_v "$text"; head="$_GNUVER_FIRST"
    [[ -n "$head" ]] || return 1
    _gnuver_parse_head "$head" || return 1

    local re_copy='(^|'$'\n'')[[:space:]]*Copyright[[:space:]]+(\(C\)|\(c\)|©)[[:space:]]'
    local re_lic='(^|'$'\n'')[[:space:]]*License[[:space:] :]'
    [[ "$text" =~ $re_copy ]] || return 1
    [[ "$text" =~ $re_lic ]] || return 1

    _STRATEGY_CONFIDENCE=92
    return 0
}

strategy_extract () {
    local text="$1"
    local result="" line trimmed
    local copyright="" license="" license_url="" warranty=0 author="" in_author=0
    local notes="" first=1 ind lead cur_ind=-1 cur_key="" after_lic=0
    local -a xk=() xv=()
    local -A used=([tool]=1 [version]=1 [copyright]=1 [license]=1 [license_url]=1 [warranty]=1 [author]=1 [notes]=1)

    local re_copy_line='^Copyright[[:space:]]+(\(C\)|\(c\)|©)[[:space:]]+(.*)$'
    local re_lic_line='^License[[:space:] :]+(.*)$'
    local re_url='<([^>]*)>'
    local re_label='^([A-Za-z][A-Za-z0-9 ./()+_-]{0,47}):([[:space:]]+(.*))?$'
    local re_bare_url='^<([^>[:space:]]*)>\.?$'

    local head
    _gnuver_first_line_v "$text"; head="$_GNUVER_FIRST"
    _gnuver_parse_head "$head" || return 1
    local tool="$_GNUVER_TOOL" version="$_GNUVER_VERSION"

    # _gv_add KEY VALUE — a new extra field (label-derived name, deduplicated)
    _gv_add () {
        local k="${1,,}" n=2
        k="${k//[^a-z0-9]/_}"
        while [[ "$k" == *__* ]]; do k="${k//__/_}"; done
        k="${k#_}"; k="${k%_}"
        [[ -n "$k" ]] || k="field"
        if [[ -n "${used[$k]:-}" ]]; then
            while [[ -n "${used[${k}_$n]:-}" ]]; do n=$((n + 1)); done
            k="${k}_$n"
        fi
        used[$k]=1
        xk+=("$k"); xv+=("$2")
    }

    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        trimmed="${line#"${line%%[![:space:]]*}"}"
        trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
        lead="${line%%[![:space:]]*}"; ind=${#lead}

        # A "Written by ..." trailer can wrap over several lines and ends at the
        # sentence period or the next blank line.
        if [[ $in_author -eq 1 ]]; then
            if [[ -z "$trimmed" ]]; then
                in_author=0
            else
                author+=" $trimmed"
                [[ "$author" == *"." ]] && in_author=0
            fi
            continue
        fi

        if [[ -z "$trimmed" ]]; then
            cur_key=""; cur_ind=-1; after_lic=0
            continue
        fi
        if [[ $first -eq 1 ]]; then
            first=0          # the banner line itself (tool / version)
            continue
        fi
        # Continuation of the field in hand: deeper indented, or the value so
        # far ends in a comma (a wrapped list), or a bare label's body.
        if [[ -n "$cur_key" ]] && { [[ $ind -gt $cur_ind ]] || [[ "${xv[-1]}" == *, ]]; } \
           && ! { [[ $ind -le $cur_ind ]] && [[ "$trimmed" =~ $re_label ]]; }; then
            if [[ -n "${xv[-1]}" ]]; then xv[-1]+=" $trimmed"; else xv[-1]="$trimmed"; fi
            continue
        fi
        cur_key=""
        if [[ -z "$copyright" && "$trimmed" =~ $re_copy_line ]]; then
            copyright="${BASH_REMATCH[2]}"
        elif [[ -z "$license" && "$trimmed" =~ $re_lic_line ]]; then
            local rest="${BASH_REMATCH[1]}"
            # SPDX style ("License: GPL-3.0-only <url>") and FSF style
            # ("License GPLv3+: GNU GPL version 3 or later <url>.") both put the
            # id first; strip the punctuation that trails it either way.
            local id="${rest%%[[:space:]]*}"
            id="${id%"${id##*[!:,.;]}"}"
            [[ -n "$id" ]] && license="$id"
            [[ "$trimmed" =~ $re_url ]] && license_url="${BASH_REMATCH[1]}"
            after_lic=1
        elif [[ $after_lic -eq 1 && -z "$license_url" && "$trimmed" =~ $re_url && "$trimmed" == "<"* ]]; then
            # the license URL wrapped onto its own line
            license_url="${BASH_REMATCH[1]}"
        elif [[ "${trimmed,,}" == *"no warranty"* ]]; then
            warranty=1
        elif [[ "$trimmed" == "This is free software"* ]]; then
            :                # boilerplate, summarised by `license`
        elif [[ -z "$author" && "$trimmed" == "Written by "* ]]; then
            author="${trimmed#Written by }"
            [[ "$author" == *"." ]] || in_author=1
        elif [[ "$trimmed" =~ $re_label ]]; then
            local lab="${BASH_REMATCH[1]}" val="${BASH_REMATCH[3]}"
            [[ "$val" =~ $re_bare_url ]] && val="${BASH_REMATCH[1]}"
            _gv_add "$lab" "$val"
            cur_key="$lab"; cur_ind=$ind
        elif _gnuver_parse_head "$trimmed" && [[ "$_GNUVER_TOOL" != *" "* ]]; then
            _gv_add "$_GNUVER_TOOL" "$_GNUVER_VERSION"
        else
            notes+="${notes:+ }$trimmed"
        fi
    done

    author="${author%.}"

    result+="tool ${tool}"$'\n'
    result+="version ${version}"$'\n'
    [[ -n "$copyright" ]] && result+="copyright ${copyright}"$'\n'
    [[ -n "$license" ]] && result+="license ${license}"$'\n'
    [[ -n "$license_url" ]] && result+="license_url ${license_url}"$'\n'
    result+="warranty ${warranty}"$'\n'
    [[ -n "$author" ]] && result+="author ${author}"$'\n'
    # Extra fields; a bare heading that collected nothing adds nothing.
    local i
    for ((i = 0; i < ${#xk[@]}; i++)); do
        [[ -n "${xv[$i]}" ]] && result+="${xk[$i]} ${xv[$i]}"$'\n'
    done
    [[ -n "$notes" ]] && result+="notes ${notes}"$'\n'
    echo "$result"
}
