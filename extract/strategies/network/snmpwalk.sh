#!/bin/bash
## Name: snmpwalk
## Description: Extract OID/type/value records from snmpwalk output
## Version: 1.0
## Priority: 20
## Technique: yes
## Sample: samples/snmpwalk/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=86
    _is_json "$text" && return 1
    # snmpwalk lines: "MIB::name.N = TYPE: value" with at least one non-.0
    # instance index (a walk spans a subtree).
    local snmp=0 nonzero=0
    while IFS= read -r _line; do
        [[ -z "$_line" ]] && continue
        if [[ "$_line" =~ ^[^[:space:]]+::[^[:space:]=]+[[:space:]]+=[[:space:]]+[^:]+:[[:space:]] ]]; then
            snmp=$((snmp + 1))
            local oid="${_line%% = *}"
            [[ "$oid" =~ \.0$ ]] || nonzero=$((nonzero + 1))
        fi
    done <<< "$text"
    [[ $snmp -ge 1 && $nonzero -ge 1 ]] && return 0
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
