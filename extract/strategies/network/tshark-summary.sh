#!/bin/bash
## Name: tshark-summary
## Description: Extract per-packet records from tshark packet summary output
## Version: 1.0
## Priority: 26
## Sample: samples/tshark-summary/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    _is_json "$text" && return 1
    # tshark summary lines: "<No> <Time> <Src> -> <Dst> <Proto> <Len> <Info>"
    # with a Unicode arrow between source and destination.
    local n=0 line trimmed
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        case "$line" in
            *"→"*) : ;;
            *) continue ;;
        esac
        # Strip leading whitespace, then require "<int> <float> " prefix.
        trimmed="${line#"${line%%[![:space:]]*}"}"
        if [[ "$trimmed" =~ ^[0-9]+[[:space:]]+[0-9]+\.[0-9]+[[:space:]] ]]; then
            n=$((n + 1))
        fi
    done <<< "$text"
    if [[ $n -ge 2 ]]; then
        _STRATEGY_CONFIDENCE=86
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local entry=0
    local line trimmed
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        case "$line" in
            *"→"*) : ;;
            *) continue ;;
        esac
        trimmed="${line#"${line%%[![:space:]]*}"}"
        [[ "$trimmed" =~ ^[0-9]+[[:space:]]+[0-9]+\.[0-9]+[[:space:]] ]] || continue

        read -ra f <<< "$trimmed"
        # f[0]=No f[1]=Time f[2]=Source f[3]=arrow f[4]=Dest f[5]=Proto f[6]=Length f[7..]=Info
        [[ ${#f[@]} -ge 7 ]] || continue

        local no="${f[0]}"
        local time="${f[1]}"
        local src="${f[2]}"
        local dst="${f[4]}"
        local proto="${f[5]}"
        local length="${f[6]}"
        local info=""
        local i
        for ((i = 7; i < ${#f[@]}; i++)); do
            info+="${f[$i]} "
        done
        info="${info%" "}"

        entry=$((entry + 1))
        result+="entry${entry}.no ${no}"$'\n'
        result+="entry${entry}.time ${time}"$'\n'
        result+="entry${entry}.source ${src}"$'\n'
        result+="entry${entry}.destination ${dst}"$'\n'
        result+="entry${entry}.protocol ${proto}"$'\n'
        result+="entry${entry}.length ${length}"$'\n'
        result+="entry${entry}.info ${info}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
