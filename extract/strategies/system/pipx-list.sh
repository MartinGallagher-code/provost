#!/bin/bash
## Name: pipx-list
## Description: `pipx list` — one record per installed package (name, version)
## Version: 1.0
## Priority: 26
## Sample: samples/pipx-list/basic.txt

# `pipx list` prints a "venvs are in …" / "apps are exposed …" preamble, then one
# `   package <name> <version>, installed using Python …` line per package, each
# followed by indented `- <app>` lines. Emit one record per package (name,
# version), skipping the preamble and the `- app` sub-lines.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    local saw_pkg=0 _l
    while IFS= read -r _l; do
        [[ "$_l" =~ ^[[:space:]]+package[[:space:]]+[^[:space:]]+[[:space:]] ]] && { saw_pkg=1; break; }
    done <<< "$text"
    [[ $saw_pkg -eq 1 ]] || return 1
    _STRATEGY_CONFIDENCE=86
    return 0
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 _l
    while IFS= read -r _l; do
        [[ "$_l" =~ ^[[:space:]]+package[[:space:]]+([^[:space:]]+)[[:space:]]+([^[:space:],]+) ]] || continue
        entry=$((entry + 1))
        result+="entry${entry}.name ${BASH_REMATCH[1]}"$'\n'
        result+="entry${entry}.version ${BASH_REMATCH[2]}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
