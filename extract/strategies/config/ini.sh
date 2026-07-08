#!/bin/bash
## Name: ini
## Description: Extract key/value pairs from INI/config files with section support
## Version: 1.0
## Priority: 15
## Sample: samples/ini/basic.ini

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=85

    # Must contain at least one section header line matching [something]
    # First check: newline followed by [section] (for multi-line input)
    # Second check: first line starts with [section] (single-line or first-line header)
    [[ "$text" =~ $'\n'"["[^]]+"]" ]] || [[ "${text%%$'\n'*}" == "["*"]"* ]]
}

strategy_extract () {
    local text="$1"

    local result=""
    local section=""

    while IFS= read -r line; do
        # Skip empty lines
        [[ -z "$line" ]] && continue

        # Skip comment lines (# or ;)
        case "$line" in
            '#'*|';'*) continue ;;
        esac

        # Check for section header [section]
        if [[ "$line" =~ ^\[.+\]$ ]]; then
            section="${line#\[}"
            section="${section%\]}"
            section="${section// /_}"
            continue
        fi

        # Check for key=value or key: value
        local key value
        if [[ "$line" == *"="* ]]; then
            key="${line%%=*}"
            value="${line#*=}"
            # Trim leading spaces from value
            while [[ "$value" == " "* ]]; do value="${value# }"; done
        elif [[ "$line" == *":"* ]]; then
            key="${line%%:*}"
            value="${line#*:}"
            # Trim leading spaces from value
            while [[ "$value" == " "* ]]; do value="${value# }"; done
        else
            continue
        fi

        # Skip if key or value is empty
        [[ -z "$key" ]] && continue
        [[ -z "$value" ]] && continue

        # Clean up key and value
        while [[ "$key" == " "* ]]; do key="${key# }"; done
        while [[ "$key" == *" " ]]; do key="${key% }"; done
        key="${key// /_}"
        while [[ "$value" == " "* ]]; do value="${value# }"; done
        while [[ "$value" == *" " ]]; do value="${value% }"; done

        # Prefix with section if we have one
        if [[ -n "$section" ]]; then
            result+="${section}.${key} ${value}"$'\n'
        else
            result+="${key} ${value}"$'\n'
        fi
    done <<< "$text"

    echo "$result"
}
