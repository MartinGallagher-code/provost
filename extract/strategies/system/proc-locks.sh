#!/bin/bash
## Name: proc-locks
## Description: Extract held file locks from /proc/locks
## Version: 1.0
## Priority: 20
## Technique: yes
## Sample: samples/proc-locks/basic.txt

# /proc/locks has one numbered record per held lock:
#   1: POSIX  ADVISORY  WRITE 1234 08:01:1835243 0 EOF
# fields: id, type(POSIX/FLOCK/OFDLCK), class(ADVISORY/MANDATORY),
# access(READ/WRITE), pid, major:minor:inode, start, end.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=86
    [[ "$text" == *"ADVISORY"* || "$text" == *"MANDATORY"* ]] || return 1
    [[ "$text" == *"POSIX"* || "$text" == *"FLOCK"* || "$text" == *"OFDLCK"* ]] || return 1
    return 0
}

strategy_extract () {
    local text="$1"
    local result="" line n=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        [[ "$line" == [0-9]*:\ * ]] || continue

        local -a f=()
        read -ra f <<< "$line"
        # f: N: type class access pid dev:inode start end
        [[ ${#f[@]} -lt 8 ]] && continue

        n=$((n + 1))
        result+="entry${n}.id ${f[0]%:}"$'\n'
        result+="entry${n}.type ${f[1]}"$'\n'
        result+="entry${n}.class ${f[2]}"$'\n'
        result+="entry${n}.access ${f[3]}"$'\n'
        result+="entry${n}.pid ${f[4]}"$'\n'
        result+="entry${n}.devinode ${f[5]}"$'\n'
        result+="entry${n}.start ${f[6]}"$'\n'
        result+="entry${n}.end ${f[7]}"$'\n'
    done <<< "$text"

    [[ $n -gt 0 ]] && result+="total_entries ${n}"$'\n'
    echo "$result"
}
