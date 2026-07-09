#!/bin/bash
## Name: proc-devices
## Description: Extract registered character/block devices from /proc/devices
## Version: 1.0
## Priority: 20
## Sample: samples/proc-devices/basic.txt

# /proc/devices has two sections, each a "<major> <name>" list:
#   Character devices:
#     1 mem
#   Block devices:
#     8 sd
# We emit one record per device with its section type, major number and name,
# skipping the section headers and the blank line between them.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=86
    [[ "$text" == *"Character devices:"* ]] || return 1
    [[ "$text" == *"Block devices:"* ]] || return 1
    return 0
}

strategy_extract () {
    local text="$1"
    local result="" line n=0 section=""

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        case "$line" in
            "Character devices:") section="character"; continue ;;
            "Block devices:")     section="block";     continue ;;
        esac

        local -a f=()
        read -ra f <<< "$line"
        [[ ${#f[@]} -lt 2 ]] && continue
        [[ "${f[0]}" == *[!0-9]* ]] && continue      # major must be numeric

        n=$((n + 1))
        result+="entry${n}.type ${section}"$'\n'
        result+="entry${n}.major ${f[0]}"$'\n'
        result+="entry${n}.name ${f[1]}"$'\n'
    done <<< "$text"

    [[ $n -gt 0 ]] && result+="total_entries ${n}"$'\n'
    echo "$result"
}
