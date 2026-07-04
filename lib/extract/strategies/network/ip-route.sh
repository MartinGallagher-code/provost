#!/bin/bash
## Name: ip-route
## Description: Extract routing table entries from ip route show output
## Version: 1.0
## Priority: 25
## Technique: kv_custom
## Sample: samples/ip-route/sample1.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=85
    _is_json "$text" && return 1
    # ip route output has lines with "dev", "proto", "scope" keywords
    local dev_count=0
    local proto_count=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        [[ "$line" == *" dev "* ]] && dev_count=$((dev_count + 1))
        [[ "$line" == *" proto "* ]] && proto_count=$((proto_count + 1))
    done <<< "$text"
    if [[ $dev_count -ge 2 && $proto_count -ge 1 ]]; then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local route_n=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        route_n=$((route_n + 1))
        local prefix="route${route_n}"

        read -ra _arr <<< "$line"
        [[ ${#_arr[@]} -lt 1 ]] && continue

        # First token is destination (or "default")
        local dest="${_arr[0]}"
        result+="${prefix}.dest ${dest}"$'\n'

        # Parse key-value pairs: via X, dev X, proto X, scope X, src X, metric X
        local i
        for ((i=1; i<${#_arr[@]}; i++)); do
            case "${_arr[$i]}" in
                via|dev|proto|scope|src|metric|mtu|weight)
                    local key="${_arr[$i]}"
                    local val=""
                    if [[ $((i + 1)) -lt ${#_arr[@]} ]]; then
                        i=$((i + 1))
                        val="${_arr[$i]}"
                    fi
                    [[ -n "$val" ]] && result+="${prefix}.${key} ${val}"$'\n'
                    ;;
            esac
        done
    done <<< "$text"

    echo "$result"
}
