#!/bin/bash
## Name: lynis-audit
## Description: Extract security audit results from Lynis audit summary output
## Version: 1.0
## Priority: 20
## Technique: kv_colon
## Sample: samples/lynis-audit/sample1.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90
    _is_json "$text" && return 1
    # Lynis output contains "Hardening index" and "Tests performed"
    local has_hardening=0
    local has_tests=0
    while IFS= read -r line; do
        [[ "$line" == *"Hardening index"* ]] && has_hardening=1
        [[ "$line" == *"Tests performed"* ]] && has_tests=1
        if [[ $has_hardening -eq 1 && $has_tests -eq 1 ]]; then
            return 0
        fi
    done <<< "$text"
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local trimmed="$line"
        while [[ "$trimmed" == " "* ]]; do trimmed="${trimmed# }"; done

        # Skip decoration lines
        [[ "$trimmed" == "="* ]] && continue
        [[ "$trimmed" == "-"* ]] && continue
        [[ "$trimmed" == "["* ]] && continue

        # Parse key : value lines
        if [[ "$trimmed" == *" : "* ]]; then
            local key="${trimmed%% : *}"
            local val="${trimmed#* : }"
            while [[ "$key" == " "* ]]; do key="${key# }"; done
            while [[ "$key" == *" " ]]; do key="${key% }"; done
            while [[ "$val" == " "* ]]; do val="${val# }"; done
            while [[ "$val" == *" " ]]; do val="${val% }"; done
            key="${key// /_}"
            key="${key,,}"
            val="${val// /_}"
            [[ -z "$key" || -z "$val" ]] && continue
            result+="${key} ${val}"$'\n'
        fi
    done <<< "$text"

    echo "$result"
}
