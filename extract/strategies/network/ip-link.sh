#!/bin/bash
## Name: ip-link
## Description: iproute2 `ip addr` / `ip link` — one tidy row per interface
## Version: 1.0
## Priority: 17
## Sample: samples/ip-link/basic.txt

# `ip addr` / `ip link` print a multi-line stanza per interface:
#
#   2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UP …
#       link/ether 52:54:00:12:34:56 brd ff:ff:ff:ff:ff:ff
#       inet 192.168.1.42/24 brd 192.168.1.255 scope global dynamic eth0
#
# A new record starts at an `N: name:` header line; the following indented lines
# (link/ether, inet, inet6) belong to it. Emit one indexed record per interface
# so the tidy melt renders one row per interface with shared columns.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    local _first="" _l
    while IFS= read -r _l; do
        [[ -z "${_l//[[:space:]]/}" ]] && continue
        _first="$_l"; break
    done <<< "$text"
    # First line is an iproute2 interface header: `<index>: <name>: …` and the
    # block carries an `mtu <n>` field somewhere (rules out `N: label:` prose).
    [[ "$_first" =~ ^[0-9]+:[[:space:]]+[A-Za-z0-9@._-]+:[[:space:]] ]] || return 1
    [[ "$text" =~ (^|$'\n')[[:space:]]*[0-9]+:[[:space:]]+[A-Za-z0-9@._-]+:[[:space:]].*[[:space:]]mtu[[:space:]] ]] || return 1
    _STRATEGY_CONFIDENCE=85
    return 0
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 _l
    while IFS= read -r _l; do
        [[ -z "${_l//[[:space:]]/}" ]] && continue
        local _tk; _tk=(); read -ra _tk <<< "$_l"

        if [[ "$_l" =~ ^[0-9]+:[[:space:]] ]]; then
            # New interface record.
            entry=$((entry + 1))
            local idx="${_tk[0]%:}"
            local name="${_tk[1]%:}"
            result+="entry${entry}.index ${idx}"$'\n'
            result+="entry${entry}.name ${name}"$'\n'
            # Flags: the `<FLAG,FLAG,…>` token.
            if [[ "${_tk[2]}" == "<"*">" ]]; then
                local flags="${_tk[2]#<}"; flags="${flags%>}"
                result+="entry${entry}.flags ${flags}"$'\n'
            fi
            # Recognised `keyword value` pairs on the header line.
            local i n=${#_tk[@]}
            for ((i = 3; i < n; i++)); do
                case "${_tk[$i]}" in
                    mtu|qdisc|state|group|qlen)
                        [[ $((i + 1)) -lt $n ]] && \
                            result+="entry${entry}.${_tk[$i]} ${_tk[$((i + 1))]}"$'\n'
                        i=$((i + 1)) ;;
                esac
            done
            continue
        fi

        # Continuation lines (indented) belong to the current interface.
        [[ $entry -eq 0 ]] && continue
        case "${_tk[0]}" in
            link/*) [[ -n "${_tk[1]:-}" ]] && result+="entry${entry}.mac ${_tk[1]}"$'\n' ;;
            inet)   [[ -n "${_tk[1]:-}" ]] && result+="entry${entry}.inet ${_tk[1]}"$'\n' ;;
            inet6)  [[ -n "${_tk[1]:-}" ]] && result+="entry${entry}.inet6 ${_tk[1]}"$'\n' ;;
        esac
    done <<< "$text"

    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
