#!/bin/bash
## Name: bundle-list
## Description: Extract gems from `bundle list` output (skips header + footer hints)
## Version: 1.0
## Priority: 26
## Technique: yes
## Sample: samples/bundle-list/basic.txt

# `bundle list` prints a header ("Gems included by the bundle:"), one bullet per
# gem ("  * <name> (<version>)"), then a footer hint
# ("Use `bundle info` to print more detailed information about a gem"). Only the
# bullet lines are data; the header and footer are skipped. Each gem becomes a
# record with name and version.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    # Distinctive header + at least one "  * name (version)" bullet.
    [[ "$text" == *"Gems included by the bundle:"* ]] || return 1
    local gems=0 line
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*\*[[:space:]]+[A-Za-z0-9._-]+[[:space:]]+\([^\)]+\)[[:space:]]*$ ]]; then
            gems=$((gems + 1))
        fi
    done <<< "$text"
    if [[ $gems -ge 1 ]]; then
        _STRATEGY_CONFIDENCE=86
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*\*[[:space:]]+[A-Za-z0-9._-]+[[:space:]]+\([^\)]+\)[[:space:]]*$ ]] || continue
        local body="${line#*\* }"
        local name="${body%% (*}"
        local ver="${body#*\(}"; ver="${ver%\)*}"
        entry=$((entry + 1))
        result+="entry${entry}.name ${name}"$'\n'
        result+="entry${entry}.version ${ver}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
