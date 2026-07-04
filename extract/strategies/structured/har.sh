#!/bin/bash
## Name: har
## Description: Extract request/response fields from HTTP Archive (HAR) files
## Version: 1.0
## Priority: 12
## Sample: samples/har/basic.har

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90

    # Must be JSON
    _is_json "$1" || return 1

    # Must contain "log" and "entries" keys
    [[ "$text" == *'"log"'* ]] || return 1
    [[ "$text" == *'"entries"'* ]] || return 1

    return 0
}

strategy_extract () {
    local text="$1"
    local result=""

    if command -v jq &>/dev/null; then
        _strat_har_extract_jq "$text"
    else
        _strat_har_extract_fallback "$text"
    fi
}

_strat_har_extract_jq () {
    local text="$1"
    local result=""

    # Extract log-level fields
    local log_version
    log_version=$(echo "$text" | jq -r '.log.version // empty' 2>/dev/null) || true
    if [[ -n "$log_version" ]]; then
        result+="log.version ${log_version}"$'\n'
    fi

    local creator_name
    creator_name=$(echo "$text" | jq -r '.log.creator.name // empty' 2>/dev/null) || true
    if [[ -n "$creator_name" ]]; then
        local clean="${creator_name// /_}"
        result+="log.creator.name ${clean}"$'\n'
    fi

    local creator_version
    creator_version=$(echo "$text" | jq -r '.log.creator.version // empty' 2>/dev/null) || true
    if [[ -n "$creator_version" ]]; then
        result+="log.creator.version ${creator_version}"$'\n'
    fi

    # Extract per-entry fields
    local entry_count
    entry_count=$(echo "$text" | jq -r '.log.entries | length' 2>/dev/null) || true
    if [[ -n "$entry_count" && "$entry_count" -gt 0 ]] 2>/dev/null; then
        local i=0
        while [[ $i -lt $entry_count ]]; do
            local n=$((i + 1))
            local prefix="entry${n}"

            local method
            method=$(echo "$text" | jq -r ".log.entries[$i].request.method // empty" 2>/dev/null) || true
            if [[ -n "$method" ]]; then
                result+="${prefix}.request.method ${method}"$'\n'
            fi

            local url
            url=$(echo "$text" | jq -r ".log.entries[$i].request.url // empty" 2>/dev/null) || true
            if [[ -n "$url" ]]; then
                local clean_url="${url// /_}"
                result+="${prefix}.request.url ${clean_url}"$'\n'
            fi

            local status
            status=$(echo "$text" | jq -r ".log.entries[$i].response.status // empty" 2>/dev/null) || true
            if [[ -n "$status" ]]; then
                result+="${prefix}.response.status ${status}"$'\n'
            fi

            local status_text
            status_text=$(echo "$text" | jq -r ".log.entries[$i].response.statusText // empty" 2>/dev/null) || true
            if [[ -n "$status_text" ]]; then
                local clean_st="${status_text// /_}"
                result+="${prefix}.response.statusText ${clean_st}"$'\n'
            fi

            local time_val
            time_val=$(echo "$text" | jq -r ".log.entries[$i].time // empty" 2>/dev/null) || true
            if [[ -n "$time_val" ]]; then
                result+="${prefix}.time ${time_val}"$'\n'
            fi

            i=$((i + 1))
        done
    fi

    echo "$result"
}

_strat_har_extract_fallback () {
    local text="$1"
    local result=""

    # Fallback: extract key fields using bash pattern matching
    local remaining="$text"
    while [[ "$remaining" == *'"'*':'* ]]; do
        local after_quote="${remaining#*\"}"
        local key="${after_quote%%\"*}"
        [[ -z "$key" ]] && break
        remaining="${after_quote#*\"}"
        remaining="${remaining#*:}"
        while [[ "$remaining" == " "* ]]; do remaining="${remaining# }"; done
        local value=""
        if [[ "$remaining" == '"'* ]]; then
            remaining="${remaining#\"}"
            value="${remaining%%\"*}"
            remaining="${remaining#*\"}"
        elif [[ "$remaining" =~ ^([0-9.eE+-]+) ]]; then
            value="${BASH_REMATCH[1]}"
            remaining="${remaining#"$value"}"
        elif [[ "$remaining" == "true"* ]]; then
            value="true"; remaining="${remaining#true}"
        elif [[ "$remaining" == "false"* ]]; then
            value="false"; remaining="${remaining#false}"
        elif [[ "$remaining" == "null"* ]]; then
            value="null"; remaining="${remaining#null}"
        else
            break
        fi
        value="${value// /_}"
        if [[ -n "$key" && -n "$value" ]]; then
            result+="${key} ${value}"$'\n'
        fi
    done

    echo "$result"
}
