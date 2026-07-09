#!/bin/bash
## Name: host_a
## Description: Extract DNS answer records from `host -a` output
## Version: 1.0
## Priority: 8
## Sample: samples/host_a/basic.txt

# `host -a <name>` prints a verbose dig-style report. Its ANSWER SECTION carries
# rows of the shape `name TTL IN TYPE value`:
#   example.com.   86400   IN   A   93.184.216.34
# Plain `host <name>` (no -a) instead prints one of:
#   example.com has address 93.184.216.34
#   example.com has IPv6 address 2606:2800:...
#   example.com mail is handled by 10 mail.example.com.
# We emit one record per answer line, handling all forms. Banner (`;`/`;;`),
# the `Trying "..."` and `Received ... bytes from` lines and blanks are skipped.
# Detection keys on the `Trying "..."` banner or the plain-host answer phrasings.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=86
    local line
    while IFS= read -r line; do
        [[ "$line" == 'Trying "'* ]] && return 0
        [[ "$line" == *" has address "* ]] && return 0
        [[ "$line" == *" has IPv6 address "* ]] && return 0
        [[ "$line" == *" mail is handled by "* ]] && return 0
    done <<< "$text"
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line
    while IFS= read -r line; do
        [[ -z "$line" || "$line" == ";"* ]] && continue
        [[ "$line" == 'Trying "'* ]] && continue

        # Plain-host phrasings first.
        if [[ "$line" == *" has address "* ]]; then
            local nm="${line%% has address *}" v="${line##* has address }"
            entry=$((entry + 1))
            result+="entry${entry}.name ${nm}"$'\n'
            result+="entry${entry}.type A"$'\n'
            result+="entry${entry}.value ${v}"$'\n'
            continue
        fi
        if [[ "$line" == *" has IPv6 address "* ]]; then
            local nm="${line%% has IPv6 address *}" v="${line##* has IPv6 address }"
            entry=$((entry + 1))
            result+="entry${entry}.name ${nm}"$'\n'
            result+="entry${entry}.type AAAA"$'\n'
            result+="entry${entry}.value ${v}"$'\n'
            continue
        fi
        if [[ "$line" == *" mail is handled by "* ]]; then
            local nm="${line%% mail is handled by *}" v="${line##* mail is handled by }"
            entry=$((entry + 1))
            result+="entry${entry}.name ${nm}"$'\n'
            result+="entry${entry}.type MX"$'\n'
            result+="entry${entry}.value ${v}"$'\n'
            continue
        fi

        # dig-style answer row: name TTL IN TYPE value...
        local -a f=()
        read -ra f <<< "$line"
        [[ ${#f[@]} -ge 5 && "${f[2]}" == "IN" && "${f[1]}" =~ ^[0-9]+$ ]] || continue
        local val="" i
        for ((i=4; i<${#f[@]}; i++)); do
            if [[ -z "$val" ]]; then val="${f[$i]}"; else val="${val}_${f[$i]}"; fi
        done
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
