#!/bin/bash
## Name: equals
## Description: Extract field=value pairs from equals-delimited data
## Version: 1.0
## Priority: 65
## Technique: yes
## Sample: samples/equals/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=35
    # Apply if input contains lines with equals signs that look like assignments
    # Skip lines that look like code (==, +=, !=)
    # Use while-read so ^ anchors match per-line (not start of entire string)
    local _det_line
    while IFS= read -r _det_line; do
        # Tight assignment: `KEY=value` (env vars, systemctl show, `git config
        # --list`'s dotted keys `user.name=…`). The key allows `.` so dotted
        # config keys match.
        [[ "$_det_line" =~ ^[A-Za-z][A-Za-z0-9_.\ -]*=[^=] ]] && return 0
        # Space-padded assignment with a rich key: `KEY(ctx) = value`,
        # `KEY(env: X) = value` (ansible-config dump). Requires ` = ` so it does
        # not fire on prose that merely contains a lone '='.
        [[ "$_det_line" =~ ^[A-Za-z][A-Za-z0-9_().:\ -]*\ =\ [^=] ]] && return 0
    done <<< "$text"
    return 1
}

strategy_extract () {
    local text="$1"

    # Clean text (dates, parentheses) -- cached by engine after first call
    clean_text "$text"; text="$_CLEAN_TEXT_RESULT"

    local result=""
    while IFS= read -r line; do
        # Skip empty lines
        [[ -z "$line" ]] && continue

        # Must contain = but not == (comparison) or += or !=
        [[ "$line" != *"="* ]] && continue
        [[ "$line" == *"=="* ]] && continue
        [[ "$line" == *"+="* ]] && continue
        [[ "$line" == *"!="* ]] && continue

        # Extract key (before first =) and value (after first =)
        local key value

        # Strip leading spaces and bullet markers
        local _stripped="$line"
        while [[ "$_stripped" == " "* ]]; do _stripped="${_stripped# }"; done
        if [[ "$_stripped" == "* "* ]]; then
            _stripped="${_stripped#\* }"
        fi

        key="${_stripped%%=*}"
        value="${_stripped#*=}"

        # Skip if key is empty or too long
        [[ -z "$key" ]] && continue
        [[ ${#key} -gt 50 ]] && continue

        # Skip lines where key starts with a digit
        [[ "$key" =~ ^[0-9] ]] && continue

        # Clean up key and value
        key="${key// /_}"
        key="${key#_}"
        key="${key%_}"

        while [[ "$value" == " "* ]]; do value="${value# }"; done
        while [[ "$value" == *" " ]]; do value="${value% }"; done

        # Skip if value is empty
        [[ -z "$value" ]] && continue

        result+="${key} ${value}"$'\n'
    done <<< "$text"

    echo "$result"
}
