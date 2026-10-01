#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: inline-kv-groups
## Description: inline `k: v` header (btrfs fi show's Label/uuid) over indented prose-kv members -> header pairs carried onto per-member rows
## Version: 1.0
## Priority: 39
## Sample: samples/inline-kv-groups/basic.txt

# `btrfs filesystem show`:
#
#   Label: 'data'  uuid: 3f8a1c2d-4b5e-6f70-8a9b-0c1d2e3f4a5b
#   	Total devices 2 FS bytes used 412.83GiB
#   	devid    1 size 931.51GiB used 420.00GiB path /dev/sda1
#   	devid    2 size 931.51GiB used 420.00GiB path /dev/sdb1
#
# block-records kept only the Label line (uuid welded in) and DROPPED every
# devid row. Two structural facts make this addressable generically:
#   * the header is nothing but inline `key: value` pairs;
#   * each member line decomposes completely into word-run -> value pairs,
#     where a VALUE token is digit-led or path-led (`2`, `931.51GiB`,
#     `/dev/sda1`) and the words before it are its key (`Total devices`,
#     `FS bytes used`, `size`).
#
# One row per member, header pairs carried down:
#
#   Label   uuid      Total_devices  FS_bytes_used  devid  size       used       path
#   'data'  3f8a1c2d…  2             412.83GiB
#   'data'  3f8a1c2d…                               1      931.51GiB  420.00GiB  /dev/sda1
#
# Summary and device rows carry different columns; the melt unions them with
# empty cells, which is the honest shape — a summary row has no devid.

# Parse a header line -> _IKG_HK[] / _IKG_HV[]. A header is ONLY inline
# `key: value` pairs: `Key: value` runs separated by 2+ spaces (the value may
# hold single spaces). Returns 1 if the line doesn't fully decompose.
_ikg_parse_header () {
    local l="$1"
    _IKG_HK=(); _IKG_HV=()
    l="${l#"${l%%[![:space:]]*}"}"; l="${l%"${l##*[![:space:]]}"}"
    [[ "$l" == [A-Za-z]* ]] || return 1
    while [[ -n "$l" ]]; do
        [[ "$l" =~ ^([A-Za-z][A-Za-z0-9_-]*):[[:space:]]+ ]] || return 1
        local k="${BASH_REMATCH[1]}"
        l="${l#*"${BASH_REMATCH[0]}"}"
        # Value: up to the NEXT `  ` 2-space run, or end of line.
        local v
        if [[ "$l" == *"  "* ]]; then
            v="${l%%  *}"
            l="${l#*  }"
            l="${l#"${l%%[![:space:]]*}"}"
        else
            v="$l"; l=""
        fi
        v="${v%"${v##*[![:space:]]}"}"
        [[ -n "$v" ]] || return 1
        # The value itself must not smuggle an unsplit `k: v` (that would mean
        # the 2-space rule missed a pair boundary).
        _IKG_HK+=("$k"); _IKG_HV+=("$v")
    done
    [[ ${#_IKG_HK[@]} -ge 2 ]] || return 1
    return 0
}

# Parse a member body (indent stripped) -> _IKG_MK[] / _IKG_MV[]. Tokens are
# consumed as word-run KEY until a value-shaped token (digit-led or /-led)
# closes the pair. Every token must be consumed into a pair. Returns 1 else.
_ikg_parse_member () {
    local body="$1"
    _IKG_MK=(); _IKG_MV=()
    local -a tok=(); { _fr_tok "$body"; tok=("${_FR_TOK[@]}"); }
    [[ ${#tok[@]} -ge 2 ]] || return 1
    local key="" t
    for t in "${tok[@]}"; do
        if [[ "$t" =~ ^[0-9/] ]]; then
            [[ -n "$key" ]] || return 1     # a value with no key words before it
            _IKG_MK+=("${key// /_}"); _IKG_MV+=("$t")
            key=""
        else
            key+="${key:+ }$t"
        fi
    done
    [[ -z "$key" ]] || return 1             # trailing words with no value
    [[ ${#_IKG_MK[@]} -ge 1 ]] || return 1
    return 0
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    local line headers=0 members=0 active=0
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "${line}" != *[![:space:]]* ]] && continue
        if [[ "$line" != [' '$'\t']* ]]; then
            _ikg_parse_header "$line" || return 1
            headers=$((headers + 1)); active=1
            continue
        fi
        [[ $active -eq 1 ]] || return 1
        local body="${line#"${line%%[![:space:]]*}"}"
        body="${body%"${body##*[![:space:]]}"}"
        _ikg_parse_member "$body" || return 1
        members=$((members + 1))
    done
    # >=2 headers (a repeating record shape, not one report) each carrying
    # members, >=1 member per header on average.
    [[ $headers -ge 2 && $members -ge $headers ]] || return 1
    _STRATEGY_CONFIDENCE=80
    return 0
}

strategy_extract () {
    local text="$1"
    local line result="" entry=0
    local -a hk=() hv=()
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "${line}" != *[![:space:]]* ]] && continue
        if [[ "$line" != [' '$'\t']* ]]; then
            if _ikg_parse_header "$line"; then
                hk=("${_IKG_HK[@]}"); hv=("${_IKG_HV[@]}")
            fi
            continue
        fi
        local body="${line#"${line%%[![:space:]]*}"}"
        body="${body%"${body##*[![:space:]]}"}"
        _ikg_parse_member "$body" || continue
        [[ ${#hk[@]} -gt 0 ]] || continue
        entry=$((entry + 1))
        local i
        for i in "${!hk[@]}"; do
            result+="entry${entry}.${hk[$i]} ${hv[$i]}"$'\n'
        done
        for i in "${!_IKG_MK[@]}"; do
            result+="entry${entry}.${_IKG_MK[$i]} ${_IKG_MV[$i]}"$'\n'
        done
    done
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
