#!/bin/bash
## Name: iperf3
## Description: Extract network throughput, retransmits, and jitter from iperf3 output
## Version: 1.0
## Priority: 12
## Sample: samples/iperf3/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90
    # Reject JSON output
    _is_json "$1" && return 1
    if [[ "$text" == *[Ii][Pp][Ee][Rr][Ff]* ]]; then
        if [[ "$text" == *"Connecting to host"* ]] || \
           [[ "$text" == *"sender"* ]]; then
            return 0
        fi
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""

    # Extract connection info: "Connecting to host 10.0.0.1, port 5201"
    local connect_line=""
    while IFS= read -r _line; do
        if [[ "$_line" == *"Connecting to host"* ]]; then
            connect_line="$_line"
            break
        fi
    done <<< "$text"
    if [[ -n "$connect_line" ]]; then
        local host port
        local after="${connect_line#*Connecting to host }"
        host="${after%%,*}"
        local port_part="${after#*port }"
        read -ra _arr <<< "$port_part"
        port="${_arr[0]}"
        [[ -n "$host" ]] && result+="host ${host}"$'\n'
        [[ -n "$port" ]] && result+="port ${port}"$'\n'
    fi

    # Extract protocol: "[  5] local ... port ... connected to ..."
    if [[ "$text" == *"TCP"* ]]; then
        result+="protocol TCP"$'\n'
    elif [[ "$text" == *"UDP"* ]]; then
        result+="protocol UDP"$'\n'
    fi

    # Extract sender/receiver summary lines
    # "[  5]   0.00-10.00  sec  1.10 GBytes   941 Mbits/sec    0   sender"
    # "[  5]   0.00-10.04  sec  1.09 GBytes   935 Mbits/sec                  receiver"
    local sender_line="" receiver_line=""
    while IFS= read -r _line; do
        if [[ "$_line" == *"sender"* ]]; then
            if [[ "$_line" != *"[SUM]"* ]]; then
                sender_line="$_line"
            elif [[ -z "$sender_line" ]]; then
                sender_line="$_line"
            fi
        fi
        if [[ "$_line" == *"receiver"* ]]; then
            if [[ "$_line" != *"[SUM]"* ]]; then
                receiver_line="$_line"
            elif [[ -z "$receiver_line" ]]; then
                receiver_line="$_line"
            fi
        fi
    done <<< "$text"
    # If we didn't find non-SUM lines, look for SUM lines
    if [[ -z "$sender_line" ]]; then
        while IFS= read -r _line; do
            if [[ "$_line" == *"[SUM]"* && "$_line" == *"sender"* ]]; then
                sender_line="$_line"
            fi
        done <<< "$text"
    fi
    if [[ -z "$receiver_line" ]]; then
        while IFS= read -r _line; do
            if [[ "$_line" == *"[SUM]"* && "$_line" == *"receiver"* ]]; then
                receiver_line="$_line"
            fi
        done <<< "$text"
    fi

    if [[ -n "$sender_line" ]]; then
        local transfer bitrate retransmits
        transfer=$(_strat_iperf3_extract_transfer "$sender_line")
        bitrate=$(_strat_iperf3_extract_bitrate "$sender_line")
        retransmits=$(_strat_iperf3_extract_retransmits "$sender_line")
        [[ -n "$transfer" ]] && result+="sender_transfer ${transfer}"$'\n'
        [[ -n "$bitrate" ]] && result+="sender_bitrate ${bitrate}"$'\n'
        [[ -n "$retransmits" ]] && result+="sender_retransmits ${retransmits}"$'\n'
    fi

    if [[ -n "$receiver_line" ]]; then
        local transfer bitrate
        transfer=$(_strat_iperf3_extract_transfer "$receiver_line")
        bitrate=$(_strat_iperf3_extract_bitrate "$receiver_line")
        [[ -n "$transfer" ]] && result+="receiver_transfer ${transfer}"$'\n'
        [[ -n "$bitrate" ]] && result+="receiver_bitrate ${bitrate}"$'\n'
    fi

    # UDP specific: jitter and packet loss
    # "0.012 ms  0/1234 (0%)"
    if [[ "$text" == *"UDP"* ]]; then
        local udp_summary=""
        while IFS= read -r _line; do
            if [[ "$_line" =~ [0-9.]+\ ms && "$_line" =~ [0-9]+/[0-9]+ ]]; then
                udp_summary="$_line"
            fi
        done <<< "$text"
        if [[ -n "$udp_summary" ]]; then
            local jitter="" loss_pct=""
            read -ra _arr <<< "$udp_summary"
            local i
            for ((i=0; i<${#_arr[@]}; i++)); do
                if [[ "${_arr[$i]}" == "ms" && $i -ge 1 ]]; then
                    jitter="${_arr[$((i-1))]}"
                fi
            done
            # Extract loss percentage from (N%)
            if [[ "$udp_summary" =~ \(([0-9.]+)%\) ]]; then
                loss_pct="${BASH_REMATCH[1]}"
            fi
            [[ -n "$jitter" ]] && result+="jitter_ms ${jitter}"$'\n'
            [[ -n "$loss_pct" ]] && result+="packet_loss_pct ${loss_pct}"$'\n'
        fi
    fi

    echo "$result"
}

_strat_iperf3_extract_transfer () {
    local line="$1"
    # "1.10 GBytes" or "1234 MBytes"
    read -ra _arr <<< "$line"
    local i
    for ((i=0; i<${#_arr[@]}; i++)); do
        if [[ "${_arr[$i]}" == *"Bytes" ]]; then
            if [[ $i -ge 1 && "${_arr[$((i-1))]}" =~ ^[0-9] ]]; then
                echo "${_arr[$((i-1))]}_${_arr[$i]}"
            fi
            return
        fi
    done
}

_strat_iperf3_extract_bitrate () {
    local line="$1"
    # "941 Mbits/sec" or "9.41 Gbits/sec"
    read -ra _arr <<< "$line"
    local i
    for ((i=0; i<${#_arr[@]}; i++)); do
        if [[ "${_arr[$i]}" == *"bits/sec" ]]; then
            if [[ $i -ge 1 && "${_arr[$((i-1))]}" =~ ^[0-9] ]]; then
                echo "${_arr[$((i-1))]}_${_arr[$i]}"
            fi
            return
        fi
    done
}

_strat_iperf3_extract_retransmits () {
    local line="$1"
    # retransmits is the number between bitrate and "sender"
    # "[5] 0.00-10.00 sec 1.10 GBytes 941 Mbits/sec 0 sender"
    read -ra _arr <<< "$line"
    local i
    for ((i=0; i<${#_arr[@]}; i++)); do
        if [[ "${_arr[$i]}" == "sender" && $i -ge 1 ]]; then
            local val="${_arr[$((i-1))]}"
            if [[ "$val" =~ ^[0-9]+$ ]]; then
                echo "$val"
            fi
            return
        fi
    done
}
