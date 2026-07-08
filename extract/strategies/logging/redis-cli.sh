#!/bin/bash
## Name: redis-cli
## Description: Extract key-value data from Redis CLI output (INFO, array responses, type annotations)
## Version: 1.0
## Priority: 22
## Sample: samples/redis-cli/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=80
    # Reject JSON
    _is_json "$1" && return 1

    # Look for Redis-specific patterns:
    # 1. Lines with numbered results like "1)" "2)" (array responses)
    # 2. "(integer)" type annotations
    # 3. "(nil)" responses
    # 4. Lines starting with OK or QUEUED or (error)
    # 5. Redis INFO output: "# Section" headers + "key:value" lines with redis-specific keys
    # 6. Redis prompt "127.0.0.1:6379>"

    local found_prompt=0
    local found_section_header=0
    local found_redis_key=0
    local _re_array='^[0-9]+\) '

    while IFS= read -r _line; do
        [[ -z "$_line" ]] && continue

        # Check for Redis prompt
        if [[ "$_line" == *":6379>"* || "$_line" == *":6380>"* || "$_line" == *"redis>"* ]]; then
            found_prompt=1
        fi

        # Check for array result
        if [[ "$_line" =~ $_re_array ]]; then
            return 0
        fi

        # Check for type annotations
        if [[ "$_line" == "(integer)"* || "$_line" == "(nil)"* || "$_line" == "(error)"* ]]; then
            return 0
        fi

        # Check for OK or QUEUED responses
        if [[ "$_line" == "OK" || "$_line" == "QUEUED" ]]; then
            return 0
        fi

        # Check for INFO section headers (# Server, # Clients, etc.)
        if [[ "$_line" == "# "* ]]; then
            found_section_header=1
        fi

        # Check for redis-specific key:value pairs
        if [[ "$_line" == "redis_version:"* || "$_line" == "redis_mode:"* || "$_line" == "tcp_port:"* || "$_line" == "uptime_in_"* || "$_line" == "connected_clients:"* || "$_line" == "used_memory"* || "$_line" == "maxmemory"* ]]; then
            found_redis_key=1
        fi
    done <<< "$text"

    # Accept if we found section headers + redis-specific keys
    if [[ $found_section_header -eq 1 && $found_redis_key -eq 1 ]]; then
        return 0
    fi

    # Accept if prompt found with section headers
    if [[ $found_prompt -eq 1 && $found_section_header -eq 1 ]]; then
        return 0
    fi

    return 1
}

strategy_extract () {
    local text="$1"
    local result=""

    # Parse Redis INFO-style output: "key:value" lines grouped by "# Section" headers
    local current_section=""
    local item_num=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Skip prompt lines
        if [[ "$line" == *":6379>"* || "$line" == *":6380>"* || "$line" == *"redis>"* ]]; then
            # Extract the command part after the prompt if present
            local after_prompt="${line#*> }"
            if [[ "$after_prompt" != "$line" && -n "$after_prompt" ]]; then
                # This is a command line, skip it
                :
            fi
            continue
        fi

        # Section headers
        if [[ "$line" == "# "* ]]; then
            current_section="${line#\# }"
            # Normalize section name: lowercase, spaces to underscores
            current_section=$(echo "$current_section" | tr '[:upper:]' '[:lower:]')
            current_section="${current_section// /_}"
            continue
        fi

        # Key:value pairs (INFO output)
        if [[ "$line" == *":"* ]]; then
            local key="${line%%:*}"
            local val="${line#*:}"
            # Skip lines that don't look like redis info keys
            local _re_key='^[a-zA-Z_][a-zA-Z0-9_]*$'
            if [[ "$key" =~ $_re_key ]]; then
                # Trim whitespace from value
                while [[ "$val" == " "* ]]; do val="${val# }"; done
                while [[ "$val" == *" " ]]; do val="${val% }"; done
                [[ -z "$val" ]] && continue
                result+="${key} ${val}"$'\n'
                continue
            fi
        fi

        # Array results: "N) value"
        local _re_arr='^([0-9]+)\) '
        if [[ "$line" =~ $_re_arr ]]; then
            item_num=$((item_num + 1))
            local val="${line#*) }"
            # Trim quotes
            if [[ "$val" == '"'* && "$val" == *'"' ]]; then
                val="${val#\"}"
                val="${val%\"}"
            fi
            result+="item${item_num} ${val}"$'\n'
            continue
        fi

        # Type annotations: "(integer) N"
        if [[ "$line" == "(integer) "* ]]; then
            local val="${line#*) }"
            result+="result ${val}"$'\n'
            continue
        fi

    done <<< "$text"

    echo "$result"
}
