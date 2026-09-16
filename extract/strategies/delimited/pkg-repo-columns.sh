#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: pkg-repo-columns
## Description: `repo name version [status]` package rows with an optional bracketed status (pacman -Sl) -> repo/name/version/status rows — hint-routed
## Version: 1.0
## Priority: 20
## Sample: samples/pkg-repo-columns/basic.txt

# `pacman -Sl` lists available packages as `repo name version` with an optional
# trailing `[installed]` (or `[installed: OLDVER]`) marker:
#
#   core linux 6.6.10.arch1-1 [installed]
#   core glibc 2.38-7
#   extra vim 9.0.2189-1 [installed]
#
# The optional 4th field makes rows ragged, so it stayed one opaque cell. The
# split is positional — the first three whitespace tokens are repo, name,
# version; anything after (the `[...]` marker) is the status:
#
#   repo    name    version         status
#   core    linux   6.6.10.arch1-1  [installed]
#   core    glibc   2.38-7
#
# HINT-ONLY: routes on the `repo name version [installed]` shape via hints.tsv.

strategy_extract () {
    local text="$1"
    local line result="" entry=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        # Collapse leading space, then peel three tokens.
        local s="${line#"${line%%[![:space:]]*}"}"
        local repo="${s%%[[:space:]]*}"; local r1="${s#"$repo"}"
        r1="${r1#"${r1%%[![:space:]]*}"}"
        local name="${r1%%[[:space:]]*}"; local r2="${r1#"$name"}"
        r2="${r2#"${r2%%[![:space:]]*}"}"
        local ver="${r2%%[[:space:]]*}"; local rest="${r2#"$ver"}"
        rest="${rest#"${rest%%[![:space:]]*}"}"
        rest="${rest%"${rest##*[![:space:]]}"}"
        # Need at least repo, name, version.
        [[ -z "$repo" || -z "$name" || -z "$ver" ]] && return 0
        entry=$((entry + 1))
        result+="entry${entry}.repo ${repo}"$'\n'
        result+="entry${entry}.name ${name}"$'\n'
        result+="entry${entry}.version ${ver}"$'\n'
        [[ -n "$rest" ]] && result+="entry${entry}.status ${rest}"$'\n'
    done <<< "$text"
    [[ $entry -ge 2 ]] || return 0
    result+="total_entries ${entry}"$'\n'
    echo "$result"
}

# Auto-detect fires only when EVERY line is `repo name version[ [status]]`
# where the version ends in a `-<digit>` pkgrel (`6.6.10.arch1-1`, `2.38-7`)
# and any trailing field is a `[...]` marker. That pkgrel + bracket shape is
# specific to pacman -Sl; version banners (`ffmpeg version X Copyright …`),
# `ip route`, and `tc class` all fail it (extra trailing text, or no pkgrel).
_prc_line_re='^[a-z][A-Za-z0-9@._+-]* [A-Za-z0-9][A-Za-z0-9@._+-]* [0-9][A-Za-z0-9._:+-]*-[0-9][A-Za-z0-9._:+]*( \[[^]]*\])?$'

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    local line n=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        [[ "$line" =~ $_prc_line_re ]] || return 1
        n=$((n + 1))
    done <<< "$text"
    [[ $n -ge 2 ]] || return 1
    _STRATEGY_CONFIDENCE=80
    return 0
}
