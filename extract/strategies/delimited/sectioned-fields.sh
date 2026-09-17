#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: sectioned-fields
## Description: colon-terminated section headers over indented `NAME value [k: v, k: v]` rows (sdparm --all mode pages) -> group + name/value + decomposed bracket columns
## Version: 1.0
## Priority: 46
## Sample: samples/sectioned-fields/basic.txt

# `sdparm --all` prints a device line, then one `… mode page [PS=0]:` header per
# page, then that page's fields indented beneath:
#
#     /dev/sda: ATA       Samsung SSD 870   2B6Q
#   Read write error recovery [rw_er_rec] mode page [PS=0]:
#     AWRE          1  [cha: y, def:  1]
#     ARRE          0  [cha: y, def:  0]
#   Caching [ca] mode page [PS=0]:
#     WCE           1  [cha: y, def:  1]
#
# The reviewer's note: "first line is kind of like a comment; Read… and
# Caching… are repeated column values, with items below each in multiple
# columns." So the device line drops as a preamble comment, each section header
# is carried DOWN as a `group` column, and each field row splits into
# `name | value` plus the trailing `[cha: y, def: N]` bracket decomposed into
# one column per bracket key (`cha`, `def`):
#
#   group                                             name  value  cha  def
#   Read write error recovery [rw_er_rec] mode page…  AWRE  1      y    1
#
# Records are entry-prefixed; the group repeats.

# A section header: unindented, ends in a colon, holds no interior `key: value`
# pair (so real kv lines stay out), and carries at least one non-space token.
_sf_hdr_re='^[A-Za-z0-9][^:]*[^: ]:[[:space:]]*$'
# A field member: indented `NAME  value  [ … ]` — a trailing bracket of
# comma-separated `key: value` pairs is what makes this shape addressable.
_sf_mem_re='^[[:space:]]+[^[:space:]].*\[[A-Za-z][A-Za-z0-9_ ]*:[^]]*\][[:space:]]*$'

# Split a member body (indent stripped) -> _SF_NAME, _SF_VAL, and the bracket
# key/value pairs into parallel arrays _SF_BK / _SF_BV. Returns 1 if it doesn't
# fit the `NAME value [k: v, …]` shape.
_sf_parse_member () {
    local body="$1"
    _SF_NAME=""; _SF_VAL=""; _SF_BK=(); _SF_BV=()
    # Peel the trailing [ … ] bracket.
    [[ "$body" == *'['*']'* ]] || return 1
    local pre="${body%%\[*}" brk="${body#*\[}"
    brk="${brk%\]*}"
    # Collapse the pre-bracket run into whitespace-separated tokens.
    pre="${pre%"${pre##*[![:space:]]}"}"
    local -a tok=(); read -ra tok <<< "$pre"
    [[ ${#tok[@]} -ge 1 ]] || return 1
    _SF_NAME="${tok[0]}"
    if [[ ${#tok[@]} -ge 2 ]]; then
        # value = the remaining pre-bracket tokens (space-joined)
        _SF_VAL="${tok[*]:1}"
    fi
    # Split the bracket on `, ` into `key: value` pairs.
    local IFS_SAVE="$IFS" part
    local -a parts=()
    IFS=',' read -ra parts <<< "$brk"
    IFS="$IFS_SAVE"
    for part in "${parts[@]}"; do
        part="${part#"${part%%[![:space:]]*}"}"
        part="${part%"${part##*[![:space:]]}"}"
        [[ "$part" == *:* ]] || continue
        local k="${part%%:*}" v="${part#*:}"
        k="${k%"${k##*[![:space:]]}"}"
        v="${v#"${v%%[![:space:]]*}"}"
        v="${v%"${v##*[![:space:]]}"}"
        k="${k// /_}"
        _SF_BK+=("$k"); _SF_BV+=("$v")
    done
    [[ ${#_SF_BK[@]} -ge 1 ]] || return 1
    return 0
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    local line headers=0 members=0 active=0 pre_noise=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        if [[ "$line" =~ $_sf_hdr_re && "$line" != *": "* ]]; then
            headers=$((headers + 1)); active=1; continue
        fi
        if [[ "$line" =~ $_sf_mem_re ]]; then
            [[ $active -eq 1 ]] || return 1     # a field with no page above it
            members=$((members + 1)); continue
        fi
        # Anything else is tolerated only as a leading comment before the first
        # header (the device line); once a header is seen, an unclassified line
        # rejects — this shape is headers + bracketed fields only.
        [[ $active -eq 1 ]] && return 1
        pre_noise=$((pre_noise + 1))
    done <<< "$text"
    [[ $headers -ge 1 && $members -ge 2 ]] || return 1
    _STRATEGY_CONFIDENCE=80
    return 0
}

strategy_extract () {
    local text="$1"
    local line result="" entry=0 group=""
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        if [[ "$line" =~ $_sf_hdr_re && "$line" != *": "* ]]; then
            group="${line%:*}"
            group="${group%"${group##*[![:space:]]}"}"
            continue
        fi
        if [[ "$line" =~ $_sf_mem_re ]]; then
            [[ -n "$group" ]] || continue
            local body="${line#"${line%%[![:space:]]*}"}"
            _sf_parse_member "$body" || continue
            entry=$((entry + 1))
            result+="entry${entry}.group ${group}"$'\n'
            result+="entry${entry}.name ${_SF_NAME}"$'\n'
            [[ -n "$_SF_VAL" ]] && result+="entry${entry}.value ${_SF_VAL}"$'\n'
            local i
            for i in "${!_SF_BK[@]}"; do
                result+="entry${entry}.${_SF_BK[$i]} ${_SF_BV[$i]}"$'\n'
            done
        fi
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
