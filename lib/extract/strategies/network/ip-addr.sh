#!/bin/bash
## Name: ip-addr
## Description: Extract interface addresses from `ip -o addr` (oneline) output
## Version: 1.0
## Priority: 24
## Technique: kv_custom
## Sample: samples/ip-addr/basic.txt

# `ip -o addr` prints one address per line:
#   2: eth0    inet 10.0.1.50/16 metric 100 brd 10.0.255.255 scope global eth0\  valid_lft ...
# Emit each as an indexed row group (entry<N>.<field>) so capture's tidy melt
# renders one row per address with shared columns (index, iface, family,
# address, scope, brd).

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=88
    _is_json "$text" && return 1

    # An `ip -o addr` line starts with "<num>: <iface>" and carries an
    # "inet"/"inet6" family token and a "scope" keyword. Require at least one
    # such line; the family + scope markers distinguish it from `ip route`.
    local hits=0 line
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        [[ "$line" == *" scope "* ]] || continue
        case "$line" in
            [0-9]*": "*" inet "*|[0-9]*": "*" inet6 "*) hits=$((hits + 1)) ;;
        esac
    done <<< "$text"
    [[ $hits -ge 1 ]] && return 0
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local n=0
    local line

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        [[ "$line" == *" scope "* ]] || continue

        read -ra _arr <<< "$line"
        [[ ${#_arr[@]} -lt 4 ]] && continue

        # _arr[0]="2:", _arr[1]=iface, _arr[2]=family, _arr[3]=address/prefix
        local family="${_arr[2]}"
        [[ "$family" == "inet" || "$family" == "inet6" ]] || continue

        n=$((n + 1))
        local prefix="entry${n}"
        local index="${_arr[0]%:}"

        result+="${prefix}.index ${index}"$'\n'
        result+="${prefix}.iface ${_arr[1]}"$'\n'
        result+="${prefix}.family ${family}"$'\n'
        result+="${prefix}.address ${_arr[3]}"$'\n'

        # Pull selected key/value markers (scope <s>, brd <addr>, metric <n>).
        local i
        for ((i=4; i<${#_arr[@]}; i++)); do
            case "${_arr[$i]}" in
                scope|brd|metric)
                    local key="${_arr[$i]}"
                    if [[ $((i + 1)) -lt ${#_arr[@]} ]]; then
                        i=$((i + 1))
                        result+="${prefix}.${key} ${_arr[$i]}"$'\n'
                    fi
                    ;;
            esac
        done
    done <<< "$text"

    [[ $n -gt 0 ]] && result+="total_entries ${n}"$'\n'
    echo "$result"
}
