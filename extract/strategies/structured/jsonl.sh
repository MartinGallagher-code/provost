#!/bin/bash
## Name: jsonl
## Description: Extract key/value pairs from JSON Lines (one JSON object per line)
## Version: 1.1
## Priority: 9
## Sample: samples/jsonl/basic.jsonl
##
## Priority 9 places JSON Lines ahead of the single-document `json` strategy
## (p10): a `.jsonl` file is NOT one JSON document, and `json` would flatten its
## objects into a wide row with duplicate columns. `jsonl`'s detector requires
## 2+ lines that are each a complete `{...}` object, so single-line or
## pretty-printed JSON (whose lines are not standalone objects) is left to json.
## Each line is emitted as a `line<N>.<field>` group so the capture tidy melt
## renders one row per record.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90

    # Strip a UTF-8 BOM (EF BB BF) if present — common in JSON exported from
    # Windows tools — so it doesn't hide the first line's leading '{'.
    local bom; bom=$(printf '\xef\xbb\xbf')
    text="${text#"$bom"}"

    # Must have 2+ lines, each looking like a JSON object
    local line_count=0
    while IFS= read -r _line; do
        [[ -n "$_line" ]] && line_count=$((line_count + 1))
    done <<< "$text"
    [[ $line_count -lt 2 ]] && return 1

    # Check first 3 non-empty lines are JSON objects
    local json_lines=0
    local checked=0
    while IFS= read -r _line; do
        [[ -z "$_line" ]] && continue
        checked=$((checked + 1))
        local trimmed="$_line"
        while [[ "$trimmed" == " "* || "$trimmed" == $'\t'* ]]; do trimmed="${trimmed#?}"; done
        if [[ "$trimmed" == "{"*"}" ]]; then
            json_lines=$((json_lines + 1))
        fi
        [[ $checked -ge 3 ]] && break
    done <<< "$text"

    [[ $json_lines -ge 2 ]] && return 0
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local line_num=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        line_num=$((line_num + 1))

        # Try jq first, fall back to regex
        if command -v jq &>/dev/null; then
            local fields
            fields=$(echo "$line" | jq -r '
                to_entries[] | "\(.key) \(.value)"
            ' 2>/dev/null)
            if [[ -n "$fields" ]]; then
                while IFS= read -r field_line; do
                    [[ -z "$field_line" ]] && continue
                    read -ra _arr <<< "$field_line"
                    local fname="${_arr[0]}"
                    local fval="${field_line#"$fname" }"
                    result+="line${line_num}.${fname} ${fval}"$'\n'
                done <<< "$fields"
            fi
        else
            # Fallback: simple extraction of "key": value patterns
            local remaining="$line"
            while [[ "$remaining" == *'"'*':'* ]]; do
                local after_quote="${remaining#*\"}"
                local fname="${after_quote%%\"*}"
                [[ -z "$fname" ]] && break
                remaining="${after_quote#*\"}"
                remaining="${remaining#*:}"
                while [[ "$remaining" == " "* ]]; do remaining="${remaining# }"; done
                local fval=""
                if [[ "$remaining" == '"'* ]]; then
                    remaining="${remaining#\"}"
                    fval="${remaining%%\"*}"
                    remaining="${remaining#*\"}"
                elif [[ "$remaining" =~ ^([0-9.eE+-]+) ]]; then
                    fval="${BASH_REMATCH[1]}"
                    remaining="${remaining#"$fval"}"
                elif [[ "$remaining" == "true"* ]]; then
                    fval="true"; remaining="${remaining#true}"
                elif [[ "$remaining" == "false"* ]]; then
                    fval="false"; remaining="${remaining#false}"
                elif [[ "$remaining" == "null"* ]]; then
                    fval="null"; remaining="${remaining#null}"
                else
                    break
                fi
                [[ -n "$fname" && -n "$fval" ]] && result+="line${line_num}.${fname} ${fval}"$'\n'
            done
        fi
    done <<< "$text"

    echo "$result"
}
