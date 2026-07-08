#!/bin/bash
## Name: memcached-stats
## Description: Extract key/value pairs from `memcached` STAT output (stats command)
## Version: 1.0
## Priority: 26
## Technique: yes
## Sample: samples/memcached-stats/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    # Distinctive signature: repeated "STAT <key> <value>" lines terminated by
    # a bare "END". df-h.txt and other tabular output have neither.
    local line stat=0 end=0
    while IFS= read -r line; do
        case "$line" in
            "STAT "*) stat=$((stat + 1)) ;;
            "END")    end=1 ;;
        esac
    done <<< "$text"
    if [[ $stat -ge 3 && $end -eq 1 ]]; then
        _STRATEGY_CONFIDENCE=86
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line
    while IFS= read -r line; do
        # Only "STAT <key> <value>" lines; the trailing "END" is skipped.
        case "$line" in
            "STAT "*) ;;
            *) continue ;;
        esac
        local rest="${line#STAT }"
        local key="${rest%% *}"
        local value="${rest#* }"
        [[ "$value" == "$rest" ]] && value=""   # key with no value
        [[ -n "$key" ]] || continue
        entry=$((entry + 1))
        result+="entry${entry}.key ${key}"$'\n'
        result+="entry${entry}.value ${value}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    printf '%s' "$result"
}
