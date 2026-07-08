#!/bin/bash
## Name: rc-status
## Description: Extract service states from OpenRC rc-status output
## Version: 1.0
## Priority: 26
## Technique: yes
## Sample: samples/rc-status/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    _is_json "$text" && return 1
    # OpenRC rc-status: a "Runlevel:" header and "svc   [  started  ]" lines.
    local has_runlevel=0 svc=0 line
    while IFS= read -r line; do
        case "$line" in
            "Runlevel:"*) has_runlevel=1 ;;
        esac
        if [[ "$line" == *"[ "*" ]"* ]] && { [[ "$line" == *"started"* ]] || [[ "$line" == *"stopped"* ]] || [[ "$line" == *"crashed"* ]]; }; then
            svc=$((svc + 1))
        fi
    done <<< "$text"
    if [[ $has_runlevel -eq 1 && $svc -ge 1 ]]; then
        _STRATEGY_CONFIDENCE=86
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local entry=0
    local line trimmed service status
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        case "$line" in
            "Runlevel:"*) continue ;;
        esac
        # A service line has a "[ ... ]" status bracket.
        [[ "$line" == *"["*"]"* ]] || continue

        trimmed="${line#"${line%%[![:space:]]*}"}"
        service="${trimmed%%[[:space:]]*}"
        [[ -n "$service" ]] || continue

        # Status is the text between the brackets, whitespace stripped.
        status="${line#*[}"
        status="${status%%]*}"
        status="${status//[[:space:]]/}"

        entry=$((entry + 1))
        result+="entry${entry}.service ${service}"$'\n'
        result+="entry${entry}.status ${status}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
