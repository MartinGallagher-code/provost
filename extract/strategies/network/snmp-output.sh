#!/bin/bash
## Name: snmp-output
## Description: Extract OID/type/value records from snmpget and snmpwalk output
## Version: 1.0
## Priority: 20
## Technique: yes
## Sample: samples/snmp-output/basic.txt

# snmpget and snmpwalk print the same line shape — `MIB::name.N = TYPE: value` —
# and want the same record output (oid/type/value per line). They were previously
# two strategies split only by a detect heuristic (get = scalar `.0` instances,
# walk = a subtree with non-`.0` indices); that distinction changes nothing about
# the output, so a single parser covers both.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    _is_json "$text" && return 1
    local snmp=0 _line
    while IFS= read -r _line; do
        [[ -z "$_line" ]] && continue
        if [[ "$_line" =~ ^[^[:space:]]+::[^[:space:]=]+[[:space:]]+=[[:space:]]+[^:]+:[[:space:]] ]]; then
            snmp=$((snmp + 1))
        fi
    done <<< "$text"
    [[ $snmp -ge 1 ]] && { _STRATEGY_CONFIDENCE=86; return 0; }
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local n=0

    while IFS= read -r line; do
        [[ "$line" == *"::"*" = "*": "* ]] || continue
        local oid="${line%% = *}"
        local rhs="${line#* = }"
        local type="${rhs%%: *}"
        local val="${rhs#*: }"

        n=$((n + 1))
        local p="entry${n}."
        result+="${p}oid ${oid}"$'\n'
        result+="${p}type ${type}"$'\n'
        result+="${p}value ${val}"$'\n'
    done <<< "$text"

    result+="total_entries ${n}"$'\n'
    echo "$result"
}
