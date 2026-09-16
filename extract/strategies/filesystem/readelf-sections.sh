#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: readelf-sections
## Description: Extract section headers from `readelf -S` output
## Version: 1.0
## Priority: 22
## Sample: samples/readelf-sections/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    # Distinctive: the readelf -S column header with the "[Nr]" index cell.
    local line
    while IFS= read -r line; do
        if [[ "$line" == *"[Nr]"* && "$line" == *"Name"* \
              && "$line" == *"Type"* && "$line" == *"Address"* \
              && "$line" == *"Offset"* ]]; then
            _STRATEGY_CONFIDENCE=88
            return 0
        fi
    done <<< "$text"
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0
    local line
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local trimmed="${line#"${line%%[![:space:]]*}"}"
        # Section rows start with a "[ N]" index cell.
        [[ "$trimmed" =~ ^\[[[:space:]]*[0-9]+\] ]] || continue
        # Pull the numeric index out of the brackets, keep the remainder.
        local nr="${trimmed#\[}"; nr="${nr%%\]*}"; nr="${nr//[[:space:]]/}"
        local rest="${trimmed#*\]}"
        read -ra f <<< "$rest"
        [[ ${#f[@]} -ge 4 ]] || continue
        entry=$((entry + 1))
        result+="entry${entry}.nr ${nr}"$'\n'
        # The NULL section (index 0) has an empty Name, so the remainder has one
        # fewer token; shift the field mapping accordingly.
        if [[ ${#f[@]} -ge 5 ]]; then
            result+="entry${entry}.name ${f[0]}"$'\n'
            result+="entry${entry}.type ${f[1]}"$'\n'
            result+="entry${entry}.address ${f[2]}"$'\n'
            result+="entry${entry}.offset ${f[3]}"$'\n'
            result+="entry${entry}.size ${f[4]}"$'\n'
        else
            result+="entry${entry}.type ${f[0]}"$'\n'
            result+="entry${entry}.address ${f[1]}"$'\n'
            result+="entry${entry}.offset ${f[2]}"$'\n'
            result+="entry${entry}.size ${f[3]}"$'\n'
        fi
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
