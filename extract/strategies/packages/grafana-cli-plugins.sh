#!/bin/bash
## Name: grafana-cli-plugins
## Description: Extract plugins from `grafana-cli plugins ls` output (id @ version)
## Version: 1.0
## Priority: 22
## Technique: yes
## Sample: samples/grafana-cli-plugins/basic.txt

# `grafana-cli plugins ls` prints an "installed plugins:" header, one line per
# plugin of the form "<id> @ <version>", then a "Restart grafana ..." footer.
# Only the "<id> @ <version>" lines are data.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    local line
    while IFS= read -r line; do
        if [[ "$line" =~ ^[A-Za-z0-9._-]+[[:space:]]@[[:space:]][0-9] ]]; then
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
        [[ "$line" =~ ^[A-Za-z0-9._-]+[[:space:]]@[[:space:]][0-9] ]] || continue
        read -ra t <<< "$line"
        [[ ${#t[@]} -ge 3 ]] || continue
        entry=$((entry + 1))
        result+="entry${entry}.id ${t[0]}"$'\n'
        result+="entry${entry}.version ${t[2]}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
