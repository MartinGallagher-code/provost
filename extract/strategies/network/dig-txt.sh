#!/bin/bash
## Name: dig-txt
## Description: Extract TXT answer records from `dig TXT` output
## Version: 1.0
## Priority: 9
## Technique: yes
## Sample: samples/dig-txt/basic.txt

# `dig TXT <name>` prints one answer per line in the ANSWER SECTION:
#   example.com.        300     IN      TXT     "v=spf1 include:_spf.google.com ~all"
# Fields are name TTL class(IN) type(TXT) then the quoted text (which may itself
# contain spaces). Comment lines begin with ';' and are skipped.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=86
    local line
    while IFS= read -r line; do
        [[ "$line" == ";"* ]] && continue
        local -a f=()
        read -ra f <<< "$line"
        [[ ${#f[@]} -ge 5 && "${f[2]}" == "IN" && "${f[3]}" == "TXT" ]] && return 0
    done <<< "$text"
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line
    while IFS= read -r line; do
        [[ "$line" == ";"* ]] && continue
        local -a f=()
        read -ra f <<< "$line"
        [[ ${#f[@]} -ge 5 && "${f[2]}" == "IN" && "${f[3]}" == "TXT" ]] || continue
        entry=$((entry + 1))
        # Reassemble the TXT payload (fields 5..end) and sanitise spaces.
        local txt="" i
        for ((i = 4; i < ${#f[@]}; i++)); do
            if [[ -z "$txt" ]]; then txt="${f[$i]}"; else txt="${txt}_${f[$i]}"; fi
        done
        result+="entry${entry}.name ${f[0]}"$'\n'
        result+="entry${entry}.ttl ${f[1]}"$'\n'
        result+="entry${entry}.class ${f[2]}"$'\n'
        result+="entry${entry}.type ${f[3]}"$'\n'
        result+="entry${entry}.text ${txt}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    printf '%s' "$result"
}
