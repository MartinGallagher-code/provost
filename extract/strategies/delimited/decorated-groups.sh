#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: decorated-groups
## Description: changesets-style identical emoji/decoration lead + `Header:` groups -> group + comma-joined members
## Version: 1.0
## Priority: 39
## Sample: samples/decorated-groups/basic.txt

# Some tools stamp every line with one identical decoration token (changesets'
# butterfly) and group members under trailing-colon headers:
#
#   🦋  Packages to be bumped at patch:
#   🦋  @example/api
#   🦋  @example/web
#   🦋  Packages to be bumped at minor:
#   🦋  @example/shared
#
# two-col-gap kept the emoji as a data column. The reviewer: "column A should
# be deleted; there are two rows — packages to be bumped at patch, and at
# minor — and the next field should be a comma separated listing of the
# sub-items":
#
#   group                          members
#   Packages to be bumped at patch  @example/api, @example/web
#   Packages to be bumped at minor  @example/shared
#
# Detection: EVERY non-blank line opens with the SAME token, that token
# contains NO ASCII alphanumerics (pure decoration — a word lead is
# repeated-lead-records' territory), the first stripped line ends in `:`,
# and >=1 member line follows a header.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    local line lead="" first=1 headers=0 members=0 seen_hdr=0
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "${line}" != *[![:space:]]* ]] && continue
        # The decoration must LEAD the line — an indented line has an empty
        # first token, which must never count as a shared decoration (that
        # ate every indented `header:` family: ceph status, clang targets).
        [[ "$line" == [!$' \t']* ]] || return 1
        local tok="${line%%[[:space:]]*}"
        [[ -n "$tok" ]] || return 1
        [[ "$tok" =~ [A-Za-z0-9] ]] && return 1
        if [[ -z "$lead" ]]; then lead="$tok"; else [[ "$tok" == "$lead" ]] || return 1; fi
        local body="${line#"$tok"}"
        body="${body#"${body%%[![:space:]]*}"}"
        body="${body%"${body##*[![:space:]]}"}"
        [[ -z "$body" ]] && continue
        if [[ "$body" == *: ]]; then
            headers=$((headers + 1)); seen_hdr=1
        else
            [[ $first -eq 1 && $seen_hdr -eq 0 ]] && return 1   # member before any header
            members=$((members + 1))
        fi
        first=0
    done
    [[ $headers -ge 1 && $members -ge 1 ]] || return 1
    _STRATEGY_CONFIDENCE=80
    return 0
}

strategy_extract () {
    local text="$1"
    local line result="" entry=0 group="" members=""
    _dg_flush () {
        [[ -n "$group" ]] || return 0
        entry=$((entry + 1))
        result+="entry${entry}.group ${group}"$'\n'
        result+="entry${entry}.members ${members}"$'\n'
        group=""; members=""
    }
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "${line}" != *[![:space:]]* ]] && continue
        local tok="${line%%[[:space:]]*}"
        local body="${line#"$tok"}"
        body="${body#"${body%%[![:space:]]*}"}"
        body="${body%"${body##*[![:space:]]}"}"
        [[ -z "$body" ]] && continue
        if [[ "$body" == *: ]]; then
            _dg_flush
            group="${body%:}"
        else
            [[ -n "$members" ]] && members+=", "
            members+="$body"
        fi
    done
    _dg_flush
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
