#!/bin/bash
## Name: ip-tunnel
## Description: Extract tunnel interfaces (name/mode/remote/local) from `ip tunnel show`
## Version: 1.0
## Priority: 9
## Technique: yes
## Sample: samples/ip-tunnel/basic.txt

# `ip tunnel show` prints one line per tunnel:
#   gre0: gre/ip remote any local any ttl inherit nopmtudisc
# i.e. "<name>: <mode> remote <R> local <L> ...". One record per tunnel.

_iptun_is_tunnel () {
    # <name>: <mode> ... remote ... local ...
    [[ "$1" =~ ^[A-Za-z][A-Za-z0-9._-]*:\ .*\ remote\ .*\ local\  ]]
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    local line
    while IFS= read -r line; do
        if _iptun_is_tunnel "$line"; then
            _STRATEGY_CONFIDENCE=86
            return 0
        fi
    done <<< "$text"
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line i
    while IFS= read -r line; do
        _iptun_is_tunnel "$line" || continue
        local name="${line%%:*}"
        local rest="${line#*: }"
        read -ra _t <<< "$rest"
        local mode="${_t[0]:-}"
        local remote="" local_="" ttl=""
        for ((i = 1; i < ${#_t[@]}; i++)); do
            case "${_t[$i]}" in
                remote) remote="${_t[$((i + 1))]:-}" ;;
                local)  local_="${_t[$((i + 1))]:-}" ;;
                ttl)    ttl="${_t[$((i + 1))]:-}" ;;
            esac
        done
        name="${name// /_}"; mode="${mode// /_}"
        remote="${remote// /_}"; local_="${local_// /_}"; ttl="${ttl// /_}"
        entry=$((entry + 1))
        result+="entry${entry}.name ${name}"$'\n'
        result+="entry${entry}.mode ${mode}"$'\n'
        result+="entry${entry}.remote ${remote}"$'\n'
        result+="entry${entry}.local ${local_}"$'\n'
        result+="entry${entry}.ttl ${ttl}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
