#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: gnu-version
## Description: Extract tool/version/copyright/license fields from a GNU-style `--version` banner
## Version: 1.0
## Priority: 22
## Sample: samples/gnu-version/basic.txt

# The GNU coreutils `--version` convention: a "<tool> <version>" line, a
# "Copyright (C) <year> <holder>" line, a "License ..." line, then boilerplate
# ("This is free software...", "There is NO WARRANTY...") and optional trailers
# ("Written by ...", "Packaged by ..."). Generic parsers see five unrelated
# prose lines and fall through to `unsorted` at confidence 35, losing the
# schema the banner actually has.
#
# One wide key/value record (no entryN.*): tool, version, copyright, license,
# license_url, warranty, author.
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
_gnuver_first_line () {
    local line
    while IFS= read -r line; do
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -z "$line" ]] && continue
        printf '%s' "$line"
        return 0
    done <<< "$1"
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
    read -ra toks <<< "$head"
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
    head="$(_gnuver_first_line "$text")"
    [[ -n "$head" ]] || return 1
    _gnuver_parse_head "$head" || return 1

    local re_copy='(^|'$'\n'')[[:space:]]*Copyright[[:space:]]+(\(C\)|\(c\)|©)[[:space:]]'
    local re_lic='(^|'$'\n'')[[:space:]]*License[[:space:] :]'
    [[ "$text" =~ $re_copy ]] || return 1
    [[ "$text" =~ $re_lic ]] || return 1

    _STRATEGY_CONFIDENCE=85
    return 0
}

strategy_extract () {
    local text="$1"
    local result="" line trimmed
    local copyright="" license="" license_url="" warranty=0 author="" in_author=0

    local re_copy_line='^Copyright[[:space:]]+(\(C\)|\(c\)|©)[[:space:]]+(.*)$'
    local re_lic_line='^License[[:space:] :]+(.*)$'
    local re_url='<([^>]*)>'

    local head
    head="$(_gnuver_first_line "$text")"
    _gnuver_parse_head "$head" || return 1

    while IFS= read -r line; do
        trimmed="${line#"${line%%[![:space:]]*}"}"
        trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"

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
            continue
        elif [[ -z "$copyright" && "$trimmed" =~ $re_copy_line ]]; then
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
        elif [[ "${trimmed,,}" == *"no warranty"* ]]; then
            warranty=1
        elif [[ -z "$author" && "$trimmed" == "Written by "* ]]; then
            author="${trimmed#Written by }"
            [[ "$author" == *"." ]] || in_author=1
        fi
    done <<< "$text"

    author="${author%.}"

    result+="tool ${_GNUVER_TOOL}"$'\n'
    result+="version ${_GNUVER_VERSION}"$'\n'
    [[ -n "$copyright" ]] && result+="copyright ${copyright}"$'\n'
    [[ -n "$license" ]] && result+="license ${license}"$'\n'
    [[ -n "$license_url" ]] && result+="license_url ${license_url}"$'\n'
    result+="warranty ${warranty}"$'\n'
    [[ -n "$author" ]] && result+="author ${author}"$'\n'
    echo "$result"
}
