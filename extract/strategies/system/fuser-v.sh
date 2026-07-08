#!/bin/bash
## Name: fuser-v
## Description: Extract process rows from `fuser -v` (verbose file-user) output
## Version: 1.0
## Priority: 20
## Technique: yes
## Sample: samples/fuser-v/basic.txt

# `fuser -v` prints a header then one row per process holding a file:
#                       USER    PID ACCESS COMMAND
#   /var/lib/mysql:     mysql  1843 F.... mysqld
#                       mysql  1902 f.... mysqld
# The file path appears only on the first row of each group (trailing ':'); it is
# carried forward to the continuation rows. Signature: the "ACCESS" column (which
# distinguishes it from `ps`, whose header also has USER/PID/COMMAND). Emit ONE
# record per process row; skip the header.

_fuser_sanitize () {
    local v="$1"
    v="${v//$'\t'/_}"
    printf '%s' "$v"
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    [[ "$text" == *ACCESS* ]]  || return 1
    [[ "$text" == *USER* ]]    || return 1
    [[ "$text" == *PID* ]]     || return 1
    [[ "$text" == *COMMAND* ]] || return 1
    _STRATEGY_CONFIDENCE=86
    return 0
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line path="" user pid access command
    local -a t=()
    while IFS= read -r line; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        read -ra t <<< "$line"
        [[ "${t[0]}" == "USER" ]] && continue      # header
        if [[ "${t[0]}" == *: ]]; then             # leading path column
            path="${t[0]%:}"
            user="${t[1]}"; pid="${t[2]}"; access="${t[3]}"; command="${t[4]}"
        else
            user="${t[0]}"; pid="${t[1]}"; access="${t[2]}"; command="${t[3]}"
        fi
        [[ -n "$pid" ]] || continue
        entry=$((entry + 1))
        result+="entry${entry}.path $(_fuser_sanitize "$path")"$'\n'
        result+="entry${entry}.user $(_fuser_sanitize "$user")"$'\n'
        result+="entry${entry}.pid $(_fuser_sanitize "$pid")"$'\n'
        result+="entry${entry}.access $(_fuser_sanitize "$access")"$'\n'
        result+="entry${entry}.command $(_fuser_sanitize "$command")"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
