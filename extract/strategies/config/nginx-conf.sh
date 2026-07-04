#!/bin/bash
## Name: nginx-conf
## Description: Extract directives from Nginx configuration files
## Version: 1.0
## Priority: 18
## Sample: samples/nginx-conf/basic.conf

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=85
    # Reject JSON
    _is_json "$1" && return 1

    # Reject HCL (Terraform) — contains resource/variable/provider keywords
    local has_resource=0
    while IFS= read -r line; do
        local trimmed="$line"
        while [[ "$trimmed" == " "* ]]; do trimmed="${trimmed# }"; done
        case "$trimmed" in
            "resource "*|"variable "*|"provider "*) has_resource=1; break ;;
        esac
    done <<< "$text"
    if [[ $has_resource -eq 1 ]]; then
        return 1
    fi

    local marker_count=0
    local has_braces=0
    while IFS= read -r line; do
        local trimmed="$line"
        while [[ "$trimmed" == " "* ]]; do trimmed="${trimmed# }"; done
        while [[ "$trimmed" == *" " ]]; do trimmed="${trimmed% }"; done
        case "$trimmed" in
            "server {"*|"server{") marker_count=$((marker_count + 1)) ;;
            "location "*) marker_count=$((marker_count + 1)) ;;
            "listen "*) marker_count=$((marker_count + 1)) ;;
            "server_name "*) marker_count=$((marker_count + 1)) ;;
            "proxy_pass "*) marker_count=$((marker_count + 1)) ;;
            "root "*) marker_count=$((marker_count + 1)) ;;
            "index "*) marker_count=$((marker_count + 1)) ;;
        esac
        case "$line" in
            *"{"*|*"}"*) has_braces=1 ;;
        esac
    done <<< "$text"

    if [[ $marker_count -ge 2 && $has_braces -eq 1 ]]; then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""

    local server_num=0
    local location_num=0
    local in_server=0
    local in_location=0
    local brace_depth=0
    local server_brace_depth=0
    local location_brace_depth=0

    while IFS= read -r line; do
        # Trim leading whitespace
        local trimmed="$line"
        while [[ "$trimmed" == " "* ]]; do trimmed="${trimmed# }"; done
        while [[ "$trimmed" == $'\t'* ]]; do trimmed="${trimmed#$'\t'}"; done

        [[ -z "$trimmed" ]] && continue
        # Skip comments
        case "$trimmed" in
            "#"*) continue ;;
        esac

        # Track brace depth
        local i
        for ((i=0; i<${#trimmed}; i++)); do
            local c="${trimmed:$i:1}"
            case "$c" in
                "{") brace_depth=$((brace_depth + 1)) ;;
                "}") brace_depth=$((brace_depth - 1))
                    if [[ $in_location -eq 1 && $brace_depth -lt $location_brace_depth ]]; then
                        in_location=0
                    fi
                    if [[ $in_server -eq 1 && $brace_depth -lt $server_brace_depth ]]; then
                        in_server=0
                        in_location=0
                    fi
                    ;;
            esac
        done

        # Detect server block
        case "$trimmed" in
            "server {"*)
                server_num=$((server_num + 1))
                location_num=0
                in_server=1
                server_brace_depth=$brace_depth
                continue
                ;;
        esac

        # Detect location block
        if [[ $in_server -eq 1 ]]; then
            case "$trimmed" in
                "location "*)
                    location_num=$((location_num + 1))
                    in_location=1
                    location_brace_depth=$brace_depth
                    # Extract location path
                    local loc_rest="${trimmed#location }"
                    # Remove trailing { and whitespace
                    loc_rest="${loc_rest%\{*}"
                    while [[ "$loc_rest" == *" " ]]; do loc_rest="${loc_rest% }"; done
                    loc_rest="${loc_rest// /_}"
                    result+="server${server_num}.location${location_num}.path ${loc_rest}"$'\n'
                    continue
                    ;;
            esac
        fi

        # Parse directive: value; pairs
        # Strip trailing semicolon
        local directive_line="$trimmed"
        directive_line="${directive_line%;}"

        # Split into directive and value
        local directive="${directive_line%% *}"
        local value="${directive_line#* }"
        if [[ "$directive" == "$value" ]]; then
            # No value
            continue
        fi

        # Replace spaces in value with underscores
        value="${value// /_}"

        # Skip block-only keywords
        case "$directive" in
            "events"|"http"|"server"|"location"|"}") continue ;;
        esac

        if [[ $in_location -eq 1 ]]; then
            result+="server${server_num}.location${location_num}.${directive} ${value}"$'\n'
        elif [[ $in_server -eq 1 ]]; then
            result+="server${server_num}.${directive} ${value}"$'\n'
        else
            result+="${directive} ${value}"$'\n'
        fi

    done <<< "$text"

    echo "$result"
}
