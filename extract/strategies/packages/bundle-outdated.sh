#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: bundle-outdated
## Description: Extract outdated gems from `bundle outdated` output (skips fetch preamble + header)
## Version: 1.1
## Priority: 12
## Sample: samples/bundle-outdated/basic.txt

# `bundle outdated` prints a "Fetching gem metadata..." / "Resolving
# dependencies..." preamble, then a column header
# ("Gem  Current  Latest  Requested  Groups"), then one row per outdated gem.
# The preamble and header are noise; only the gem rows are data.
#
# v1.1 keeps ALL five columns, not just name/current/latest. `Requested` and
# `Groups` were dropped because they cannot be read by splitting on whitespace:
# `Requested` holds `= 1.16.2` and `~> 6.4` (two tokens), is EMPTY for a gem
# with no constraint, and `Groups` holds `development, test`. The table is
# fixed-width, so the header's column start positions are what slices it.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    # Distinctive: bundler's fetch preamble plus the Current/Latest header.
    [[ "$text" == *"Fetching gem metadata"* ]] || return 1
    local line has_header=0 rows=0
    while IFS= read -r line; do
        if [[ "$line" == Gem*Current*Latest* ]]; then
            has_header=1
            continue
        fi
        # A gem row: name, then two version-looking tokens (start with a digit).
        if [[ "$line" =~ ^[A-Za-z0-9._-]+[[:space:]]+[0-9][^[:space:]]*[[:space:]]+[0-9][^[:space:]]* ]]; then
            rows=$((rows + 1))
        fi
    done <<< "$text"
    if [[ $has_header -eq 1 && $rows -ge 1 ]]; then
        _STRATEGY_CONFIDENCE=86
        return 0
    fi
    return 1
}

# Column start offsets of a fixed-width header, into _BO_POS / _BO_NAME.
_bo_header_cols () {
    # Split declarations: `local h="$1" n=${#h}` evaluates ${#h} BEFORE h is
    # assigned, so n comes out 0 and the loop never runs.
    local h="$1"
    local i=0 n=${#h} c prev=' '
    _BO_POS=(); _BO_NAME=()
    for ((i = 0; i < n; i++)); do
        c="${h:i:1}"
        if [[ "$c" != ' ' && "$prev" == ' ' ]]; then
            _BO_POS+=("$i")
            _BO_NAME+=("$(printf '%s' "${h:i}" | awk '{ print tolower($1) }')")
        fi
        prev="$c"
    done
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line
    local -a _BO_POS=() _BO_NAME=()
    while IFS= read -r line; do
        if [[ "$line" == Gem*Current*Latest* ]]; then
            _bo_header_cols "$line"
            continue
        fi
        [[ "$line" =~ ^[A-Za-z0-9._-]+[[:space:]]+[0-9][^[:space:]]*[[:space:]]+[0-9][^[:space:]]* ]] || continue
        [[ ${#_BO_POS[@]} -ge 3 ]] || continue
        entry=$((entry + 1))
        local ci start len cell
        for ((ci = 0; ci < ${#_BO_POS[@]}; ci++)); do
            start="${_BO_POS[$ci]}"
            if [[ $((ci + 1)) -lt ${#_BO_POS[@]} ]]; then
                len=$(( ${_BO_POS[$((ci + 1))]} - start ))
                cell="${line:start:len}"
            else
                # Last column runs to end of line: `development, test`.
                cell="${line:start}"
            fi
            cell="${cell#"${cell%%[![:space:]]*}"}"
            cell="${cell%"${cell##*[![:space:]]}"}"
            result+="entry${entry}.${_BO_NAME[$ci]} ${cell}"$'\n'
        done
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
