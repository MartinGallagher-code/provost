#!/bin/bash
## Name: k8s-events
## Description: Extract event information from kubectl get events output
## Version: 1.0
## Priority: 15
## Sample: samples/k8s-events/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90
    # Reject JSON
    _is_json "$1" && return 1
    # Look for a header line starting with LAST SEEN or TYPE followed by
    # distinctive kubectl events columns: REASON, OBJECT, MESSAGE
    local _nl=$'\n'
    local found_header=0
    while IFS= read -r _line; do
        [[ -z "$_line" ]] && continue
        # Check if line starts with LAST SEEN or LAST_SEEN or TYPE
        if [[ "$_line" == "LAST SEEN"* || "$_line" == "LAST_SEEN"* || "$_line" == "TYPE"* ]]; then
            # Must also contain REASON and OBJECT or MESSAGE
            if [[ "$_line" == *"REASON"* && ( "$_line" == *"OBJECT"* || "$_line" == *"MESSAGE"* ) ]]; then
                found_header=1
                break
            fi
        fi
    done <<< "$text"
    [[ $found_header -eq 1 ]] && return 0
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""

    # Get the header line to find column positions
    local header_line=""
    while IFS= read -r _line; do
        [[ -z "$_line" ]] && continue
        header_line="$_line"
        break
    done <<< "$text"

    # Parse column positions from header
    local col_names=()
    local col_starts=()
    _strat_k8s_events_parse_columns "$header_line"

    # Process each data row
    local row_num=0
    local line_num=0
    while IFS= read -r line; do
        line_num=$((line_num + 1))
        [[ $line_num -eq 1 ]] && continue  # skip header
        [[ -z "$line" ]] && continue

        row_num=$((row_num + 1))
        local prefix="event${row_num}"

        local i
        for ((i=0; i<${#col_names[@]}; i++)); do
            local col_name="${col_names[$i]}"
            local start="${col_starts[$i]}"
            local end=""
            if [[ $((i + 1)) -lt ${#col_names[@]} ]]; then
                end="${col_starts[$((i + 1))]}"
            fi

            local val
            if [[ -n "$end" ]]; then
                local s0=$((start - 1))
                local len=$((end - start))
                val="${line:$s0:$len}"
            else
                local s0=$((start - 1))
                val="${line:$s0}"
            fi

            # Trim leading/trailing whitespace
            while [[ "$val" == " "* ]]; do val="${val# }"; done
            while [[ "$val" == *" " ]]; do val="${val% }"; done
            [[ -z "$val" ]] && continue

            # Normalize column name to lowercase with underscores
            col_name=$(_strat_k8s_events_normalize_col "$col_name")
            result+="${prefix}.${col_name} ${val}"$'\n'
        done
    done <<< "$text"

    echo "$result"
}

_strat_k8s_events_parse_columns () {
    local header="$1"
    col_names=()
    col_starts=()

    local remaining="$header"
    local offset=0

    while [[ -n "$remaining" ]]; do
        # Skip leading spaces
        local stripped="$remaining"
        while [[ "$stripped" == " "* ]]; do stripped="${stripped# }"; done
        local spaces_skipped=$(( ${#remaining} - ${#stripped} ))
        offset=$((offset + spaces_skipped))
        remaining="$stripped"

        [[ -z "$remaining" ]] && break

        # Try to match known two-word headers
        local matched=0
        if [[ "$remaining" == "LAST SEEN"* ]]; then
            col_names+=("LAST_SEEN")
            col_starts+=($((offset + 1)))
            local hdr="LAST SEEN"
            remaining="${remaining#$hdr}"
            offset=$((offset + ${#hdr}))
            matched=1
        fi

        if [[ $matched -eq 0 ]]; then
            # Single-word header
            read -ra _arr <<< "$remaining"
            local word="${_arr[0]}"
            [[ -z "$word" ]] && break
            col_names+=("$word")
            col_starts+=($((offset + 1)))
            remaining="${remaining#"$word"}"
            offset=$((offset + ${#word}))
        fi
    done
}

_strat_k8s_events_normalize_col () {
    local col="$1"
    col="${col// /_}"
    echo "$col" | tr '[:upper:]' '[:lower:]'
}
