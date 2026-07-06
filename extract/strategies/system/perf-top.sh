#!/bin/bash
## Name: perf-top
## Description: Extract per-symbol records from perf top output (overhead, shared_object, symbol)
## Version: 1.0
## Priority: 20
## Sample: samples/perf-top/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    # Distinctive signature: perf top's "Overhead  Shared Object  Symbol"
    # header, or its percentage rows carrying a [.]/[k] symbol marker.
    if [[ "$text" == *"Overhead"*"Shared Object"*"Symbol"* ]]; then
        _STRATEGY_CONFIDENCE=88
        return 0
    fi
    while IFS= read -r line; do
        if [[ "$line" == *"%"* ]] && { [[ "$line" == *"[.]"* ]] || [[ "$line" == *"[k]"* ]]; }; then
            _STRATEGY_CONFIDENCE=88
            return 0
        fi
    done <<< "$text"
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0
    while IFS= read -r line; do
        # Only rows shaped "<pct>%  <object>  [.] <symbol>" are data rows.
        [[ "$line" == *"%"* ]] || continue
        { [[ "$line" == *"[.]"* ]] || [[ "$line" == *"[k]"* ]]; } || continue

        local parts
        read -ra parts <<< "$line"
        [[ ${#parts[@]} -lt 4 ]] && continue

        local overhead="${parts[0]}"
        [[ "$overhead" == *"%" ]] || continue
        local shared_object="${parts[1]}"

        # symbol: everything after the [.]/[k] marker (markers quoted so the
        # bracket is matched literally, not as a glob character class).
        local symbol="${line#*"[.] "}"
        [[ "$symbol" == "$line" ]] && symbol="${line#*"[k] "}"
        symbol="${symbol#"${symbol%%[![:space:]]*}"}"
        symbol="${symbol%"${symbol##*[![:space:]]}"}"

        entry=$((entry + 1))
        result+="entry${entry}.overhead ${overhead}"$'\n'
        result+="entry${entry}.shared_object ${shared_object}"$'\n'
        result+="entry${entry}.symbol ${symbol}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
