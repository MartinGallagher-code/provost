#!/bin/bash
## Name: rustc-cfg
## Description: Extract target cfg flags from `rustc --print cfg` output
## Version: 1.0
## Priority: 20
## Technique: yes
## Sample: samples/rustc-cfg/basic.txt

# `rustc --print cfg` prints one cfg per line, either a bare flag
# ("debug_assertions") or a key/value ('target_arch="x86_64"'). Each non-blank
# line is one record kept verbatim (single column).

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    # Signature cfg keys emitted by rustc.
    if [[ "$text" == *'target_arch="'* && "$text" == *'target_os="'* ]]; then
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
        s="${s%"${s##*[![:space:]]}"}"
        s="${s// /_}"
        [[ -z "$s" ]] && continue
        entry=$((entry + 1))
        result+="entry${entry}.c1 ${s}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
