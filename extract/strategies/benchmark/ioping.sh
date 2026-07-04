#!/bin/bash
## Name: ioping
## Description: Extract I/O latency metrics from ioping output
## Version: 1.0
## Priority: 15
## Sample: samples/ioping/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=85
    # Direct ioping marker
    if [[ "$text" == *"ioping"* ]]; then
        return 0
    fi
    # "requests completed" + "iops" pattern
    if [[ "$text" == *"requests completed"* ]] && \
       [[ "$text" == *"iops"* ]]; then
        return 0
    fi
    # "min/avg/max" + time unit pattern
    if [[ "$text" == *"min/avg/max"* ]]; then
        if [[ "$text" =~ [[:space:]]us[[:space:]] || "$text" =~ [[:space:]]ms[[:space:]] ]]; then
            return 0
        fi
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Header line: --- /dev/sda (block device 500.1 GB) ioping statistics ---
        if [[ "$line" == *"ioping statistics"* ]]; then
            local device device_type device_size
            device=$(_strat_ioping_extract_device "$line")
            device_type=$(_strat_ioping_extract_device_type "$line")
            device_size=$(_strat_ioping_extract_device_size "$line")
            [[ -n "$device" ]] && result+="device ${device}"$'\n'
            [[ -n "$device_type" ]] && result+="device_type ${device_type}"$'\n'
            [[ -n "$device_size" ]] && result+="device_size ${device_size}"$'\n'
            continue
        fi

        # Completed line: 20 requests completed in 19.8 ms, 80 KiB read, 1.01 k iops, 3.95 MiB/s
        if [[ "$line" == *"requests completed"* ]]; then
            read -ra _arr <<< "$line"
            local req_count="${_arr[0]}"
            local total_time total_size iops throughput
            total_time=$(_strat_ioping_extract_completed_time "$line")
            total_size=$(_strat_ioping_extract_completed_size "$line")
            iops=$(_strat_ioping_extract_completed_iops "$line")
            throughput=$(_strat_ioping_extract_completed_throughput "$line")
            [[ -n "$req_count" ]] && result+="requests_completed ${req_count}"$'\n'
            [[ -n "$total_time" ]] && result+="total_time ${total_time}"$'\n'
            [[ -n "$total_size" ]] && result+="total_size ${total_size}"$'\n'
            [[ -n "$iops" ]] && result+="iops ${iops}"$'\n'
            [[ -n "$throughput" ]] && result+="throughput ${throughput}"$'\n'
            continue
        fi

        # Latency line: min/avg/max/mdev = 223 us / 990 us / 2.69 ms / 670 us
        if [[ "$line" == *"min/avg/max"* ]]; then
            local lat_min lat_avg lat_max lat_mdev
            lat_min=$(_strat_ioping_extract_latency "$line" 1)
            lat_avg=$(_strat_ioping_extract_latency "$line" 2)
            lat_max=$(_strat_ioping_extract_latency "$line" 3)
            lat_mdev=$(_strat_ioping_extract_latency "$line" 4)
            [[ -n "$lat_min" ]] && result+="latency_min ${lat_min}"$'\n'
            [[ -n "$lat_avg" ]] && result+="latency_avg ${lat_avg}"$'\n'
            [[ -n "$lat_max" ]] && result+="latency_max ${lat_max}"$'\n'
            [[ -n "$lat_mdev" ]] && result+="latency_mdev ${lat_mdev}"$'\n'
            continue
        fi
    done <<< "$text"

    echo "$result"
}

# Extract device path from header line
_strat_ioping_extract_device () {
    local line="$1"
    # "--- /dev/sda (block device 500.1 GB) ioping statistics ---"
    local after="${line#--- }"
    read -ra _arr <<< "$after"
    echo "${_arr[0]}"
}

