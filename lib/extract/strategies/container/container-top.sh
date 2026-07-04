#!/bin/bash
## Name: container-top
## Description: Extract process list from docker top or podman top output
## Version: 1.0
## Priority: 25
## Technique: table
## Sample: samples/container-top/sample1.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=85
    _is_json "$text" && return 1
    # docker/podman top output has UID/USER PID PPID columns
    local first_line=""
    while IFS= read -r _line; do
        [[ -z "$_line" ]] && continue
        first_line="$_line"
        break
    done <<< "$text"
    if [[ "$first_line" == *"PID"* && "$first_line" == *"PPID"* && "$first_line" == *"CMD"* ]]; then
        return 0
    fi
    if [[ "$first_line" == *"UID"* && "$first_line" == *"PID"* && "$first_line" == *"CMD"* ]]; then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local row_num=0
    local past_header=0

    # Find header columns
    local header_line=""
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        if [[ "$line" == *"PID"* && "$line" == *"CMD"* ]]; then
            header_line="$line"
            past_header=1
            continue
        fi
        [[ $past_header -eq 0 ]] && continue

        read -ra _arr <<< "$line"
        [[ ${#_arr[@]} -lt 3 ]] && continue

        row_num=$((row_num + 1))
        local prefix="proc${row_num}"

        # Typical columns: UID PID PPID C STIME TTY TIME CMD
        local uid="${_arr[0]}"
        local pid="${_arr[1]}"
        local ppid="${_arr[2]}"

        # CMD is everything from index 7 onward (or last fields)
        local cmd=""
        local i
        local cmd_start=7
        if [[ ${#_arr[@]} -le 7 ]]; then
            cmd_start=$((${#_arr[@]} - 1))
        fi
        for ((i=cmd_start; i<${#_arr[@]}; i++)); do
            if [[ -z "$cmd" ]]; then
                cmd="${_arr[$i]}"
            else
                cmd="${cmd}_${_arr[$i]}"
            fi
        done

        result+="${prefix}.uid ${uid}"$'\n'
        result+="${prefix}.pid ${pid}"$'\n'
        result+="${prefix}.ppid ${ppid}"$'\n'
        [[ -n "$cmd" ]] && result+="${prefix}.cmd ${cmd}"$'\n'
    done <<< "$text"

    echo "$result"
}
