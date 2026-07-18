#!/bin/bash
## Name: dot-leader-kv
## Description: `label: ......... value` reports where a run of dot leaders separates key from value
## Version: 1.0
## Priority: 15
## Sample: samples/dot-leader-kv/basic.txt

# Reports like artillery / some benchmark summaries align a value to the right
# with a run of dot leaders: `http.codes.200: ............ 120488`. The dots are
# a delimiter, not data. block-records / colons mangle these (the leaders end up
# glued to the value, or the row is split on the dots). This owns the shape:
# key before the colon, value after the dot run, one row per metric.

# A dot-leader line: optional indent, a label, `:`, optional spaces, a run of
# >=3 dots, spaces, then a value. Sets _DL_KEY / _DL_VAL on success.
_dl_match () {
    local line="$1"
    local _re='^[[:space:]]*([^:]+):[[:space:]]*\.\.\.+[[:space:]]*(.+)$'
    [[ "$line" =~ $_re ]] || return 1
    _DL_KEY="${BASH_REMATCH[1]}"
    _DL_VAL="${BASH_REMATCH[2]}"
    # Trim trailing whitespace from the value.
    while [[ "$_DL_VAL" == *" " ]]; do _DL_VAL="${_DL_VAL% }"; done
    # A value that is itself only dots is not a value.
    [[ "$_DL_VAL" =~ ^\.*$ ]] && return 1
    return 0
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    local line hits=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        _dl_match "$line" && hits=$((hits + 1))
        [[ $hits -ge 3 ]] && { _STRATEGY_CONFIDENCE=86; return 0; }
    done <<< "$text"
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line
    while IFS= read -r line || [[ -n "$line" ]]; do
        _dl_match "$line" || continue
        local key="$_DL_KEY"
        # Trim trailing space off the key too.
        while [[ "$key" == *" " ]]; do key="${key% }"; done
        entry=$((entry + 1))
        result+="entry${entry}.key ${key}"$'\n'
        result+="entry${entry}.value ${_DL_VAL}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
