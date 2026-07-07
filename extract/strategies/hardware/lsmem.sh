#!/bin/bash
## Name: lsmem
## Description: Extract memory range table from lsmem output (skips summary block)
## Version: 1.0
## Priority: 20
## Technique: yes
## Sample: samples/lsmem/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=86
    _is_json "$text" && return 1
    local first=""
    while IFS= read -r _line; do
        [[ -z "$_line" ]] && continue
        first="$_line"; break
    done <<< "$text"
    # lsmem header: RANGE  SIZE  STATE  REMOVABLE  BLOCK
    if [[ "$first" == RANGE* && "$first" == *SIZE* && "$first" == *STATE* && "$first" == *BLOCK* ]]; then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local n=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        # Data rows are memory ranges (start at a hex address). Everything else
        # (header, "Memory block size:", totals) is skipped.
        case "$line" in
            0x*) : ;;
            *) continue ;;
        esac

        read -ra _arr <<< "$line"
        [[ ${#_arr[@]} -lt 5 ]] && continue

        n=$((n + 1))
        local p="entry${n}."
        result+="${p}range ${_arr[0]}"$'\n'
        result+="${p}size ${_arr[1]}"$'\n'
        result+="${p}state ${_arr[2]}"$'\n'
        result+="${p}removable ${_arr[3]}"$'\n'
        result+="${p}block ${_arr[4]}"$'\n'
    done <<< "$text"

    result+="total_entries ${n}"$'\n'
    echo "$result"
}
