#!/bin/bash
## Name: ping-stats
## Description: Extract statistics from ping command output (packets, RTT min/avg/max/mdev)
## Version: 1.0
## Priority: 35
## Sample: samples/ping/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=95
    # Reject JSON
    _is_json "$1" && return 1
    # Must contain ping statistics marker
    [[ "$text" == *"ping statistics"* ]] || return 1
    # Must contain packet stats (rtt line only present if packets received)
    [[ "$text" == *"packets transmitted"* ]] || return 1
    return 0
}

strategy_extract () {
    local text="$1"
    local result=""

    # Extract destination host from "PING host (ip)" line
    while IFS= read -r _l; do
        [[ -z "$_l" ]] && continue
        if [[ "$_l" == "PING "* ]]; then
            local after="${_l#PING }"
            local host="${after%% (*}"
            [[ -n "$host" ]] && result+="host ${host}"$'\n'
            # Extract IP
            if [[ "$after" == *"("*")"* ]]; then
                local ip="${after#*(}"
                ip="${ip%%)*}"
                [[ -n "$ip" ]] && result+="ip ${ip}"$'\n'
            fi
            break
        fi
    done <<< "$text"

    # Extract packet stats: "N packets transmitted, N received, N% packet loss, time Nms"
    while IFS= read -r _l; do
        if [[ "$_l" == *"packets transmitted"* ]]; then
            if [[ "$_l" =~ ([0-9]+)[[:space:]]+packets[[:space:]]+transmitted ]]; then
                result+="packets_sent ${BASH_REMATCH[1]}"$'\n'
            fi
            if [[ "$_l" =~ ([0-9]+)[[:space:]]+received ]]; then
                result+="packets_received ${BASH_REMATCH[1]}"$'\n'
            fi
            if [[ "$_l" =~ ([0-9.]+)%[[:space:]]+packet[[:space:]]+loss ]]; then
                result+="packet_loss_pct ${BASH_REMATCH[1]}"$'\n'
            fi
            if [[ "$_l" =~ time[[:space:]]+([0-9]+)ms ]]; then
                result+="time_ms ${BASH_REMATCH[1]}"$'\n'
            fi
        fi
    done <<< "$text"

    # Extract RTT stats: "rtt min/avg/max/mdev = 1.234/2.345/3.456/0.567 ms"
    # Also handles macOS: "round-trip min/avg/max/stddev = ..."
    while IFS= read -r _l; do
        if [[ "$_l" =~ (rtt|round-trip)[[:space:]].*=[[:space:]]*([0-9.]+)/([0-9.]+)/([0-9.]+)/([0-9.]+) ]]; then
            result+="rtt_min ${BASH_REMATCH[2]}"$'\n'
            result+="rtt_avg ${BASH_REMATCH[3]}"$'\n'
            result+="rtt_max ${BASH_REMATCH[4]}"$'\n'
            result+="rtt_mdev ${BASH_REMATCH[5]}"$'\n'
            break
        fi
    done <<< "$text"

    [[ -n "$result" ]] && echo "${result%$'\n'}"
}
