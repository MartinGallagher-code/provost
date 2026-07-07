#!/bin/bash
## Name: lscpu-extended
## Description: Extract per-CPU rows from `lscpu --extended`
## Version: 1.0
## Priority: 9
## Technique: yes
## Sample: samples/lscpu-extended/basic.txt

# `lscpu --extended` prints an aligned table with header
# `CPU NODE SOCKET CORE L1d:L1i:L2:L3 ONLINE MAXMHZ MINMHZ` then one row per
# logical CPU. Emit ONE record per CPU row.

_lscpux_san () { local v="$1"; v="${v//$'\t'/_}"; v="${v// /_}"; printf '%s' "$v"; }

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    # The aligned extended header is the narrow signature.
    [[ "$text" == *"CPU"*"NODE"*"SOCKET"*"CORE"* ]] || return 1
    [[ "$text" == *"ONLINE"* ]] || return 1
    _STRATEGY_CONFIDENCE=86
    return 0
}

strategy_extract () {
    local text="$1" result="" entry=0 line
    local -a t
    while IFS= read -r line; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        case "$line" in
            *CPU*NODE*SOCKET*) continue ;;   # header row
        esac
        read -ra t <<< "$line"
        [[ ${#t[@]} -ge 8 ]] || continue
        [[ "${t[0]}" =~ ^[0-9]+$ ]] || continue   # CPU index is numeric
        entry=$((entry + 1))
        result+="entry${entry}.cpu ${t[0]}"$'\n'
        result+="entry${entry}.node ${t[1]}"$'\n'
        result+="entry${entry}.socket ${t[2]}"$'\n'
        result+="entry${entry}.core ${t[3]}"$'\n'
        result+="entry${entry}.caches ${t[4]}"$'\n'
        result+="entry${entry}.online ${t[5]}"$'\n'
        result+="entry${entry}.maxmhz ${t[6]}"$'\n'
        result+="entry${entry}.minmhz ${t[7]}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    printf '%s' "$result"
}
