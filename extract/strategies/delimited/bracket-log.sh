#!/bin/bash
## Name: bracket-log
## Description: Log lines prefixed with a [bracketed] timestamp/tag (dmesg, kernel ring buffer, many app logs)
## Version: 1.0
## Priority: 48
## Sample: samples/bracket-log/dmesg.txt

# Matches lines shaped like `[<tag>] <message>` — dmesg / kernel ring buffer
# (`[    0.000000] Linux version …`), and app logs that lead with a bracketed
# timestamp or level. Tidied to one row per line: (timestamp, message).

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0

    local nonblank=0 bracketed=0 _l
    while IFS= read -r _l; do
        [[ -z "${_l//[[:space:]]/}" ]] && continue
        nonblank=$((nonblank + 1))
        # leading (optional ws) '[', some content, ']', then a space + message
        [[ "$_l" =~ ^[[:space:]]*\[[^]]+\][[:space:]]+[^[:space:]] ]] && bracketed=$((bracketed + 1))
        [[ $nonblank -ge 40 ]] && break
    done <<< "$text"

    [[ $nonblank -lt 2 ]] && return 1
    # Strong majority of lines must be bracket-prefixed.
    [[ $(( bracketed * 100 / nonblank )) -lt 80 ]] && return 1
    _STRATEGY_CONFIDENCE=85
    return 0
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 _l
    while IFS= read -r _l; do
        [[ -z "${_l//[[:space:]]/}" ]] && continue
        [[ "$_l" =~ ^[[:space:]]*\[[^]]+\][[:space:]]+[^[:space:]] ]] || continue

        # timestamp/tag = text between the first '[' and ']'
        local ts="${_l#*[}"; ts="${ts%%]*}"
        # message = everything after the first ']'
        local msg="${_l#*]}"
        # trim surrounding whitespace
        ts="${ts#"${ts%%[![:space:]]*}"}"; ts="${ts%"${ts##*[![:space:]]}"}"
        msg="${msg#"${msg%%[![:space:]]*}"}"; msg="${msg%"${msg##*[![:space:]]}"}"

        entry=$((entry + 1))
        result+="entry${entry}.timestamp ${ts}"$'\n'
        [[ -n "$msg" ]] && result+="entry${entry}.message ${msg}"$'\n'
    done <<< "$text"

    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
