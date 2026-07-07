#!/bin/bash
## Name: telegraf-test
## Description: Extract InfluxDB line-protocol points from `telegraf --test`
## Version: 1.0
## Priority: 9
## Technique: yes
## Sample: samples/telegraf-test/basic.txt

# `telegraf --test` prints one InfluxDB line-protocol point per line, each
# prefixed with "> ":
#   > measurement,tag=v,... field=v,... <timestamp>
# Emit ONE record per point: measurement, tag set, field set, and timestamp.

_tt_san () { local v="$1"; v="${v//$'\t'/_}"; v="${v// /_}"; printf '%s' "$v"; }

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    case "$text" in
        "> "*) : ;;
        *$'\n'"> "*) : ;;
        *) return 1 ;;
    esac
    [[ "$text" == *"="* ]] || return 1
    _STRATEGY_CONFIDENCE=86
    return 0
}

strategy_extract () {
    local text="$1" result="" entry=0 line body meas_tags fields ts
    local -a p
    while IFS= read -r line; do
        [[ "$line" == "> "* ]] || continue
        body="${line#> }"
        # split into 3 space-separated segments: <measurement,tags> <fields> <ts>
        read -ra p <<< "$body"
        [[ ${#p[@]} -eq 3 ]] || continue
        meas_tags="${p[0]}"; fields="${p[1]}"; ts="${p[2]}"
        [[ "$meas_tags" == *","* ]] || continue
        entry=$((entry + 1))
        result+="entry${entry}.measurement ${meas_tags%%,*}"$'\n'
        result+="entry${entry}.tags ${meas_tags#*,}"$'\n'
        result+="entry${entry}.fields $(_tt_san "$fields")"$'\n'
        result+="entry${entry}.timestamp ${ts}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
