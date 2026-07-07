#!/bin/bash
## Name: bq-ls
## Description: Extract datasets/tables from `bq ls` (BigQuery CLI) output
## Version: 1.0
## Priority: 20
## Technique: yes
## Sample: samples/bq-ls/basic.txt

# `bq ls` prints a "tableId  Type" header, a dashed rule, then one entry per
# line as "<id>  <type>" (columns separated by runs of spaces). Each data row is
# one record with tableid/type fields.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    # The bq column header plus its dashed separator rule.
    if [[ "$text" == *"tableId"* && "$text" == *"---"* ]]; then
        _STRATEGY_CONFIDENCE=86
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line s id type
    while IFS= read -r line; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        s="${line#"${line%%[![:space:]]*}"}"
        s="${s%"${s##*[![:space:]]}"}"
        # Skip the header row and the dashed separator rule.
        [[ "$s" == tableId* ]] && continue
        [[ "$s" == -* ]] && continue
        id="${s%%[[:space:]]*}"
        type="${s#"$id"}"
        type="${type#"${type%%[![:space:]]*}"}"
        type="${type%"${type##*[![:space:]]}"}"
        [[ -z "$id" ]] && continue
        entry=$((entry + 1))
        result+="entry${entry}.tableid ${id// /_}"$'\n'
        result+="entry${entry}.type ${type// /_}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
