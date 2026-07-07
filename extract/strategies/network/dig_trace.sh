#!/bin/bash
## Name: dig_trace
## Description: Extract delegation records from `dig +trace` output
## Version: 1.0
## Priority: 8
## Technique: yes
## Sample: samples/dig_trace/basic.txt

# `dig +trace <name>` walks the delegation chain, printing several groups of
# answer rows (root NS, TLD NS, zone NS, final A/...) separated by
# `;; Received N bytes from ...` lines and blanks:
#   .            84392   IN   NS   a.root-servers.net.
#   com.         172800  IN   NS   a.gtld-servers.net.
# We emit one record per answer row `name TTL IN TYPE value` across ALL groups.
# `;`-comment lines (banner, `;; Received`) and blanks are skipped. Detection
# keys on the dig banner naming a +trace query plus the `Received ... from` lines.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=86
    local line banner=0 recv=0 answer=0
    while IFS= read -r line; do
        [[ "$line" == *"<<>>"*"+trace"* ]] && banner=1
        [[ "$line" == *"Received "*" bytes from "* ]] && recv=1
        [[ -z "$line" || "$line" == ";"* ]] && continue
        local -a f=()
        read -ra f <<< "$line"
        [[ ${#f[@]} -ge 5 && "${f[2]}" == "IN" && "${f[1]}" =~ ^[0-9]+$ ]] && answer=1
    done <<< "$text"
    [[ $banner -eq 1 && $recv -eq 1 && $answer -eq 1 ]] && return 0
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line
    while IFS= read -r line; do
        [[ -z "$line" || "$line" == ";"* ]] && continue
        local -a f=()
        read -ra f <<< "$line"
        [[ ${#f[@]} -ge 5 && "${f[2]}" == "IN" && "${f[1]}" =~ ^[0-9]+$ ]] || continue
        local val="" i
        for ((i=4; i<${#f[@]}; i++)); do
            if [[ -z "$val" ]]; then val="${f[$i]}"; else val="${val}_${f[$i]}"; fi
        done
        val="${val// /_}"
        entry=$((entry + 1))
        result+="entry${entry}.name ${f[0]}"$'\n'
        result+="entry${entry}.ttl ${f[1]}"$'\n'
        result+="entry${entry}.class ${f[2]}"$'\n'
        result+="entry${entry}.type ${f[3]}"$'\n'
        result+="entry${entry}.value ${val}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    printf '%s' "$result"
}
