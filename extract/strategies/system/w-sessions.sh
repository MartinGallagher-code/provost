#!/bin/bash
## Name: w-sessions
## Description: Extract per-session records from w output (user, tty, from, login, idle, jcpu, pcpu, what)
## Version: 1.0
## Priority: 18
## Sample: samples/w-sessions/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    _is_json "$text" && return 1
    # Distinctive signature: the w/uptime banner (contains "load average:") on
    # the first non-blank line, plus a later column header naming all of the
    # session columns.
    local first_seen=0 has_banner=0 has_header=0
    while IFS= read -r line; do
        if [[ $first_seen -eq 0 ]]; then
            [[ -z "${line//[[:space:]]/}" ]] && continue
            first_seen=1
            [[ "$line" == *"load average:"* ]] && has_banner=1
            continue
        fi
        if [[ "$line" == *"USER"* && "$line" == *"TTY"* && "$line" == *"FROM"* \
              && "$line" == *"LOGIN@"* && "$line" == *"IDLE"* && "$line" == *"JCPU"* \
              && "$line" == *"PCPU"* && "$line" == *"WHAT"* ]]; then
            has_header=1
        fi
    done <<< "$text"
    if [[ $has_banner -eq 1 && $has_header -eq 1 ]]; then
        _STRATEGY_CONFIDENCE=88
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0
    local past_header=0
    while IFS= read -r line; do
        if [[ $past_header -eq 0 ]]; then
            # The USER/TTY/.../WHAT column header ends the preamble.
            if [[ "$line" == *"USER"* && "$line" == *"TTY"* && "$line" == *"WHAT"* ]]; then
                past_header=1
            fi
            continue
        fi
        [[ -z "${line//[[:space:]]/}" ]] && continue

        # WHAT is the trailing free-text field (may contain spaces), so let the
        # last read variable soak up the remainder.
        local user tty from login idle jcpu pcpu what
        read -r user tty from login idle jcpu pcpu what <<< "$line"
        [[ -n "$user" ]] || continue

        entry=$((entry + 1))
        result+="entry${entry}.user ${user}"$'\n'
        result+="entry${entry}.tty ${tty}"$'\n'
        result+="entry${entry}.from ${from}"$'\n'
        result+="entry${entry}.login ${login}"$'\n'
        result+="entry${entry}.idle ${idle}"$'\n'
        result+="entry${entry}.jcpu ${jcpu}"$'\n'
        result+="entry${entry}.pcpu ${pcpu}"$'\n'
        result+="entry${entry}.what ${what}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
