#!/bin/bash
## Name: valgrind-summary
## Description: Extract memory leak summary from Valgrind memcheck output
## Version: 1.0
## Priority: 22
## Technique: kv_colon
## Sample: samples/valgrind-summary/sample1.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=92
    _is_json "$text" && return 1
    # Valgrind output contains "==" prefix lines with "LEAK SUMMARY" or "HEAP SUMMARY"
    local has_summary=0
    while IFS= read -r line; do
        if [[ "$line" == *"LEAK SUMMARY"* || "$line" == *"HEAP SUMMARY"* ]]; then
            has_summary=1
            break
        fi
    done <<< "$text"
    [[ $has_summary -eq 1 ]] && return 0
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local section=""

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Strip the "==PID==" prefix
        local trimmed="$line"
        if [[ "$trimmed" == "=="*"=="* ]]; then
            trimmed="${trimmed#==*== }"
        fi
        while [[ "$trimmed" == " "* ]]; do trimmed="${trimmed# }"; done

        # Track sections
        case "$trimmed" in
            "HEAP SUMMARY:"*)
                section="heap"
                continue
                ;;
            "LEAK SUMMARY:"*)
                section="leak"
                continue
                ;;
            "ERROR SUMMARY:"*)
                # Parse inline: "ERROR SUMMARY: N errors from M contexts"
                local val="${trimmed#ERROR SUMMARY: }"
                local errors="${val%% *}"
                result+="error_summary.errors ${errors}"$'\n'
                continue
                ;;
        esac

        # Parse "key: value" within sections
        if [[ "$trimmed" == *": "* ]]; then
            local key="${trimmed%%:*}"
            local val="${trimmed#*: }"
            while [[ "$key" == " "* ]]; do key="${key# }"; done
            while [[ "$key" == *" " ]]; do key="${key% }"; done
            while [[ "$val" == " "* ]]; do val="${val# }"; done

            # Normalize key
            key="${key// /_}"
            key="${key,,}"

            # Extract the numeric value (first token, with commas)
            read -ra _varr <<< "$val"
            local num_val="${_varr[0]}"
            num_val="${num_val//,/}"

            # Extract bytes in parentheses if present
            local bytes=""
            if [[ "$val" == *"bytes"* ]]; then
                local tmp="${val#*in }"
                if [[ "$tmp" != "$val" ]]; then
                    bytes="${tmp%% *}"
                fi
            fi

            if [[ -n "$section" ]]; then
                result+="${section}.${key} ${num_val}"$'\n'
                [[ -n "$bytes" ]] && result+="${section}.${key}_bytes ${bytes}"$'\n'
            else
                result+="${key} ${num_val}"$'\n'
            fi
        fi
    done <<< "$text"

    echo "$result"
}
