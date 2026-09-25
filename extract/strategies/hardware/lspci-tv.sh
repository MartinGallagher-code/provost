#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: lspci-tv
## Description: Extract PCI device tree lines from lspci -tv output (one record per device)
## Version: 1.0
## Priority: 20
## Sample: samples/lspci-tv/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=92
    _is_json "$text" && return 1
    # lspci -tv tree: a root bus like "-[0000:00]-" (HEX bus address, no spaces)
    # plus branch glyphs (+- \-). The hex requirement rejects psql `\x` record
    # separators like "-[ RECORD 1 ]---+---".
    if [[ "$text" =~ \-\[[0-9a-fA-F]+(:[0-9a-fA-F]+)?\]- ]] \
       && { [[ "$text" == *"+-"* ]] || [[ "$text" == *"\\-"* ]]; }; then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local n=0

    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ -z "$line" ]] && continue
        n=$((n + 1))
        # Single-column: whole tree line is the value (internal spaces preserved).
        result+="entry${n}.A ${line}"$'\n'
    done

    result+="total_entries ${n}"$'\n'
    echo "$result"
}
