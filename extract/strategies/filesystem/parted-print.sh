#!/bin/bash
## Name: parted-print
## Description: Extract partition table (number/start/end/size/fs/name) from `parted print`
## Version: 1.0
## Priority: 26
## Technique: yes
## Sample: samples/parted-print/basic.txt

# `parted print` prints a Model:/Disk:/Partition Table: header block, then a
# "Number Start End Size File system Name Flags" table. One record per
# partition; the header block is skipped.

_parted_is_header_row () {
    [[ "$1" == "Number"* && "$1" == *Start* && "$1" == *End* \
       && "$1" == *Size* && "$1" == *"File system"* ]]
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    local line saw_disk=0 saw_hdr=0
    while IFS= read -r line; do
        [[ "$line" == "Disk /dev/"* ]] && saw_disk=1
        _parted_is_header_row "$line" && saw_hdr=1
    done <<< "$text"
    if [[ $saw_disk -eq 1 && $saw_hdr -eq 1 ]]; then
        _STRATEGY_CONFIDENCE=86
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line in_table=0 i
    while IFS= read -r line; do
        if _parted_is_header_row "$line"; then
            in_table=1
            continue
        fi
        [[ $in_table -eq 1 ]] || continue
        [[ -z "${line//[[:space:]]/}" ]] && continue
        read -ra _f <<< "$line"
        # _f[0]=Number _f[1]=Start _f[2]=End _f[3]=Size _f[4]=Filesystem,
        # remaining tokens = Name + Flags.
        [[ "${_f[0]:-}" =~ ^[0-9]+$ ]] || continue
        local number="${_f[0]}" start="${_f[1]:-}" end="${_f[2]:-}"
        local size="${_f[3]:-}" fs="${_f[4]:-}"
        local name=""
        for ((i = 5; i < ${#_f[@]}; i++)); do
            [[ -n "$name" ]] && name+="_"
            name+="${_f[$i]}"
        done
        entry=$((entry + 1))
        result+="entry${entry}.number ${number}"$'\n'
        result+="entry${entry}.start ${start}"$'\n'
        result+="entry${entry}.end ${end}"$'\n'
        result+="entry${entry}.size ${size}"$'\n'
        result+="entry${entry}.fs ${fs}"$'\n'
        result+="entry${entry}.name ${name}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
