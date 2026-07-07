#!/bin/bash
## Name: proc-filesystems
## Description: Extract supported filesystem types from /proc/filesystems
## Version: 1.0
## Priority: 9
## Technique: yes
## Sample: samples/proc-filesystems/basic.txt

# /proc/filesystems lists one filesystem per line, tab-separated: an optional
# "nodev" marker then the filesystem name:
#   nodev<TAB>sysfs
#   <TAB>ext4
# We emit one record per line with a nodev flag and the fs name.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=86
    [[ "$text" == *"nodev"$'\t'* ]] || return 1
    return 0
}

strategy_extract () {
    local text="$1"
    local result="" line n=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local -a f=()
        read -ra f <<< "$line"
        [[ ${#f[@]} -lt 1 ]] && continue

        local nodev="" name
        if [[ "${f[0]}" == "nodev" && ${#f[@]} -ge 2 ]]; then
            nodev="nodev"
            name="${f[1]}"
        else
            name="${f[0]}"
        fi

        n=$((n + 1))
        result+="entry${n}.nodev ${nodev}"$'\n'
        result+="entry${n}.name ${name}"$'\n'
    done <<< "$text"

    [[ $n -gt 0 ]] && result+="total_entries ${n}"$'\n'
    echo "$result"
}
