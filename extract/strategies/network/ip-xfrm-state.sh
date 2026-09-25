#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: ip-xfrm-state
## Description: Extract IPsec SAs (src/dst/proto) from `ip xfrm state`
## Version: 1.0
## Priority: 26
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
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        _xfrm_is_sa "$line" && saw_sa=1
        [[ "$line" =~ ^[[:space:]]+proto\ (esp|ah|comp)\  ]] && saw_proto=1
    done
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
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        if _xfrm_is_sa "$line"; then
            { _fr_tok "$line"; _s=("${_FR_TOK[@]}"); }
            # _s[0]=src _s[1]=<srcval> _s[2]=dst _s[3]=<dstval>
            entry=$((entry + 1))
            srcs[$entry]="${_s[1]:-}"
            dsts[$entry]="${_s[3]:-}"
            protos[$entry]=""
        elif [[ "$line" =~ ^[[:space:]]+proto\  && $entry -ge 1 ]]; then
            { _fr_tok "$line"; _p=("${_FR_TOK[@]}"); }
            protos[$entry]="${_p[1]:-}"
        fi
    done
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
