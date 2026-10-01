#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: binnacle-agree
## Description: Extract per-group results from `agree` (binnacle) fleet-comparison output
## Version: 1.0
## Priority: 22
## Sample: samples/binnacle-agree/basic.txt

# `agree` runs the same command across many hosts, buckets hosts by identical
# output into GROUP blocks, and reports whether each block agreed (ok) or
# couldn't be reached (unreachable). One row per GROUP block; header line
# fields (total hosts/groups/agree-count, the command run) are broadcast to
# every row.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1

    local re_header='(^|
)agree[[:space:]]+--[[:space:]]+[0-9]+[[:space:]]+hosts,'
    local re_group='(^|
)[[:space:]]{2}GROUP[[:space:]]+[0-9]+[[:space:]]+[0-9]+[[:space:]]+hosts?[[:space:]]'
    [[ "$text" =~ $re_header ]] || return 1
    [[ "$text" =~ $re_group ]] || return 1

    _STRATEGY_CONFIDENCE=95
    return 0
}

strategy_extract () {
    local text="$1"
    local result="" n=0

    local total_hosts="" total_groups="" agree_count="" command_line=""
    local found_header=0

    local gnum="" host_count="" status="" digest="" baseline="" hosts_str=""
    local -a detail_lines=()
    local in_group=0 stop=0

    local re_header='^agree[[:space:]]+--[[:space:]]+([0-9]+)[[:space:]]+hosts,[[:space:]]+([0-9]+)[[:space:]]+groups,[[:space:]]+([0-9]+)[[:space:]]+agree'
    local re_group='^[[:space:]]{2}GROUP[[:space:]]+([0-9]+)[[:space:]]+([0-9]+)[[:space:]]+hosts?[[:space:]]+([A-Za-z_]+)(.*)$'
    local re_digest='d=([^[:space:]]+)'
    local re_hosts='^[[:space:]]*hosts:[[:space:]]*(.*)$'
    local re_nextsteps='^[[:space:]]*WHAT TO DO NEXT'

    _ba_flush () {
        [[ -z "$gnum" ]] && return
        n=$((n + 1))
        local p="entry${n}."
        result+="${p}group ${gnum}"$'\n'
        result+="${p}host_count ${host_count}"$'\n'
        result+="${p}status ${status}"$'\n'
        result+="${p}digest ${digest}"$'\n'
        result+="${p}hosts ${hosts_str}"$'\n'
        result+="${p}baseline ${baseline:-0}"$'\n'
        if [[ ${#detail_lines[@]} -gt 0 ]]; then
            local joined="" d
            for d in "${detail_lines[@]}"; do
                if [[ -z "$joined" ]]; then joined="$d"; else joined+=" | ${d}"; fi
            done
            result+="${p}detail ${joined}"$'\n'
        fi
        gnum=""; host_count=""; status=""; digest=""; baseline=""; hosts_str=""
        detail_lines=()
    }

    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ $stop -eq 1 ]] && break

        if [[ $found_header -eq 0 && "$line" =~ $re_header ]]; then
            total_hosts="${BASH_REMATCH[1]}"
            total_groups="${BASH_REMATCH[2]}"
            agree_count="${BASH_REMATCH[3]}"
            found_header=1
            continue
        fi

        if [[ $found_header -eq 1 && -z "$command_line" && $in_group -eq 0 ]]; then
            local trimmed="$line"
            trimmed="${trimmed#"${trimmed%%[![:space:]]*}"}"
            if [[ -n "$trimmed" && "$trimmed" != GROUP* ]]; then
                # Command line has a large gap before trailing timing info
                # ("11.4s, 32 jobs"); keep only the command portion.
                local re_cmdsplit='^(.+[^[:space:]])[[:space:]][[:space:]]+'
                if [[ "$trimmed" =~ $re_cmdsplit ]]; then
                    command_line="${BASH_REMATCH[1]}"
                else
                    command_line="$trimmed"
                fi
                continue
            fi
        fi

        if [[ "$line" =~ $re_nextsteps ]]; then
            _ba_flush
            stop=1
            continue
        fi

        if [[ "$line" =~ $re_group ]]; then
            _ba_flush
            gnum="${BASH_REMATCH[1]}"
            host_count="${BASH_REMATCH[2]}"
            status="${BASH_REMATCH[3]}"
            local rest="${BASH_REMATCH[4]}"
            digest=""
            [[ "$rest" =~ $re_digest ]] && digest="${BASH_REMATCH[1]}"
            baseline=0
            [[ "$rest" == *"<- baseline"* ]] && baseline=1
            in_group=1
            continue
        fi

        if [[ -z "$line" ]]; then
            [[ $in_group -eq 1 ]] && _ba_flush
            in_group=0
            continue
        fi

        [[ $in_group -eq 1 ]] || continue

        if [[ "$line" =~ $re_hosts ]]; then
            hosts_str="${BASH_REMATCH[1]}"
            continue
        fi

        local dtrim="$line"
        dtrim="${dtrim#"${dtrim%%[![:space:]]*}"}"
        [[ -n "$dtrim" ]] && detail_lines+=("$dtrim")
    done

    [[ $in_group -eq 1 ]] && _ba_flush

    [[ -n "$total_hosts" ]] && result+="total_hosts ${total_hosts}"$'\n'
    [[ -n "$total_groups" ]] && result+="total_groups ${total_groups}"$'\n'
    [[ -n "$agree_count" ]] && result+="agree_count ${agree_count}"$'\n'
    [[ -n "$command_line" ]] && result+="command ${command_line}"$'\n'
    result+="total_entries ${n}"$'\n'
    echo "$result"
}
