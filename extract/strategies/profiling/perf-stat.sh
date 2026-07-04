#!/bin/bash
## Name: perf-stat
## Description: Extract hardware counter values from perf stat output
## Version: 1.0
## Priority: 45
## Technique: mixed
## Sample: samples/perf-stat/sample1.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90
    _is_json "$text" && return 1
    # perf stat output contains "Performance counter stats" and counter lines
    local has_header=0
    local has_counter=0
    while IFS= read -r line; do
        [[ "$line" == *"Performance counter stats"* ]] && has_header=1
        [[ "$line" == *"task-clock"* || "$line" == *"context-switches"* || "$line" == *"cpu-cycles"* || "$line" == *"instructions"* ]] && has_counter=1
        if [[ $has_header -eq 1 && $has_counter -eq 1 ]]; then
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

        # Skip header and separator lines
        [[ "$trimmed" == "#"* ]] && continue
        [[ "$trimmed" == "Performance counter"* ]] && continue

        # Extract "seconds time elapsed" and similar summary lines
        if [[ "$trimmed" == *"seconds time elapsed"* ]]; then
            local val="${trimmed%% seconds*}"
            while [[ "$val" == " "* ]]; do val="${val# }"; done
            result+="time_elapsed ${val}"$'\n'
            continue
        fi
        if [[ "$trimmed" == *"seconds user"* ]]; then
            local val="${trimmed%% seconds*}"
            while [[ "$val" == " "* ]]; do val="${val# }"; done
            result+="time_user ${val}"$'\n'
            continue
        fi
        if [[ "$trimmed" == *"seconds sys"* ]]; then
            local val="${trimmed%% seconds*}"
            while [[ "$val" == " "* ]]; do val="${val# }"; done
            result+="time_sys ${val}"$'\n'
            continue
        fi

        # Parse counter lines: "value counter-name  # comment"
        # Format: "1,234,567  counter-name   # 1.23 GHz"
        read -ra _arr <<< "$trimmed"
        [[ ${#_arr[@]} -lt 2 ]] && continue

        local value="${_arr[0]}"
        # Value should be numeric (with optional commas)
        local clean_val="${value//,/}"
        case "$clean_val" in
            [0-9]*) ;;
            *) continue ;;
        esac

        local counter="${_arr[1]}"
        # Normalize counter name (replace hyphens with underscores)
        counter="${counter//-/_}"

        # Extract comment (after #) if present
        local comment=""
        local i
        for ((i=2; i<${#_arr[@]}; i++)); do
            if [[ "${_arr[$i]}" == "#" ]]; then
                i=$((i + 1))
                while [[ $i -lt ${#_arr[@]} ]]; do
                    if [[ -z "$comment" ]]; then
                        comment="${_arr[$i]}"
                    else
                        comment="${comment}_${_arr[$i]}"
                    fi
                    i=$((i + 1))
                done
                break
            fi
        done

        result+="${counter} ${value}"$'\n'
        [[ -n "$comment" ]] && result+="${counter}.detail ${comment}"$'\n'
    done <<< "$text"

    echo "$result"
}
