#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: systemd-analyze-critical-chain
## Description: Extract the boot critical chain from `systemd-analyze critical-chain`
## Version: 1.0
## Priority: 26
## Sample: samples/systemd-analyze-critical-chain/basic.txt

# `systemd-analyze critical-chain` prints a preamble, then the boot critical
# chain as a tree: one unit per line (└─unit @activation +duration), indented
# with box-drawing connectors. Each unit becomes a record: c1 = unit name,
# c2 = timing (the @activation and optional +duration, spaces -> _).

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    # Distinctive: units with an "@time" activation stamp (e.g. ".target @14s").
    [[ "$text" == *".target @"* || "$text" == *".service @"* || "$text" == *".socket @"* ]] || return 1
    _STRATEGY_CONFIDENCE=86
    return 0
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line s
    local re='^([^[:space:]]+)[[:space:]]+(@[0-9].*)$'
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        s="$line"
        # Strip box-drawing glyphs: │ ├ └ ─
        s="${s//$'\xe2\x94\x82'/}"
        s="${s//$'\xe2\x94\x9c'/}"
        s="${s//$'\xe2\x94\x94'/}"
        s="${s//$'\xe2\x94\x80'/}"
        # Trim leading whitespace.
        while [[ "$s" == " "* || "$s" == $'\t'* ]]; do s="${s#[$' \t']}"; done
        # Only unit lines match "<unit> @<time>..."; skips preamble prose.
        [[ "$s" =~ $re ]] || continue
        local unit="${BASH_REMATCH[1]}"
        local timing="${BASH_REMATCH[2]}"
        entry=$((entry + 1))
        result+="entry${entry}.A ${unit}"$'\n'
        result+="entry${entry}.B ${timing}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
