#!/bin/bash
## Name: ip-xfrm-state
## Description: Extract IPsec SAs (src/dst/proto) from `ip xfrm state`
## Version: 1.0
## Priority: 26
## Technique: yes
## Sample: samples/ip-xfrm-state/basic.txt

# `ip xfrm state` prints each SA as a "src <A> dst <B>" line followed by
# indented "proto ..."/"auth ..."/etc. lines. One record per SA.

_xfrm_is_sa () {
    [[ "$1" =~ ^src\ [^[:space:]]+\ dst\ [^[:space:]]+ ]]
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    local line saw_sa=0 saw_proto=0
    while IFS= read -r line; do
        _xfrm_is_sa "$line" && saw_sa=1
        [[ "$line" =~ ^[[:space:]]+proto\ (esp|ah|comp)\  ]] && saw_proto=1
    done <<< "$text"
    if [[ $saw_sa -eq 1 && $saw_proto -eq 1 ]]; then
        _STRATEGY_CONFIDENCE=86
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line
    local -a srcs=() dsts=() protos=()
    while IFS= read -r line; do
        if _xfrm_is_sa "$line"; then
            read -ra _s <<< "$line"
            # _s[0]=src _s[1]=<srcval> _s[2]=dst _s[3]=<dstval>
            entry=$((entry + 1))
            srcs[$entry]="${_s[1]:-}"
            dsts[$entry]="${_s[3]:-}"
            protos[$entry]=""
        elif [[ "$line" =~ ^[[:space:]]+proto\  && $entry -ge 1 ]]; then
            read -ra _p <<< "$line"
            protos[$entry]="${_p[1]:-}"
        fi
    done <<< "$text"
    local i
    for ((i = 1; i <= entry; i++)); do
        local src="${srcs[$i]}" dst="${dsts[$i]}" proto="${protos[$i]}"
        result+="entry${i}.src ${src}"$'\n'
        result+="entry${i}.dst ${dst}"$'\n'
        result+="entry${i}.proto ${proto}"$'\n'
    done
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
