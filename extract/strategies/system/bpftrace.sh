#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: bpftrace
## Description: bpftrace @map[key]: count output → one tidy row per key
## Version: 1.0
## Priority: 22
## Sample: samples/bpftrace/basic.txt

# bpftrace prints an "Attaching N probes..." line, a blank line, then one
# aggregated map entry per line: "@map[key]: count" (or "@[key]: count"). Each
# map line starts with '@' and contains "]:" — that distinguishes it from the
# attach banner and blanks, so we emit exactly one record per key.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    local line
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        if [[ "$line" == "@"* && "$line" == *"]:"* ]]; then
            _STRATEGY_CONFIDENCE=92
            return 0
        fi
    done
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "$line" == "@"* && "$line" == *"]:"* ]] || continue
        # key = text between the first '[' and its matching ']'
        local inside="${line#*[}"
        local key="${inside%%]*}"
        # count = text after "]:" with surrounding whitespace stripped
        local rest="${line#*]:}"
        local count="${rest// /}"
        entry=$((entry + 1))
        result+="entry${entry}.key ${key}"$'\n'
        result+="entry${entry}.count ${count}"$'\n'
    done
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
