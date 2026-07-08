#!/bin/bash
## Name: markdown-frontmatter
## Description: Extract key/value pairs from YAML frontmatter in Markdown files (Jekyll, Hugo, Gatsby, Astro)
## Version: 1.0
## Priority: 12
## Sample: samples/markdown-frontmatter/basic.md

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90

    # Must NOT be JSON
    _is_json "$1" && return 1

    # First line must be exactly ---
    local first_line="${text%%$'\n'*}"
    [[ "$first_line" == "---" ]] || return 1

    # Must have a second --- later in the text (closing delimiter)
    local after_first="${text#*$'\n'}"
    [[ "$after_first" == *$'\n'"---"* || "$after_first" == "---" ]] || return 1

    return 0
}

strategy_extract () {
    local text="$1"
    local result=""
    local in_frontmatter=0
    local found_open=0

    while IFS= read -r line; do
        # Handle opening ---
        if [[ $found_open -eq 0 ]]; then
            if [[ "$line" == "---" ]]; then
                found_open=1
                in_frontmatter=1
            fi
            continue
        fi

        # Handle closing ---
        if [[ "$line" == "---" ]]; then
            break
        fi

        # Skip empty lines
        [[ -z "$line" ]] && continue

        # Skip comment lines
        local trimmed="$line"
        while [[ "$trimmed" == " "* || "$trimmed" == "	"* ]]; do trimmed="${trimmed#?}"; done
        case "$trimmed" in
            '#'*) continue ;;
        esac

        # Parse key: value pairs (simple flat YAML only)
        if [[ "$trimmed" =~ ^[a-zA-Z][a-zA-Z0-9_-]*: ]]; then
            local key="${trimmed%%:*}"
            local value="${trimmed#*:}"

            # Trim leading whitespace from value
            while [[ "$value" == " "* || "$value" == "	"* ]]; do value="${value#?}"; done
            # Trim trailing whitespace from value
            while [[ "$value" == *" " || "$value" == *"	" ]]; do value="${value%?}"; done

            # Skip keys with no value (nested YAML sections)
            [[ -z "$value" ]] && continue

            result+="${key} ${value}"$'\n'
        fi
    done <<< "$text"

    echo "$result"
}
