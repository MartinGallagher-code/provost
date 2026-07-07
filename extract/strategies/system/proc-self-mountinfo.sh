#!/bin/bash
## Name: proc-self-mountinfo
## Description: Extract mount records from /proc/self/mountinfo
## Version: 1.0
## Priority: 9
## Technique: yes
## Sample: samples/proc-self-mountinfo/basic.txt

# /proc/self/mountinfo has one record per mount, split by a " - " separator:
#   36 35 98:0 /mnt1 /mnt2 rw,noatime shared:14 - ext3 /dev/root rw,errors=continue
# Before "-": mount_id parent_id major:minor root mountpoint mount_opts and any
# optional tag fields. After "-": fstype source super_opts. Optional tags (which
# vary in number) are joined into one "optional" column so rows stay rectangular.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=86
    [[ "$text" == *" - "* ]] || return 1
    local re='^[0-9]+ [0-9]+ [0-9]+:[0-9]+ '
    [[ "$text" =~ $re ]] || return 1
    return 0
}

strategy_extract () {
    local text="$1"
    local result="" line n=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        [[ "$line" == *" - "* ]] || continue

        local pre="${line%% - *}" post="${line#* - }"
        local -a p=() q=()
        read -ra p <<< "$pre"
        read -ra q <<< "$post"
        [[ ${#p[@]} -lt 6 || ${#q[@]} -lt 3 ]] && continue

        # optional tag fields = pre tokens after the first six
        local optional=""
        local i
        for ((i = 6; i < ${#p[@]}; i++)); do
            optional+="${optional:+_}${p[$i]}"
        done

        n=$((n + 1))
        result+="entry${n}.mount_id ${p[0]}"$'\n'
        result+="entry${n}.parent_id ${p[1]}"$'\n'
        result+="entry${n}.major_minor ${p[2]}"$'\n'
        result+="entry${n}.root ${p[3]}"$'\n'
        result+="entry${n}.mountpoint ${p[4]}"$'\n'
        result+="entry${n}.mount_opts ${p[5]}"$'\n'
        result+="entry${n}.optional ${optional}"$'\n'
        result+="entry${n}.fstype ${q[0]}"$'\n'
        result+="entry${n}.source ${q[1]}"$'\n'
        result+="entry${n}.super_opts ${q[2]}"$'\n'
    done <<< "$text"

    [[ $n -gt 0 ]] && result+="total_entries ${n}"$'\n'
    echo "$result"
}
