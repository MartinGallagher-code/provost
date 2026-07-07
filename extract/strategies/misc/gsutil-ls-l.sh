#!/bin/bash
## Name: gsutil-ls-l
## Description: Extract objects from `gsutil ls -l` output (size, timestamp, gs:// url; skips TOTAL footer)
## Version: 1.0
## Priority: 22
## Technique: yes
## Sample: samples/gsutil-ls-l/basic.txt

# `gsutil ls -l` prints one row per object: "<size>  <ISO-timestamp>  gs://<url>"
# followed by a "TOTAL: N objects, ..." footer. Only the gs:// object rows are
# data.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    local line
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*[0-9]+[[:space:]]+[0-9T:-]+Z?[[:space:]]+gs:// ]]; then
            _STRATEGY_CONFIDENCE=86
            return 0
        fi
    done <<< "$text"
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line
    local -a t
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*[0-9]+[[:space:]]+[0-9T:-]+Z?[[:space:]]+gs:// ]] || continue
        read -ra t <<< "$line"
        [[ ${#t[@]} -ge 3 ]] || continue
        entry=$((entry + 1))
        result+="entry${entry}.size ${t[0]}"$'\n'
        result+="entry${entry}.timestamp ${t[1]}"$'\n'
        result+="entry${entry}.url ${t[2]}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
