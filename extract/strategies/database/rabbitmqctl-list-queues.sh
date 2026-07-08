#!/bin/bash
## Name: rabbitmqctl-list-queues
## Description: Extract queue rows from `rabbitmqctl list_queues`
## Version: 1.0
## Priority: 20
## Technique: yes
## Sample: samples/rabbitmqctl-list-queues/basic.txt

# `rabbitmqctl list_queues name messages consumers` prints a "Timeout:" line and
# a "Listing queues for vhost ..." banner, then TAB-separated rows
# `name<TAB>messages<TAB>consumers`. Emit ONE record per queue row; skip the
# banners.

_rq_san () { local v="$1"; v="${v//$'\t'/_}"; printf '%s' "$v"; }

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    [[ "$text" == *"Listing queues for vhost"* ]] || return 1
    _STRATEGY_CONFIDENCE=86
    return 0
}

strategy_extract () {
    local text="$1" result="" entry=0 line
    local -a t
    while IFS= read -r line; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        case "$line" in
            Timeout:*|"Listing queues"*) continue ;;
        esac
        [[ "$line" == *$'\t'* ]] || continue
        IFS=$'\t' read -ra t <<< "$line"
        [[ ${#t[@]} -eq 3 ]] || continue
        entry=$((entry + 1))
        result+="entry${entry}.name $(_rq_san "${t[0]}")"$'\n'
        result+="entry${entry}.messages ${t[1]}"$'\n'
        result+="entry${entry}.consumers ${t[2]}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
