#!/bin/bash
## Name: apache-access
## Description: Extract fields from Apache/nginx combined access log format
## Version: 1.0
## Priority: 10
## Sample: samples/apache-access/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=95
    # Match IP address followed by " - " and then a bracket-enclosed date
    # Use variable for regex: (^|newline) to match any line start
    local _nl=$'\n'
    local _re="(^|${_nl})[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3} .* \["
    [[ "$text" =~ $_re ]]
}

strategy_extract () {
    local text="$1"
    local result=""
    local line_num=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        # Only process lines matching access log format
        if ! [[ "$line" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\  ]]; then
            continue
        fi

        line_num=$((line_num + 1))
        local prefix="line${line_num}"

        # Parse the combined log format using bash builtins
        # Format: IP ident user [date] "method path proto" status size "referrer" "user_agent"
        read -ra _arr <<< "$line"
        local ip="${_arr[0]}"
        local user="${_arr[2]}"

        # Extract date between brackets
        local date=""
        if [[ "$line" =~ \[([^\]]*)\] ]]; then
            date="${BASH_REMATCH[1]}"
        fi

        # Extract the first quoted string (request)
        local method="" path=""
        if [[ "$line" =~ \"([A-Z]+)\ ([^\ ]*)\ ([^\"]*)\" ]]; then
            method="${BASH_REMATCH[1]}"
            path="${BASH_REMATCH[2]}"
        fi

        # Extract status and size after the request quote
        local _after_request="${line#*\" }"
        read -ra _arr2 <<< "$_after_request"
        local status="${_arr2[0]}"
        local size="${_arr2[1]}"

        # Extract referrer (second quoted string) and user_agent (third quoted string)
        local referrer="" user_agent=""
        local _remaining="$line"
        local _quote_count=0
        local _current_quoted=""
        local _in_quotes=0
        local _quoted_fields=""
        local _i
        for ((_i=0; _i<${#_remaining}; _i++)); do
            local _c="${_remaining:$_i:1}"
            if [[ "$_c" == '"' ]]; then
                if [[ $_in_quotes -eq 0 ]]; then
                    _in_quotes=1
                    _current_quoted=""
                else
                    _in_quotes=0
                    _quote_count=$((_quote_count + 1))
                    if [[ $_quote_count -eq 2 ]]; then
                        referrer="${_current_quoted}"
                    elif [[ $_quote_count -eq 3 ]]; then
                        user_agent="${_current_quoted}"
                    fi
                fi
            elif [[ $_in_quotes -eq 1 ]]; then
                _current_quoted+="$_c"
            fi
        done

        result+="${prefix}.ip ${ip}"$'\n'
        result+="${prefix}.user ${user}"$'\n'
        result+="${prefix}.date ${date}"$'\n'
        result+="${prefix}.method ${method}"$'\n'
        result+="${prefix}.path ${path}"$'\n'
        result+="${prefix}.status ${status}"$'\n'
        result+="${prefix}.size ${size}"$'\n'
        result+="${prefix}.referrer ${referrer}"$'\n'
        result+="${prefix}.user_agent ${user_agent}"$'\n'

    done <<< "$text"

    echo "$result"
}
