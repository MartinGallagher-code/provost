#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: flatpak-remotes
## Description: Extract configured remotes from `flatpak remotes` output
## Version: 1.0
## Priority: 20
## Sample: samples/flatpak-remotes/basic.txt

# `flatpak remotes` prints a "Name  Options" header then one remote per line as
# "<name>  <options>" (columns separated by runs of spaces). Each data row is
# one record with name/options fields.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    local first="" line
    while IFS= read -r line; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        first="$line"; break
    done <<< "$text"
    if [[ "$first" == Name*Options* ]]; then
        _STRATEGY_CONFIDENCE=86
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line name opts nb=0
    while IFS= read -r line; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        nb=$((nb + 1))
        [[ $nb -eq 1 ]] && continue   # header row
        name="${line%%[[:space:]]*}"
        opts="${line#"$name"}"
        opts="${opts#"${opts%%[![:space:]]*}"}"
        opts="${opts%"${opts##*[![:space:]]}"}"
        [[ -z "$name" ]] && continue
        entry=$((entry + 1))
        result+="entry${entry}.name ${name}"$'\n'
        result+="entry${entry}.options ${opts}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
