#!/bin/bash
## Name: podman-ps
## Description: Extract container information from podman ps output
## Version: 1.0
## Priority: 22
## Technique: table
## Sample: samples/podman-ps/sample1.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90
    # Reject JSON
    _is_json "$text" && return 1
    # Must have CONTAINER ID and POD ID or PODMAN-specific columns
    local first_line=""
    while IFS= read -r _line; do
        [[ -z "$_line" ]] && continue
        first_line="$_line"
        break
    done <<< "$text"
    # Podman ps header contains CONTAINER ID and often POD ID
    if [[ "$first_line" == "CONTAINER ID"* && "$first_line" == *"POD ID"* ]]; then
        return 0
    fi
    # Also match if it has CONTAINER ID + NAMES (same as docker but detect via context)
    if [[ "$first_line" == "CONTAINER ID"* && "$first_line" == *"NAMES"* && "$first_line" == *"POD"* ]]; then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local row_num=0
    local past_header=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        if [[ "$line" == "CONTAINER ID"* ]]; then
            past_header=1
            continue
        fi
        [[ $past_header -eq 0 ]] && continue

        # Parse data rows by splitting on two-or-more spaces
        row_num=$((row_num + 1))
        local prefix="container${row_num}"

        read -ra _arr <<< "$line"
        [[ ${#_arr[@]} -lt 4 ]] && continue

        local cid="${_arr[0]}"
        local image="${_arr[1]}"
        local status=""
        local name=""

        # Find the last token as name
        name="${_arr[${#_arr[@]}-1]}"

        # Collect status tokens (between image and name, skipping command)
        local i
        local status_parts=""
        for ((i=2; i<${#_arr[@]}-1; i++)); do
            case "${_arr[$i]}" in
                Up|Exited|Created|Paused|Running|Dead|Restarting)
                    if [[ -z "$status_parts" ]]; then
                        status_parts="${_arr[$i]}"
                    else
                        status_parts="${status_parts}_${_arr[$i]}"
                    fi
                    ;;
            esac
        done
        [[ -n "$status_parts" ]] && status="$status_parts"

        result+="${prefix}.id ${cid}"$'\n'
        result+="${prefix}.image ${image}"$'\n'
        [[ -n "$status" ]] && result+="${prefix}.status ${status}"$'\n'
        [[ -n "$name" ]] && result+="${prefix}.name ${name}"$'\n'
    done <<< "$text"

    echo "$result"
}
