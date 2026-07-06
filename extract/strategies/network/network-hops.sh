#!/bin/bash
## Name: network-hops
## Description: Extract hop statistics from traceroute or mtr --report output
## Version: 1.0
## Priority: 35
## Sample: samples/traceroute/basic.txt

# Merges traceroute and mtr strategies.
# traceroute output: first line "traceroute to ..."  -> destination + hopN_host/hopN_ip/hopN_rtt
# mtr --report output: HOST:/Loss% header + N.|-- hop lines -> source + hopN_host/hopN_loss/hopN_avg/etc.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90

    # Reject JSON
    _is_json "$1" && return 1

    local found_mtr_header=0 found_mtr_hop=0

    while IFS= read -r _line; do
        # traceroute: first non-empty line starts with "traceroute to"
        if [[ -n "$_line" ]]; then
            if [[ "$_line" == "traceroute to "* ]]; then
                _STRATEGY_CONFIDENCE=95
                return 0
            fi
            # If first non-empty line is not traceroute, stop checking for it
        fi

        # mtr: HOST:/Loss% header
        if [[ "$_line" == *"HOST:"* && "$_line" == *"Loss%"* ]]; then
            found_mtr_header=1
        fi
        # mtr: hop lines with .|-- marker
        case "$_line" in
            *'.|--'*) found_mtr_hop=1 ;;
        esac

        if [[ $found_mtr_header -eq 1 || $found_mtr_hop -eq 1 ]]; then
            return 0
        fi
    done <<< "$text"

    return 1
}

strategy_extract () {
    local text="$1"
    local result=""

    # Determine which format by checking for traceroute first line
    local _is_traceroute=0
    while IFS= read -r _line; do
        [[ -z "$_line" ]] && continue
        [[ "$_line" == "traceroute to "* ]] && _is_traceroute=1
        break
    done <<< "$text"

    if [[ $_is_traceroute -eq 1 ]]; then
        # --- traceroute format ---
        local first_line=1
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue

            # Parse first line: "traceroute to example.com (93.184.216.34), 30 hops max, 60 byte packets"
            if [[ $first_line -eq 1 ]]; then
                first_line=0
                if [[ "$line" == "traceroute to "* ]]; then
                    local after="${line#traceroute to }"
                    local dest="${after%% (*}"
                    while [[ "$dest" == *" " ]]; do dest="${dest% }"; done
                    [[ -n "$dest" ]] && result+="destination ${dest}"$'\n'
                    if [[ "$after" == *"("*")"* ]]; then
                        local ip_part="${after#*(}"
                        ip_part="${ip_part%%)*}"
                        [[ -n "$ip_part" ]] && result+="destination_ip ${ip_part}"$'\n'
                    fi
                fi
                continue
            fi

            # Parse hop lines: " N  hostname (IP)  RTT ms ..."  or " N  * * *"
            local trimmed="$line"
            while [[ "$trimmed" == " "* ]]; do trimmed="${trimmed# }"; done
            while [[ "$trimmed" == $'\t'* ]]; do trimmed="${trimmed#$'\t'}"; done
            [[ -z "$trimmed" ]] && continue

            read -ra _arr <<< "$trimmed"
            [[ ${#_arr[@]} -lt 1 ]] && continue
            local hop_num="${_arr[0]}"
            case "$hop_num" in *[!0-9]*) continue ;; esac
            [[ -z "$hop_num" ]] && continue

            # Timeout line: "N  * * *"
            if [[ "${_arr[1]:-}" == "*" ]]; then
                result+="hop${hop_num}_host *"$'\n'
                continue
            fi

            local hop_host="${_arr[1]:-}"
            local hop_ip=""
            local hop_rtt=""

            # IP in parentheses
            if [[ ${#_arr[@]} -ge 3 ]]; then
                case "${_arr[2]}" in
                    "("*")"*)
                        hop_ip="${_arr[2]#(}"
                        hop_ip="${hop_ip%)}"
                        ;;
                    "("*)
                        hop_ip="${_arr[2]#(}"
                        hop_ip="${hop_ip%)}"
                        ;;
                esac
            fi

            # First RTT value (number before "ms")
            local k
            for ((k=1; k<${#_arr[@]}; k++)); do
                if [[ "${_arr[$k]}" == "ms" && $k -ge 2 ]]; then
                    local rtt_candidate="${_arr[$((k-1))]}"
                    case "$rtt_candidate" in
                        *[!0-9.]*) ;;
                        *)
                            [[ -n "$rtt_candidate" ]] && hop_rtt="$rtt_candidate" && break
                            ;;
                    esac
                fi
            done

            [[ -n "$hop_host" ]] && result+="hop${hop_num}_host ${hop_host}"$'\n'
            [[ -n "$hop_ip" ]]   && result+="hop${hop_num}_ip ${hop_ip}"$'\n'
            [[ -n "$hop_rtt" ]]  && result+="hop${hop_num}_rtt ${hop_rtt}"$'\n'
        done <<< "$text"

    else
        # --- mtr format ---
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue

            # Start time: "Start: 2024-01-15T10:30:00+0000"
            if [[ "$line" == "Start:"* ]]; then
                local val="${line#Start:}"
                while [[ "$val" == " "* ]]; do val="${val# }"; done
                [[ -n "$val" ]] && result+="start_time ${val}"$'\n'
                continue
            fi

            # Source host from HOST: header line
            if [[ "$line" == *"HOST:"* && "$line" == *"Loss%"* ]]; then
                local val="${line#*HOST:}"
                while [[ "$val" == " "* ]]; do val="${val# }"; done
                read -ra _arr <<< "$val"
                local src="${_arr[0]:-}"
                [[ -n "$src" ]] && result+="source_host ${src}"$'\n'
                continue
            fi

            # Hop lines: "  N.|-- hostname  loss%  snt  last  avg  best  worst"
            case "$line" in
                *'.|--'*)
                    local before="${line%%.|--*}"
                    while [[ "$before" == " "* ]]; do before="${before# }"; done
                    local hop_num="$before"

                    local after="${line#*.|-- }"
                    while [[ "$after" == " "* ]]; do after="${after# }"; done

                    read -ra _arr <<< "$after"
                    [[ ${#_arr[@]} -lt 7 ]] && continue

                    result+="hop${hop_num}_host ${_arr[0]}"$'\n'
                    result+="hop${hop_num}_loss ${_arr[1]}"$'\n'
                    result+="hop${hop_num}_sent ${_arr[2]}"$'\n'
                    result+="hop${hop_num}_last ${_arr[3]}"$'\n'
                    result+="hop${hop_num}_avg ${_arr[4]}"$'\n'
                    result+="hop${hop_num}_best ${_arr[5]}"$'\n'
                    result+="hop${hop_num}_worst ${_arr[6]}"$'\n'
                    ;;
            esac
        done <<< "$text"
    fi

    echo "$result"
}
