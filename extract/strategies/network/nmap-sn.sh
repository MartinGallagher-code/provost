#!/bin/bash
## Name: nmap-sn
## Description: Extract discovered hosts (host/ip/latency) from `nmap -sn` output
## Version: 1.0
## Priority: 14
## Sample: samples/nmap-sn/basic.txt

# `nmap -sn` host discovery prints a "Starting Nmap" banner, then one
# "Nmap scan report for <host> (<ip>)" line per host (each followed by a
# "Host is up (<lat> latency)." line), then a "Nmap done:" summary line.
# One record per host; banner and summary are skipped.

_nmapsn_is_report () {
    [[ "$1" == "Nmap scan report for "* ]]
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    local line saw_report=0 saw_up=0 saw_ports=0
    while IFS= read -r line; do
        _nmapsn_is_report "$line" && saw_report=1
        [[ "$line" == "Host is up"* ]] && saw_up=1
        # A PORT table means a full scan, not a -sn ping sweep — that input
        # belongs to the nmap strategy.
        [[ "$line" == "PORT"*"STATE"* ]] && saw_ports=1
    done <<< "$text"
    if [[ $saw_report -eq 1 && $saw_up -eq 1 && $saw_ports -eq 0 ]]; then
        _STRATEGY_CONFIDENCE=86
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line
    local -a hosts=() ips=() lats=()
    while IFS= read -r line; do
        if _nmapsn_is_report "$line"; then
            local target="${line#Nmap scan report for }"
            local host="$target" ip="$target"
            if [[ "$target" == *"("*")"* ]]; then
                host="${target%% (*}"
                ip="${target##*(}"; ip="${ip%)}"
            fi
            entry=$((entry + 1))
            hosts[$entry]="$host"
            ips[$entry]="$ip"
            lats[$entry]=""
        elif [[ "$line" == "Host is up"* && $entry -ge 1 ]]; then
            if [[ "$line" == *"("*"latency)"* ]]; then
                local lat="${line#*(}"
                lat="${lat%% *}"
                lats[$entry]="$lat"
            fi
        fi
    done <<< "$text"
    local i
    for ((i = 1; i <= entry; i++)); do
        local host="${hosts[$i]}" ip="${ips[$i]}" lat="${lats[$i]}"
        result+="entry${i}.host ${host}"$'\n'
        result+="entry${i}.ip ${ip}"$'\n'
        result+="entry${i}.latency ${lat}"$'\n'
    done
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
