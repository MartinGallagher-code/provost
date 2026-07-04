#!/bin/bash
## Name: block-records
## Description: Split input on blank lines into records, extract key:value and key=value fields
## Version: 1.0
## Priority: 40
## Technique: yes
## Sample: samples/blank-line-records/basic.txt

# Merges blank-line-records and repeated-blocks. Detects either:
#   (a) 2+ blank lines separating blocks with key:value/key=value patterns, or
#   (b) 1+ blank line where the same field name appears in multiple blocks.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=60

    # Reject JSON-like input
    _is_json "$1" && return 1

    # Must have at least one blank line separating blocks
    local blank_count=0
    while IFS= read -r _line; do
        [[ -z "$_line" ]] && blank_count=$((blank_count + 1))
    done <<< "$text"
    [[ $blank_count -lt 1 ]] && return 1

    # Must have key: value or key=value patterns
    [[ "$text" =~ (^|$'\n')\ *[A-Za-z][A-Za-z0-9_\ -]*[:=] ]] || return 1

    # Condition (a): 2+ blank lines is sufficient
    if [[ $blank_count -ge 2 ]]; then
        return 0
    fi

    # Condition (b): same field name appears in 2+ blocks (repeated-blocks criterion)
    local _unique_names="" _total=0 _unique=0
    while IFS= read -r _line; do
        if [[ "$_line" =~ ^[\ ]*([A-Za-z][A-Za-z0-9_\ -]*): ]]; then
            local _name="${BASH_REMATCH[1]}"
            while [[ "$_name" == " "* ]]; do _name="${_name# }"; done
            while [[ "$_name" == *" " ]]; do _name="${_name% }"; done
            _total=$((_total + 1))
            case "|${_unique_names}|" in
                *"|${_name}|"*) ;;
                *) _unique=$((_unique + 1)); _unique_names="${_unique_names}|${_name}" ;;
            esac
        fi
    done <<< "$text"
    [[ $_total -gt $_unique && $_unique -ge 1 ]] && return 0

    # Also check for equals-delimited fields (key=value) from repeated-blocks patterns
    _unique_names="" _total=0 _unique=0
    while IFS= read -r _line; do
        if [[ "$_line" =~ ^[\ ]*([A-Za-z][A-Za-z0-9_\ -]*)= ]]; then
            local _name="${BASH_REMATCH[1]}"
            while [[ "$_name" == " "* ]]; do _name="${_name# }"; done
            while [[ "$_name" == *" " ]]; do _name="${_name% }"; done
            _total=$((_total + 1))
            case "|${_unique_names}|" in
                *"|${_name}|"*) ;;
                *) _unique=$((_unique + 1)); _unique_names="${_unique_names}|${_name}" ;;
            esac
        fi
    done <<< "$text"
    [[ $_total -gt $_unique && $_unique -ge 1 ]] && return 0

    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local record_num=0

    _tech_split_blocks "$text"

    local _remaining="$_TECH_BLOCKS"
    while [[ -n "$_remaining" ]]; do
        local _block="${_remaining%%$'\x01'*}"
        [[ "$_remaining" == *$'\x01'* ]] && _remaining="${_remaining#*$'\x01'}" || _remaining=""
        [[ -z "$_block" ]] && continue
        record_num=$((record_num + 1))
        local _prefix="record${record_num}"
        result+="$(_tech_kv_colon "$_block" "$_prefix")"$'\n'
        result+="$(_tech_kv_equals "$_block" "$_prefix")"$'\n'
    done

    echo "$result"
}
