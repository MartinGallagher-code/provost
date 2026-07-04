#!/bin/bash
## Name: properties
## Description: Extract key/value pairs from Java .properties files
## Version: 1.0
## Priority: 18
## Sample: samples/properties/basic.properties

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=80

    # Must NOT be JSON
    _is_json "$text" && return 1

    # Must NOT have INI section headers [section]
    local _nl=$'\n'
    local _re_section="(^|${_nl})\\["
    [[ "$text" =~ $_re_section ]] && return 1

    # Must have comment lines (# or !)
    local has_comment=0
    local _re_hash="(^|${_nl})#"
    local _re_bang="(^|${_nl})!"
    if [[ "$text" =~ $_re_hash ]] || [[ "$text" =~ $_re_bang ]]; then
        has_comment=1
    fi
    [[ $has_comment -eq 1 ]] || return 1

    # Must have key=value or key:value lines where key starts with letter
    # and contains letters, digits, dots, hyphens, underscores
    local _re_kv="(^|${_nl})[a-zA-Z][a-zA-Z0-9._-]*[=:]"
    [[ "$text" =~ $_re_kv ]] || return 1

    return 0
}

strategy_extract () {
    local text="$1"

    local result=""
    local continuation=""

    while IFS= read -r line; do
        # Handle line continuation
        if [[ -n "$continuation" ]]; then
            # Strip leading whitespace from continuation line
            local cont_trimmed="$line"
            while [[ "$cont_trimmed" == " "* || "$cont_trimmed" == "	"* ]]; do cont_trimmed="${cont_trimmed#?}"; done

            # Check if this continuation line also ends with backslash
            if [[ "$cont_trimmed" == *"\\" ]]; then
                continuation="${continuation}${cont_trimmed%\\}"
                continue
            else
                continuation="${continuation}${cont_trimmed}"
                line="$continuation"
                continuation=""
            fi
        fi

        # Skip empty lines
        [[ -z "$line" ]] && continue

        # Skip comment lines (# or !)
        local trimmed="$line"
        while [[ "$trimmed" == " "* || "$trimmed" == "	"* ]]; do trimmed="${trimmed#?}"; done
        case "$trimmed" in
            '#'*|'!'*) continue ;;
        esac

        # Check for line continuation (ends with \)
        if [[ "$trimmed" == *"\\" ]]; then
            continuation="${trimmed%\\}"
            continue
        fi

        # Try to extract key=value, key:value, or key value
        local key="" value=""
        if [[ "$trimmed" == *"="* ]]; then
            key="${trimmed%%=*}"
            value="${trimmed#*=}"
        elif [[ "$trimmed" == *":"* ]]; then
            key="${trimmed%%:*}"
            value="${trimmed#*:}"
        elif [[ "$trimmed" == *" "* ]]; then
            key="${trimmed%% *}"
            value="${trimmed#* }"
        else
            continue
        fi

        # Trim whitespace from key
        while [[ "$key" == " "* || "$key" == "	"* ]]; do key="${key#?}"; done
        while [[ "$key" == *" " || "$key" == *"	" ]]; do key="${key%?}"; done

        # Trim whitespace from value
        while [[ "$value" == " "* || "$value" == "	"* ]]; do value="${value#?}"; done
        while [[ "$value" == *" " || "$value" == *"	" ]]; do value="${value%?}"; done

        # Skip if key or value is empty
        [[ -z "$key" ]] && continue
        [[ -z "$value" ]] && continue

        # Replace spaces in key and value with underscores
        key="${key// /_}"
        value="${value// /_}"

        result+="${key} ${value}"$'\n'
    done <<< "$text"

    echo "$result"
}
