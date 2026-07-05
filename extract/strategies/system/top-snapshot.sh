#!/bin/bash
## Name: top-snapshot
## Description: Extract stats from a single frame of macOS/Linux top output
## Version: 1.0
## Priority: 25
## Sample: samples/top-snapshot/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=75
    # Detect macOS top header: "Processes: N total" or "Load Avg:"
    if [[ "$text" == *"Processes:"*"total"* ]]; then
        return 0
    fi
    if [[ "$text" == *"Load Avg:"* ]]; then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""

    # Extract header stats
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Processes line: "Processes: 285 total, 2 running, 283 sleeping"
        if [[ "$line" == "Processes:"* ]]; then
            result+=$(_strat_top_snapshot_parse_processes "$line")
            continue
        fi

        # Load Avg line: "Load Avg: 1.23, 1.45, 1.67"
        if [[ "$line" == "Load Avg:"* ]]; then
            result+=$(_strat_top_snapshot_parse_load_avg "$line")
            continue
        fi

        # CPU usage line: "CPU usage: 12.3% user, 5.6% sys, 82.1% idle"
        if [[ "$line" == "CPU usage:"* ]]; then
            result+=$(_strat_top_snapshot_parse_cpu "$line")
            continue
        fi

        # PhysMem line: "PhysMem: 8192M used, 8192M unused"
        if [[ "$line" == "PhysMem:"* ]]; then
            result+=$(_strat_top_snapshot_parse_physmem "$line")
            continue
        fi
    done <<< "$text"

    # Extract process table
    local in_table=0
    local proc_num=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Detect table header
        if [[ "$line" =~ ^[\ ]*PID ]]; then
            in_table=1
            continue
        fi

        if [[ $in_table -eq 1 ]]; then
            proc_num=$((proc_num + 1))
            # Use read to collapse whitespace
            read -ra _arr <<< "$line"
            local pid="${_arr[0]}"
            local cmd="${_arr[1]}"
            local cpu="${_arr[2]}"
            local time_val="${_arr[3]}"
            local mem="${_arr[4]}"

            [[ -n "$pid" ]] && result+="process${proc_num}.pid ${pid}"$'\n'
            [[ -n "$cmd" ]] && result+="process${proc_num}.command ${cmd}"$'\n'
            [[ -n "$cpu" ]] && result+="process${proc_num}.cpu ${cpu}"$'\n'
            [[ -n "$time_val" ]] && result+="process${proc_num}.time ${time_val}"$'\n'
            [[ -n "$mem" ]] && result+="process${proc_num}.mem ${mem}"$'\n'
        fi
    done <<< "$text"

    echo "$result"
}

_strat_top_snapshot_parse_processes () {
    local line="$1"
    local val="${line#Processes:}"
    while [[ "$val" == " "* ]]; do val="${val# }"; done
    # "285 total, 2 running, 283 sleeping"
    # Split on commas and parse each segment
    local _result=""
    local _remaining="$val"
    while [[ -n "$_remaining" ]]; do
        local segment="${_remaining%%,*}"
        if [[ "$_remaining" == *","* ]]; then
            _remaining="${_remaining#*,}"
        else
            _remaining=""
        fi
        # Trim leading spaces
        while [[ "$segment" == " "* ]]; do segment="${segment# }"; done
        read -ra _arr <<< "$segment"
        local num="${_arr[0]}"
        local label="${_arr[1]}"
        [[ -n "$num" && -n "$label" ]] && _result+="processes_${label} ${num}"$'\n'
    done
    echo "$_result"
}

_strat_top_snapshot_parse_load_avg () {
    local line="$1"
    local val="${line#Load Avg:}"
    while [[ "$val" == " "* ]]; do val="${val# }"; done
    # Split on commas
    local load1="${val%%,*}"
    val="${val#*,}"
    local load5="${val%%,*}"
    val="${val#*,}"
    local load15="$val"
    # Trim spaces
    while [[ "$load1" == " "* ]]; do load1="${load1# }"; done
    while [[ "$load5" == " "* ]]; do load5="${load5# }"; done
    while [[ "$load15" == " "* ]]; do load15="${load15# }"; done
    while [[ "$load1" == *" " ]]; do load1="${load1% }"; done
    while [[ "$load5" == *" " ]]; do load5="${load5% }"; done
    while [[ "$load15" == *" " ]]; do load15="${load15% }"; done
    local _result=""
    [[ -n "$load1" ]] && _result+="load_avg_1min ${load1}"$'\n'
    [[ -n "$load5" ]] && _result+="load_avg_5min ${load5}"$'\n'
    [[ -n "$load15" ]] && _result+="load_avg_15min ${load15}"$'\n'
    echo "$_result"
}

_strat_top_snapshot_parse_cpu () {
    local line="$1"
    local val="${line#CPU usage:}"
    while [[ "$val" == " "* ]]; do val="${val# }"; done
    local _result=""
    local _remaining="$val"
    while [[ -n "$_remaining" ]]; do
        local segment="${_remaining%%,*}"
        if [[ "$_remaining" == *","* ]]; then
            _remaining="${_remaining#*,}"
        else
            _remaining=""
        fi
        while [[ "$segment" == " "* ]]; do segment="${segment# }"; done
        read -ra _arr <<< "$segment"
        local pct="${_arr[0]}"
        local label="${_arr[1]}"
        [[ -n "$pct" && -n "$label" ]] && _result+="cpu_${label} ${pct}"$'\n'
    done
    echo "$_result"
}

_strat_top_snapshot_parse_physmem () {
    local line="$1"
    local val="${line#PhysMem:}"
    while [[ "$val" == " "* ]]; do val="${val# }"; done
    local _result=""
    local _remaining="$val"
    while [[ -n "$_remaining" ]]; do
        local segment="${_remaining%%,*}"
        if [[ "$_remaining" == *","* ]]; then
            _remaining="${_remaining#*,}"
        else
            _remaining=""
        fi
        while [[ "$segment" == " "* ]]; do segment="${segment# }"; done
        read -ra _arr <<< "$segment"
        local amt="${_arr[0]}"
        local label="${_arr[1]}"
        [[ -n "$amt" && -n "$label" ]] && _result+="physmem_${label} ${amt}"$'\n'
    done
    echo "$_result"
}
