#!/bin/bash
## Name: curl-headers
## Description: Extract fields from curl -v verbose output
## Version: 1.0
## Priority: 22
## Sample: samples/curl-headers/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=80
    # Lines starting with "> " (request) and "< " (response) prefixes,
    # or "* Connected to"
    local has_request=0 has_response=0 has_connected=0
    while IFS= read -r _line; do
        [[ "$_line" == "> "* ]] && has_request=$((has_request + 1))
        [[ "$_line" == "< "* ]] && has_response=$((has_response + 1))
        [[ "$_line" == "* Connected to"* ]] && has_connected=$((has_connected + 1))
    done <<< "$text"

    # Must have at least request or response headers
    if [[ $has_request -gt 0 ]] && [[ $has_response -gt 0 ]]; then
        return 0
    fi
    if [[ $has_connected -gt 0 ]] && [[ $has_response -gt 0 ]]; then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""

    while IFS= read -r line; do
        # Request line: "> GET /index.html HTTP/2"
        if [[ "$line" =~ ^\>\ (GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS)\  ]]; then
            local _stripped="${line#> }"
            read -ra _arr <<< "$_stripped"
            local method="${_arr[0]}"
            local path="${_arr[1]}"
            result+="request.method ${method}"$'\n'
            result+="request.path ${path}"$'\n'
            continue
        fi

        # Request headers: "> Header: value"
        if [[ "$line" =~ ^\>\ [A-Za-z][-A-Za-z0-9]*: ]]; then
            local _stripped="${line#> }"
            local key="${_stripped%%:*}"
            local value="${_stripped#*: }"
            if [[ "$value" == "$_stripped" ]]; then
                value="${_stripped#*:}"
            fi
            key="${key// /_}"
            [[ -n "$key" ]] && [[ -n "$value" ]] && result+="request.${key} ${value}"$'\n'
            continue
        fi

        # Response status: "< HTTP/2 200" or "< HTTP/1.1 200 OK"
        if [[ "$line" == "< HTTP/"* ]]; then
            local _stripped="${line#< }"
            read -ra _arr <<< "$_stripped"
            local status="${_arr[1]}"
            result+="response.status ${status}"$'\n'
            continue
        fi

        # Response headers: "< header: value"
        if [[ "$line" =~ ^\<\ [A-Za-z][-A-Za-z0-9]*: ]]; then
            local _stripped="${line#< }"
            local key="${_stripped%%:*}"
            local value="${_stripped#*: }"
            if [[ "$value" == "$_stripped" ]]; then
                value="${_stripped#*:}"
            fi
            key="${key// /_}"
            [[ -n "$key" ]] && [[ -n "$value" ]] && result+="response.${key} ${value}"$'\n'
            continue
        fi

    done <<< "$text"

    echo "$result"
}
