#!/bin/bash
## Name: go-mod-graph
## Description: Extract dependency edges from go mod graph output
## Version: 1.0
## Priority: 25
## Sample: samples/go-mod-graph/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=80
    # Reject JSON
    _is_json "$1" && return 1

    # Go module graph lines: two space-separated module references per line
    # Format: module@version module@version
    # OR: module (without version, for root) module@version
    # Module paths contain dots and slashes (Go import paths)
    local match_count=0
    local _re_mod='^[a-zA-Z][a-zA-Z0-9._/-]+ [a-zA-Z][a-zA-Z0-9._/-]+@v[0-9]'

    while IFS= read -r _line; do
        [[ -z "$_line" ]] && continue
        if [[ "$_line" =~ $_re_mod ]]; then
            match_count=$((match_count + 1))
        fi
        # Early exit
        if [[ $match_count -ge 3 ]]; then
            return 0
        fi
    done <<< "$text"

    [[ $match_count -ge 2 ]] && return 0
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local edge_num=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Split into two tokens: from and to
        read -ra parts <<< "$line"
        [[ ${#parts[@]} -lt 2 ]] && continue

        local from_mod="${parts[0]}"
        local to_mod="${parts[1]}"

        # Validate: to must contain @v (versioned dependency)
        if [[ "$to_mod" != *"@v"* ]]; then
            continue
        fi

        # Replace spaces with underscores in module paths (shouldn't have any, but be safe)
        from_mod="${from_mod// /_}"
        to_mod="${to_mod// /_}"

        edge_num=$((edge_num + 1))
        result+="edge${edge_num}.from ${from_mod}"$'\n'
        result+="edge${edge_num}.to ${to_mod}"$'\n'
    done <<< "$text"

    if [[ $edge_num -gt 0 ]]; then
        result+="total_edges ${edge_num}"$'\n'
    fi

    echo "$result"
}
