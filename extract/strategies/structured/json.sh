#!/bin/bash
## Name: json
## Description: Extract key/value pairs from JSON input, flattening nested objects with dot notation
## Version: 1.0
## Priority: 10
## Sample: samples/json/benchmark.json

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=95
    _STRATEGY_CONFIDENCE_REASON="input starts with { or ["
    # Apply if input looks like JSON (starts with { or [, possibly with leading whitespace)
    local trimmed="$text"
    # Strip a UTF-8 BOM (EF BB BF) if present — common in JSON exported from
    # Windows tools (PowerShell's Out-File, Notepad's "UTF-8" encoding). Left
    # in place it hides the leading '{'/'[' from the checks below and the
    # file falls through to 'unsorted' instead of being recognized as JSON.
    local bom; bom=$(printf '\xef\xbb\xbf')
    trimmed="${trimmed#"$bom"}"
    while [[ "$trimmed" == " "* || "$trimmed" == $'\t'* || "$trimmed" == $'\n'* ]]; do
        trimmed="${trimmed#?}"
    done
    # Trailing whitespace/newlines too, so we can check the closing bracket.
    while [[ "$trimmed" == *" " || "$trimmed" == *$'\t' || "$trimmed" == *$'\n' ]]; do
        trimmed="${trimmed%?}"
    done
    # Must open AND close like JSON. This rejects bracket-prefixed logs such as
    # dmesg ("[    0.000000] Linux version …") which open with '[' but do not
    # close with ']'/'}'.
    [[ "$trimmed" == "{"* || "$trimmed" == "["* ]] || return 1
    [[ "$trimmed" == *"}" || "$trimmed" == *"]" ]] || return 1
    return 0
}

strategy_extract () {
    local text="$1"

    # Try jq first (most reliable), fall back to awk-based parser. Pipe the flat
    # key/value pairs through _list_explode so a single indexed list-of-records
    # (avro `fields`, amtool `Peers`) becomes one tidy row per element instead of
    # a wide `fields.0.* fields.1.*` row whose duplicate leaf names collide.
    if command -v jq &>/dev/null; then
        _strat_json_extract_jq "$text" | _list_explode
    else
        _strat_json_extract_fallback "$text" | _list_explode
    fi
}

_strat_json_extract_jq () {
    local text="$1"

    # Use jq to flatten and extract all leaf key/value pairs
    # Outputs "path value" for each leaf node
    # Uses path(.. | select()) for jq 1.8+ compatibility
    echo "$text" | jq -r '
        path(.. | select(type == "number" or type == "string" or type == "boolean" or type == "null")) as $p |
        ($p | map(if type == "number" then tostring else . end) | join(".")) + " " +
        (getpath($p) | tostring)
    ' 2>/dev/null || true
}

_strat_json_extract_fallback () {
    local text="$1"

    # Simple fallback: extract "key": value patterns with bash
    # Limitations: processes line-by-line, so multi-line JSON strings are broken.
    # This won't handle deeply nested structures as well as jq
    while IFS= read -r _line; do
        [[ -z "$_line" ]] && continue
        # Match patterns like "key": "value" or "key": 123 or "key": true
        local remaining="$_line"
        while [[ "$remaining" == *'"'*':'* ]]; do
            # Find the next "key":
            local after_quote="${remaining#*\"}"
            local key="${after_quote%%\"*}"
            [[ -z "$key" ]] && break
            # Move past the key and colon
            remaining="${after_quote#*\"}"
            remaining="${remaining#*:}"
            # Trim spaces
            while [[ "$remaining" == " "* ]]; do remaining="${remaining# }"; done
            # Extract value
            local value=""
            if [[ "$remaining" == '"'* ]]; then
                # String value
                remaining="${remaining#\"}"
                value="${remaining%%\"*}"
                remaining="${remaining#*\"}"
            elif [[ "$remaining" =~ ^([0-9.eE+-]+) ]]; then
                value="${BASH_REMATCH[1]}"
                remaining="${remaining#"$value"}"
            elif [[ "$remaining" == "true"* ]]; then
                value="true"
                remaining="${remaining#true}"
            elif [[ "$remaining" == "false"* ]]; then
                value="false"
                remaining="${remaining#false}"
            elif [[ "$remaining" == "null"* ]]; then
                value="null"
                remaining="${remaining#null}"
            else
                break
            fi
            [[ -n "$key" && -n "$value" ]] && echo "$key $value"
        done
    done <<< "$text"
}
