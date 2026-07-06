#!/bin/bash
## Name: docker-compose-ps
## Description: Extract service status from docker compose ps output
## Version: 1.0
## Priority: 20
## Technique: table
## Sample: samples/docker-compose-ps/sample1.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=88
    _is_json "$text" && return 1
    # docker compose ps v2 header: NAME  IMAGE  COMMAND  SERVICE  CREATED  STATUS  PORTS
    local first_line=""
    while IFS= read -r _line; do
        [[ -z "$_line" ]] && continue
        first_line="$_line"
        break
    done <<< "$text"
    if [[ "$first_line" == *"NAME"* && "$first_line" == *"SERVICE"* && "$first_line" == *"STATUS"* ]]; then
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

        if [[ "$line" == *"NAME"* && "$line" == *"SERVICE"* && "$line" == *"STATUS"* ]]; then
            past_header=1
            continue
        fi
        [[ $past_header -eq 0 ]] && continue

        read -ra _arr <<< "$line"
        [[ ${#_arr[@]} -lt 4 ]] && continue

        row_num=$((row_num + 1))
        local prefix="service${row_num}"

        local svc_name="${_arr[0]}"
        local image="${_arr[1]}"

        # Find status keywords
        local status_parts=""
        local ports=""
        local i
        for ((i=2; i<${#_arr[@]}; i++)); do
            case "${_arr[$i]}" in
                Up|Exited|Created|Paused|Running|Restarting|running|exited|created)
                    if [[ -z "$status_parts" ]]; then
                        status_parts="${_arr[$i]}"
                    else
                        status_parts="${status_parts}_${_arr[$i]}"
                    fi
                    ;;
                *"->"*|*":"*)
                    if [[ "${_arr[$i]}" == *"->"* ]]; then
                        if [[ -z "$ports" ]]; then
                            ports="${_arr[$i]}"
                        else
                            ports="${ports},${_arr[$i]}"
                        fi
                    fi
                    ;;
            esac
        done

        result+="${prefix}.name ${svc_name}"$'\n'
        result+="${prefix}.image ${image}"$'\n'
        [[ -n "$status_parts" ]] && result+="${prefix}.status ${status_parts}"$'\n'
        [[ -n "$ports" ]] && result+="${prefix}.ports ${ports}"$'\n'
    done <<< "$text"

    echo "$result"
}
