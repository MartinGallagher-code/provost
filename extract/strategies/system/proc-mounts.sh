#!/bin/bash
## Name: proc-mounts
## Description: Extract mounted filesystems from /proc/mounts
## Version: 1.0
## Priority: 9
## Technique: yes
## Sample: samples/proc-mounts/basic.txt

# /proc/mounts (fstab-style) has one record per mount, six space-separated
# fields ending in the two dump/pass zeros:
#   /dev/sda1 / ext4 rw,relatime 0 0
# We keep device, mountpoint, fstype and options (dropping the trailing 0 0).
# Distinct from /proc/self/mountinfo, which carries a " - " separator.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=86
    [[ "$text" == *" - "* ]] && return 1            # that is mountinfo
    local line
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local -a f=()
        read -ra f <<< "$line"
        [[ ${#f[@]} -eq 6 && "${f[4]}" == "0" && "${f[5]}" == "0" ]] && return 0
        return 1
    done <<< "$text"
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" line n=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local -a f=()
        read -ra f <<< "$line"
        [[ ${#f[@]} -eq 6 && "${f[4]}" == "0" && "${f[5]}" == "0" ]] || continue

        n=$((n + 1))
        result+="entry${n}.device ${f[0]}"$'\n'
        result+="entry${n}.mountpoint ${f[1]}"$'\n'
        result+="entry${n}.fstype ${f[2]}"$'\n'
        result+="entry${n}.options ${f[3]}"$'\n'
    done <<< "$text"

    [[ $n -gt 0 ]] && result+="total_entries ${n}"$'\n'
    echo "$result"
}
