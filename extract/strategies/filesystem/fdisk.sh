#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: fdisk
## Description: Extract disk partition table from fdisk -l output
## Version: 1.0
## Priority: 20
## Sample: samples/fdisk/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    _is_json "$text" && return 1
    # Distinctive: a "Disk /dev/..." line AND a partition-table header containing
    # Device / Start / End / Sectors / Size / Type columns.
    local has_disk=0 has_header=0
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "$line" == "Disk /dev/"* ]] && has_disk=1
        if [[ "$line" == "Device"* && "$line" == *Start* && "$line" == *End* \
              && "$line" == *Sectors* && "$line" == *Size* && "$line" == *Type* ]]; then
            has_header=1
        fi
    done
    if [[ $has_disk -eq 1 && $has_header -eq 1 ]]; then
        _STRATEGY_CONFIDENCE=92
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local entry=0
    local in_table=0
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        # Partition-table header marks the start of the data rows.
        if [[ "$line" == "Device"* && "$line" == *Start* && "$line" == *Type* ]]; then
            in_table=1
            continue
        fi
        [[ $in_table -eq 1 ]] || continue
        [[ -z "$line" ]] && continue
        # Only partition rows (/dev/...) are data.
        [[ "$line" == /dev/* ]] || continue

        { _fr_tok "$line"; f=("${_FR_TOK[@]}"); }
        # f[0]=device; optional "*" boot flag; then start end sectors size id type...
        local device="${f[0]}"
        local idx=1
        local boot=""
        if [[ "${f[1]}" == "*" ]]; then
            boot="*"
            idx=2
        fi
        local start="${f[$idx]}"; idx=$((idx + 1))
        local end="${f[$idx]}";   idx=$((idx + 1))
        local sectors="${f[$idx]}"; idx=$((idx + 1))
        local size="${f[$idx]}";  idx=$((idx + 1))
        # skip Id column
        idx=$((idx + 1))
        # remaining tokens form the Type (may contain spaces)
        local type=""
        local i
        for ((i = idx; i < ${#f[@]}; i++)); do
            type+="${f[$i]} "
        done
        type="${type%" "}"

        entry=$((entry + 1))
        result+="entry${entry}.device ${device}"$'\n'
        result+="entry${entry}.boot ${boot}"$'\n'
        result+="entry${entry}.start ${start}"$'\n'
        result+="entry${entry}.end ${end}"$'\n'
        result+="entry${entry}.sectors ${sectors}"$'\n'
        result+="entry${entry}.size ${size}"$'\n'
        result+="entry${entry}.type ${type}"$'\n'
    done
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
