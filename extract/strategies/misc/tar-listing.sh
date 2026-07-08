#!/bin/bash
## Name: tar-listing
## Description: Extract fields from tar archive listing output
## Version: 1.0
## Priority: 22
## Sample: samples/tar-listing/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=85

    # Reject JSON
    _is_json "$text" && return 1

    # tar `-v` output: permissions then an `owner/group` token (containing a
    # slash), size, date, path. Requiring the owner/group slash keeps this
    # strategy from grabbing `ls -l` output — whose second field is a numeric
    # link count — which the dedicated `ls-l` strategy handles instead.
    # Need at least 3 lines matching.
    local _match_count=0
    local _perm_re='^[dlrwxs@t-]{10}[[:space:]]+[^[:space:]/]+/[^[:space:]]+[[:space:]]'
    while IFS= read -r _line; do
        if [[ "$_line" =~ $_perm_re ]]; then
            _match_count=$((_match_count + 1))
        fi
    done <<< "$text"

    [[ $_match_count -ge 3 ]] && return 0
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local _entry_num=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        local _perm_re='^[dlrwxs@t-]{10}'
        if [[ "$line" =~ $_perm_re ]]; then
            _entry_num=$((_entry_num + 1))

            # Parse the line: permissions owner/group size date time path
            local _rest="$line"

            # Extract permissions (first 10 chars)
            local _perms="${_rest:0:10}"
            _rest="${_rest:10}"

            # Strip leading whitespace
            while [[ "$_rest" == " "* ]]; do _rest="${_rest# }"; done

            # Extract owner/group (next non-space token)
            local _owner="${_rest%% *}"
            _rest="${_rest#"$_owner"}"
            while [[ "$_rest" == " "* ]]; do _rest="${_rest# }"; done

            # Extract size (next non-space token)
            local _size="${_rest%% *}"
            _rest="${_rest#"$_size"}"
            while [[ "$_rest" == " "* ]]; do _rest="${_rest# }"; done

            # Extract date (YYYY-MM-DD)
            local _date="${_rest%% *}"
            _rest="${_rest#"$_date"}"
            while [[ "$_rest" == " "* ]]; do _rest="${_rest# }"; done

            # Extract time (HH:MM)
            local _time="${_rest%% *}"
            _rest="${_rest#"$_time"}"
            while [[ "$_rest" == " "* ]]; do _rest="${_rest# }"; done

            # Remainder is the path
            local _path="$_rest"

            result+="entry${_entry_num}.permissions ${_perms}"$'\n'
            result+="entry${_entry_num}.owner ${_owner}"$'\n'
            result+="entry${_entry_num}.size ${_size}"$'\n'
            result+="entry${_entry_num}.date ${_date}"$'\n'
            result+="entry${_entry_num}.path ${_path}"$'\n'
        fi
    done <<< "$text"

    if [[ $_entry_num -gt 0 ]]; then
        result+="total_entries ${_entry_num}"$'\n'
    fi

    echo "$result"
}
