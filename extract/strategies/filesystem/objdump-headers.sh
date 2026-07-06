#!/bin/bash
## Name: objdump-headers
## Description: Extract section headers from `objdump -h` output
## Version: 1.0
## Priority: 22
## Sample: samples/objdump-headers/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    # Distinctive: the objdump -h column header line.
    local line
    while IFS= read -r line; do
        if [[ "$line" == *"Idx"* && "$line" == *"Name"* && "$line" == *"Size"* \
              && "$line" == *"VMA"* && "$line" == *"LMA"* \
              && "$line" == *"File off"* && "$line" == *"Algn"* ]]; then
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
        # Trim leading whitespace.
        local trimmed="${line#"${line%%[![:space:]]*}"}"
        # Section rows begin with the numeric index; this skips the "Sections:"
        # banner, the "a.out: file format ..." line, the column header, and the
        # flag continuation lines (CONTENTS, ALLOC, ...).
        [[ "$trimmed" =~ ^[0-9]+[[:space:]] ]] || continue
        read -ra f <<< "$trimmed"
        [[ ${#f[@]} -ge 7 ]] || continue
        entry=$((entry + 1))
        result+="entry${entry}.idx ${f[0]}"$'\n'
        result+="entry${entry}.name ${f[1]}"$'\n'
        result+="entry${entry}.size ${f[2]}"$'\n'
        result+="entry${entry}.vma ${f[3]}"$'\n'
        result+="entry${entry}.lma ${f[4]}"$'\n'
        result+="entry${entry}.file_off ${f[5]}"$'\n'
        result+="entry${entry}.algn ${f[6]}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
