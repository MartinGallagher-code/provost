#!/bin/bash
## Name: semanage-boolean
## Description: Extract SELinux booleans from `semanage boolean -l` output (name, state, description)
## Version: 1.0
## Priority: 26
## Technique: yes
## Sample: samples/semanage-boolean/basic.txt

# `semanage boolean -l` prints a header
# ("SELinux boolean  State  Default Description"), a blank line, then one row per
# boolean: "<name>  (<state> , <default>)  <description>". The header is skipped;
# each boolean becomes a record with its name, current state, and description.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    # Distinctive: the "SELinux boolean" header plus "(on/off , on/off)" rows.
    [[ "$text" == *"SELinux boolean"* ]] || return 1
    local line rows=0
    while IFS= read -r line; do
        if [[ "$line" =~ ^[A-Za-z0-9_]+[[:space:]]+\((on|off)[[:space:]]*, ]]; then
            rows=$((rows + 1))
        fi
    done <<< "$text"
    if [[ $rows -ge 1 ]]; then
        _STRATEGY_CONFIDENCE=86
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line name state rest desc
    while IFS= read -r line; do
        [[ "$line" =~ ^[A-Za-z0-9_]+[[:space:]]+\((on|off)[[:space:]]*, ]] || continue
        name="${line%%[[:space:]]*}"
        # State is the first token inside the parentheses.
        rest="${line#*\(}"
        state="${rest%%[[:space:]]*,*}"
        state="${state%%[[:space:]]*}"
        # Description follows the closing paren.
        desc="${line#*\)}"
        # Trim leading/trailing whitespace, collapse spaces to underscores.
        desc="${desc#"${desc%%[![:space:]]*}"}"
        desc="${desc%"${desc##*[![:space:]]}"}"
        desc="${desc//[[:space:]]/_}"
        entry=$((entry + 1))
        result+="entry${entry}.name ${name}"$'\n'
        result+="entry${entry}.state ${state}"$'\n'
        result+="entry${entry}.description ${desc}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
