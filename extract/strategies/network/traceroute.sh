#!/bin/bash
## Name: traceroute
## Description: Extract per-hop records from traceroute output (hop, host, rtt1-3)
## Version: 1.0
## Priority: 18
## Sample: samples/traceroute-hops/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    _is_json "$text" && return 1
    # Distinctive signature: first non-blank line begins with "traceroute to".
    while IFS= read -r line; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        if [[ "$line" == "traceroute to "* ]]; then
            _STRATEGY_CONFIDENCE=88
            return 0
        fi
        return 1
    done <<< "$text"
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0
    while IFS= read -r line; do
        # Skip blank lines and the "traceroute to ..." header.
        [[ -z "${line//[[:space:]]/}" ]] && continue
        [[ "$line" == "traceroute to "* ]] && continue

        # Trim leading whitespace, then split into fields.
        local trimmed="${line#"${line%%[![:space:]]*}"}"
        read -ra f <<< "$trimmed"
        [[ ${#f[@]} -ge 1 ]] || continue

        # First token must be the hop number.
        local hop="${f[0]}"
        case "$hop" in *[!0-9]*) continue ;; esac

        local host="" rtt1="" rtt2="" rtt3=""

        # Timeout hop: "N  * * *"
        if [[ "${f[1]:-}" == "*" ]]; then
            host="*"
        else
            host="${f[1]:-}"
            # Collect ms values: each number immediately preceding an "ms" token.
            local i rtts=0
            for ((i = 1; i < ${#f[@]}; i++)); do
                if [[ "${f[$i]}" == "ms" && $i -ge 1 ]]; then
                    local cand="${f[$((i-1))]}"
                    case "$cand" in
                        ""|*[!0-9.]*) ;;
                        *)
                            rtts=$((rtts + 1))
                            case $rtts in
                                1) rtt1="$cand" ;;
                                2) rtt2="$cand" ;;
                                3) rtt3="$cand" ;;
                            esac
                            ;;
                    esac
                fi
            done
        fi

        entry=$((entry + 1))
        result+="entry${entry}.hop ${hop}"$'\n'
        [[ -n "$host" ]] && result+="entry${entry}.host ${host}"$'\n'
        [[ -n "$rtt1" ]] && result+="entry${entry}.rtt1 ${rtt1}"$'\n'
        [[ -n "$rtt2" ]] && result+="entry${entry}.rtt2 ${rtt2}"$'\n'
        [[ -n "$rtt3" ]] && result+="entry${entry}.rtt3 ${rtt3}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
