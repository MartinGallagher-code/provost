#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: dbmate-status
## Description: Extract migrations from `dbmate status` output ([X]/[ ] lines; skips Applied/Pending footer)
## Version: 1.0
## Priority: 22
## Sample: samples/dbmate-status/basic.txt

# `dbmate status` prints one line per migration: "[X] <name>" (applied) or
# "[ ] <name>" (pending), followed by an "Applied: N / Pending: M" summary
# footer. Only the bracketed migration lines are data.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    # NB: no _is_json guard here — dbmate rows start with "[", which the naive
    # leading-bracket JSON check would misread as a JSON array.
    local line
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        if [[ "$line" =~ ^\[[X\ ]\][[:space:]] ]]; then
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
        [[ "$line" =~ ^\[[X\ ]\][[:space:]] ]] || continue
        local flag="${line:1:1}" name status
        name="${line:4}"
        while [[ "$name" == " "* ]]; do name="${name# }"; done
        if [[ "$flag" == "X" ]]; then status="applied"; else status="pending"; fi
        entry=$((entry + 1))
        result+="entry${entry}.status ${status}"$'\n'
        result+="entry${entry}.name ${name}"$'\n'
    done
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
