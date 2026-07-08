#!/bin/bash
## Name: fail2ban-status
## Description: Extract jail status from fail2ban-client status output
## Version: 1.0
## Priority: 20
## Technique: kv_colon
## Sample: samples/fail2ban-status/sample1.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90
    _is_json "$text" && return 1
    # fail2ban-client status output contains "Number of jail" and "Jail list"
    # fail2ban-client status <jail> contains "Currently banned" and "Total banned"
    local has_jail=0
    local has_banned=0
    while IFS= read -r line; do
        [[ "$line" == *"Jail list"* || "$line" == *"Number of jail"* ]] && has_jail=1
        [[ "$line" == *"Currently banned"* || "$line" == *"Total banned"* ]] && has_banned=1
    done <<< "$text"
    if [[ $has_jail -eq 1 || $has_banned -eq 1 ]]; then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local section=""

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local trimmed="$line"
        while [[ "$trimmed" == " "* ]]; do trimmed="${trimmed# }"; done
        # Remove leading "|- " or "`- " tree markers
        case "$trimmed" in
            "|- "*) trimmed="${trimmed#|- }" ;;
            "\`- "*) trimmed="${trimmed#\`- }" ;;
        esac

        # Track sections
        case "$trimmed" in
            "Status for the jail:"*|"Status")
                continue
                ;;
            *"Filter"*)
                section="filter"
                continue
                ;;
            *"Actions"*)
                section="actions"
                continue
                ;;
        esac

        # Parse key: value pairs
        if [[ "$trimmed" == *":"* ]]; then
            local key="${trimmed%%:*}"
            local val="${trimmed#*:}"
            while [[ "$val" == " "* ]]; do val="${val# }"; done
            while [[ "$val" == *" " ]]; do val="${val% }"; done
            # Normalize key
            key="${key// /_}"
            # Lowercase key
            key="${key,,}"
            [[ -z "$val" ]] && continue
            if [[ -n "$section" ]]; then
                result+="${section}.${key} ${val}"$'\n'
            else
                result+="${key} ${val}"$'\n'
            fi
        fi
    done <<< "$text"

    echo "$result"
}
