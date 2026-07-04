#!/bin/bash
## Name: ss
## Description: Extract socket connections from ss -tuln output
## Version: 1.0
## Priority: 40
## Sample: samples/ss/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90
    # Reject JSON
    _is_json "$1" && return 1
    # Look for header with "Netid" and "State" and "Local Address"
    while IFS= read -r line; do
        if [[ "$line" == *"Netid"* && "$line" == *"State"* && "$line" == *"Local Address"* ]]; then
            return 0
        fi
    done <<< "$text"
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""

    local past_header=0
    local socket_n=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Skip header line
        if [[ "$line" == *"Netid"* && "$line" == *"State"* && "$line" == *"Local Address"* ]]; then
            past_header=1
            continue
        fi
        [[ $past_header -eq 0 ]] && continue

        # Parse data line
        # Format: netid state recv-q send-q local_addr:port peer_addr:port [process]
        # Examples:
        #   tcp    LISTEN  0       128      0.0.0.0:22            0.0.0.0:*
        #   tcp    LISTEN  0       128      [::]:443              [::]:*
        #   udp    UNCONN  0       0        0.0.0.0:68            0.0.0.0:*

        read -ra _arr <<< "$line"
        [[ ${#_arr[@]} -lt 5 ]] && continue

        local netid="${_arr[0]}"
        local state="${_arr[1]}"

        # Validate netid looks reasonable
        case "$netid" in
            tcp|tcp6|udp|udp6|raw|raw6|u_str|u_seq|u_dgr|nl|p_raw|p_dgr) ;;
            *) continue ;;
        esac

        socket_n=$((socket_n + 1))

        # Find local and peer addresses
        # recv-q and send-q are at positions 2 and 3
        # local address is at position 4, peer at position 5
        local local_addr="${_arr[4]}"
        local peer_addr="${_arr[5]}"

        # Handle IPv6 addresses in brackets that may span array elements
        # e.g., [::]:443 is one token, but [::1]:443 could also be one token
        # If local_addr starts with [ but doesn't contain ]:, merge tokens
        if [[ "$local_addr" == "["* && "$local_addr" != *"]:"* && "$local_addr" != *"]:*"* ]]; then
            # Check if next token completes the bracket
            local j=5
            while [[ $j -lt ${#_arr[@]} ]]; do
                local_addr+=" ${_arr[$j]}"
                if [[ "${_arr[$j]}" == *"]:"* || "${_arr[$j]}" == *"]:*"* ]]; then
                    j=$((j + 1))
                    break
                fi
                j=$((j + 1))
            done
            peer_addr="${_arr[$j]}"
        fi

        result+="socket${socket_n}_netid ${netid}"$'\n'
        result+="socket${socket_n}_state ${state}"$'\n'
        [[ -n "$local_addr" ]] && result+="socket${socket_n}_local ${local_addr}"$'\n'
        [[ -n "$peer_addr" ]] && result+="socket${socket_n}_peer ${peer_addr}"$'\n'
    done <<< "$text"

    echo "$result"
}
