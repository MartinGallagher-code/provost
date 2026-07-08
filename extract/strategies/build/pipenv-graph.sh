#!/bin/bash
## Name: pipenv-graph
## Description: Extract dependencies from `pipenv graph` dependency-tree output
## Version: 1.0
## Priority: 20
## Technique: yes
## Sample: samples/pipenv-graph/basic.txt

# `pipenv graph` prints top-level packages ("Django==4.2.7") followed by
# indented requirement lines ("  - asgiref [required: ..., installed: ...]").
# Every non-blank line is one dependency; the cleaned value is the line with any
# leading whitespace and "- " tree marker stripped (single column).

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    # pip-style requirement annotations are the signature.
    if [[ "$text" == *"[required:"* && "$text" == *"installed:"* ]]; then
        _STRATEGY_CONFIDENCE=86
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line s
    while IFS= read -r line; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        s="$line"
        s="${s#"${s%%[![:space:]]*}"}"
        s="${s#- }"
        s="${s#"${s%%[![:space:]]*}"}"
        s="${s%"${s##*[![:space:]]}"}"
        [[ -z "$s" ]] && continue
        entry=$((entry + 1))
        result+="entry${entry}.c1 ${s}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
