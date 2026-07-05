#!/bin/bash
## Name: kubectl
## Description: Extract resource information from kubectl get output
## Version: 1.0
## Priority: 12
## Sample: samples/kubectl/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90
    # First non-empty line starts with NAME and contains STATUS or READY
    local first_line=""
    while IFS= read -r _line; do
        [[ -z "$_line" ]] && continue
        first_line="$_line"
        break
    done <<< "$text"
    if [[ "$first_line" == "NAME"* ]]; then
        if [[ "$first_line" == *"STATUS"* || "$first_line" == *"READY"* ]]; then
            return 0
        fi
    fi
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
    _strat_kubectl_parse_columns "$header_line"

    # Process each data row
    local row_num=0
    local line_num=0
    while IFS= read -r line; do
        line_num=$((line_num + 1))
        [[ $line_num -eq 1 ]] && continue  # skip header
        [[ -z "$line" ]] && continue

        row_num=$((row_num + 1))
        local prefix="pod${row_num}"

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
                # Extract substring using bash (1-indexed start, convert to 0-indexed)
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
            # Replace spaces with underscores
            val="${val// /_}"
            [[ -z "$val" ]] && continue

            # Normalize column name to lowercase
            col_name=$(_strat_kubectl_normalize_col "$col_name")
            result+="${prefix}.${col_name} ${val}"$'\n'
        done
    done <<< "$text"

    echo "$result"
}

_strat_kubectl_parse_columns () {
    local header="$1"
    col_names=()
    col_starts=()

    # kubectl headers are single words separated by whitespace
    # Find the start position of each header word
    local offset=0
    local remaining="$header"

    while [[ -n "$remaining" ]]; do
        # Skip leading spaces
        local stripped="$remaining"
        while [[ "$stripped" == " "* ]]; do stripped="${stripped# }"; done
        local spaces_skipped=$(( ${#remaining} - ${#stripped} ))
        offset=$((offset + spaces_skipped))
        remaining="$stripped"

        [[ -z "$remaining" ]] && break

        # Get next word
        read -ra _arr <<< "$remaining"
        local word="${_arr[0]}"
        [[ -z "$word" ]] && break

        col_names+=("$word")
        col_starts+=($((offset + 1)))

        remaining="${remaining#"$word"}"
        offset=$((offset + ${#word}))
    done
}

_strat_kubectl_normalize_col () {
    local col="$1"
    # Convert to lowercase using tr
    echo "$col" | tr '[:upper:]' '[:lower:]'
}
