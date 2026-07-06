#!/bin/bash
## Name: ss-tulnp
## Description: Extract socket info from ss -tulnp output with process information
## Version: 1.0
## Priority: 42
## Technique: table
## Sample: samples/ss-tulnp/sample1.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=92
    _is_json "$text" && return 1
    # ss -tulnp has State, Recv-Q, Send-Q, Local Address:Port, Peer Address:Port, Process
    local first_line=""
    while IFS= read -r _line; do
        [[ -z "$_line" ]] && continue
        first_line="$_line"
        break
    done <<< "$text"
    if [[ "$first_line" == *"State"* && "$first_line" == *"Local"* && "$first_line" == *"Process"* ]]; then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local socket_n=0
    local past_header=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        if [[ "$line" == *"State"* && "$line" == *"Local"* && "$line" == *"Process"* ]]; then
            past_header=1
            continue
        fi
        [[ $past_header -eq 0 ]] && continue

        read -ra _arr <<< "$line"
        [[ ${#_arr[@]} -lt 5 ]] && continue

        socket_n=$((socket_n + 1))
        local prefix="socket${socket_n}"

        local state="${_arr[0]}"
        local recv_q="${_arr[1]}"
        local send_q="${_arr[2]}"
        local local_addr="${_arr[3]}"
        local peer_addr="${_arr[4]}"

        # Process info may be in remaining tokens
        local process=""
        local i
        for ((i=5; i<${#_arr[@]}; i++)); do
            if [[ -z "$process" ]]; then
                process="${_arr[$i]}"
            else
                process="${process}_${_arr[$i]}"
            fi
        done
        # Extract program name from users:(("name",pid=N,fd=N)) format
        local prog_name=""
        if [[ "$process" == *"users:"* ]]; then
            local tmp="${process#*users:((\"}"
            prog_name="${tmp%%\"*}"
        fi

        result+="${prefix}.state ${state}"$'\n'
        result+="${prefix}.recv_q ${recv_q}"$'\n'
        result+="${prefix}.send_q ${send_q}"$'\n'
        result+="${prefix}.local ${local_addr}"$'\n'
        result+="${prefix}.peer ${peer_addr}"$'\n'
        [[ -n "$prog_name" ]] && result+="${prefix}.process ${prog_name}"$'\n'
    done <<< "$text"

    echo "$result"
}