# Extract device type from parenthesized portion
_strat_ioping_extract_device_type () {
    local line="$1"
    # Extract text between ( and )
    [[ "$line" == *"("*")"* ]] || return
    local paren="${line#*(}"
    paren="${paren%%)*}"
    # device type is everything before the size (last two words are size+unit)
    read -ra _arr <<< "$paren"
    local count=${#_arr[@]}
    [[ $count -lt 3 ]] && return
    local i result_str=""
    for ((i=0; i<count-2; i++)); do
        if [[ -n "$result_str" ]]; then
            result_str+="_"
        fi
        result_str+="${_arr[$i]}"
    done
    echo "$result_str"
}

# Extract device size from parenthesized portion
_strat_ioping_extract_device_size () {
    local line="$1"
    [[ "$line" == *"("*")"* ]] || return
    local paren="${line#*(}"
    paren="${paren%%)*}"
    # size is the last two words (e.g., "500.1 GB")
    read -ra _arr <<< "$paren"
    local count=${#_arr[@]}
    [[ $count -lt 2 ]] && return
    echo "${_arr[$((count-2))]}_${_arr[$((count-1))]}"
}

# Extract time from "completed in X unit" portion
_strat_ioping_extract_completed_time () {
    local line="$1"
    [[ "$line" == *"completed in "* ]] || return
    local after="${line#*completed in }"
    local before_comma="${after%%,*}"
    echo "${before_comma// /_}"
}

# Extract total data size (e.g., "80 KiB") from completed line
_strat_ioping_extract_completed_size () {
    local line="$1"
    # After "completed in X unit, " comes "80 KiB read, ..."
    [[ "$line" == *"completed in "* ]] || return
    local after="${line#*completed in }"
    # Skip past first comma
    [[ "$after" == *","* ]] || return
    after="${after#*, }"
    local before_comma="${after%%,*}"
    read -ra _arr <<< "$before_comma"
    [[ ${#_arr[@]} -ge 2 ]] && echo "${_arr[0]}_${_arr[1]}"
}

# Extract iops value from completed line
# Handles formats: "1.01 k iops", "1010 iops"
_strat_ioping_extract_completed_iops () {
    local line="$1"
    # Split on commas and find the part with "iops"
    local remaining="$line"
    while [[ "$remaining" == *","* ]]; do
        local part="${remaining%%,*}"
        remaining="${remaining#*,}"
        if [[ "$part" == *"iops"* ]]; then
            _strat_ioping_parse_iops_part "$part"
            return
        fi
    done
    # Check the last segment
    if [[ "$remaining" == *"iops"* ]]; then
        _strat_ioping_parse_iops_part "$remaining"
    fi
}

_strat_ioping_parse_iops_part () {
    local part="$1"
    read -ra _arr <<< "$part"
    local i
    for ((i=0; i<${#_arr[@]}; i++)); do
        if [[ "${_arr[$i]}" == "iops" ]]; then
            if [[ $i -ge 2 && "${_arr[$((i-2))]}" =~ ^[0-9] ]]; then
                # "1.01 k iops" -> "1.01_k"
                echo "${_arr[$((i-2))]}_${_arr[$((i-1))]}"
            elif [[ $i -ge 1 ]]; then
                # "1010 iops" -> "1010"
                echo "${_arr[$((i-1))]}"
            fi
            return
        fi
    done
}

# Extract throughput (last comma-separated value, e.g., "3.95 MiB/s")
_strat_ioping_extract_completed_throughput () {
    local line="$1"
    # Get last comma-separated part
    local last_part="${line##*,}"
    # If the last part contains a rate like MiB/s or MB/s
    if [[ "$last_part" =~ [KMGTkmgt]i?[Bb]/s ]]; then
        read -ra _arr <<< "$last_part"
        local i
        for ((i=0; i<${#_arr[@]}; i++)); do
            if [[ "${_arr[$i]}" == *"/s" ]]; then
                if [[ $i -ge 1 && "${_arr[$((i-1))]}" =~ ^[0-9] ]]; then
                    echo "${_arr[$((i-1))]}_${_arr[$i]}"
                else
                    echo "${_arr[$i]}"
                fi
                return
            fi
        done
    fi
}

# Extract latency value at position N (1=min, 2=avg, 3=max, 4=mdev)
# Input: "min/avg/max/mdev = 223 us / 990 us / 2.69 ms / 670 us"
_strat_ioping_extract_latency () {
    local line="$1"
    local pos="$2"
    # Get everything after "= "
    local values="${line#*= }"
    # Split on " / "
    local count=0
    while [[ -n "$values" ]]; do
        count=$((count + 1))
        local segment
        if [[ "$values" == *" / "* ]]; then
            segment="${values%% / *}"
            values="${values#* / }"
        else
            segment="$values"
            values=""
        fi
        if [[ $count -eq $pos ]]; then
            # segment is like "223 us" or "2.69 ms"
            echo "${segment// /_}"
            return
        fi
    done
}
