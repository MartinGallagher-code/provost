#!/bin/bash
## Name: line-pairs
## Description: etcdctl get --prefix alternating key-line/value-line pairs -> key/value rows
## Version: 1.0
## Priority: 44
## Sample: samples/line-pairs/basic.txt

# etcdctl's `get --prefix` prints each key on its own line with the value on
# the NEXT line:
#
#   /config/service/api/replicas
#   3
#   /config/service/api/timeout
#   30s
#
# line-records emitted eight one-cell rows. The reviewer: "the even rows have
# values for the keys in the odd rows." Pairs re-join:
#
#   key                            value
#   /config/service/api/replicas   3
#   /config/service/api/timeout    30s
#
# Gates: an EVEN count of non-blank lines (>=4), and every ODD line is a
# `/`-rooted space-free path — the etcd key shape; the path/value alternation
# is what tells this from a plain list.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    local line n=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        n=$((n + 1))
        if [[ $((n % 2)) -eq 1 ]]; then
            # Key position: a /rooted, space-free path.
            [[ "$line" =~ ^/[^[:space:]]+$ ]] || return 1
        else
            # Value position: must NOT itself look like a key path — two
            # key-shaped lines in a row is a plain path list (dpkg -L).
            [[ "$line" =~ ^/[^[:space:]]+$ ]] && return 1
        fi
    done <<< "$text"
    [[ $n -ge 4 && $((n % 2)) -eq 0 ]] || return 1
    _STRATEGY_CONFIDENCE=82
    return 0
}

strategy_extract () {
    local text="$1"
    local line result="" entry=0 key=""
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        local v="$line"
        v="${v#"${v%%[![:space:]]*}"}"
        v="${v%"${v##*[![:space:]]}"}"
        if [[ -z "$key" ]]; then
            key="$v"
        else
            entry=$((entry + 1))
            result+="entry${entry}.key ${key}"$'\n'
            result+="entry${entry}.value ${v}"$'\n'
            key=""
        fi
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
