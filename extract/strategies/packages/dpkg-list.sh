#!/bin/bash
## Name: dpkg-list
## Description: Extract installed packages from dpkg -l output
## Version: 1.0
## Priority: 20
## Sample: samples/dpkg-list/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    _is_json "$text" && return 1
    # Distinctive dpkg -l preamble: a "Desired=" legend line, a "||/ Name" column
    # header, and a "+++-" separator row.
    local has_desired=0 has_name_hdr=0 has_sep=0
    while IFS= read -r line; do
        [[ "$line" == "Desired="* ]] && has_desired=1
        [[ "$line" == "||/ Name"* ]] && has_name_hdr=1
        [[ "$line" == "+++-"* ]] && has_sep=1
    done <<< "$text"
    if [[ $has_desired -eq 1 && $has_name_hdr -eq 1 && $has_sep -eq 1 ]]; then
        _STRATEGY_CONFIDENCE=88
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local entry=0
    local past_sep=0
    while IFS= read -r line; do
        # The "+++-" separator marks the end of the header block.
        if [[ "$line" == "+++-"* ]]; then
            past_sep=1
            continue
        fi
        [[ $past_sep -eq 1 ]] || continue
        [[ -z "$line" ]] && continue

        read -ra f <<< "$line"
        [[ ${#f[@]} -ge 4 ]] || continue
        local status="${f[0]}"
        local name="${f[1]}"
        local version="${f[2]}"
        local arch="${f[3]}"
        local description=""
        local i
        for ((i = 4; i < ${#f[@]}; i++)); do
            description+="${f[$i]} "
        done
        description="${description%" "}"

        entry=$((entry + 1))
        result+="entry${entry}.status ${status}"$'\n'
        result+="entry${entry}.name ${name}"$'\n'
        result+="entry${entry}.version ${version}"$'\n'
        result+="entry${entry}.arch ${arch}"$'\n'
        result+="entry${entry}.description ${description}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
