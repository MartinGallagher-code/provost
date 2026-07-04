#!/bin/bash
## Name: qperf
## Description: Extract network bandwidth and latency metrics from qperf output
## Version: 1.0
## Priority: 12
## Sample: samples/qperf/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=85
    # qperf output has section headers like "tcp_bw:", "udp_lat:", "rc_bi_bw:" etc.
    # followed by indented key = value lines with units
    if [[ "$text" =~ (^|$'\n')[a-zA-Z0-9_]+_(bw|lat|bi_bw|bi_lat): ]] && \
       [[ "$text" == *"=/sec"* || "$text" == *"us"* || "$text" == *"ms"* || "$text" == *"ns"* || "$text" == *"% cpus"* ]]; then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local current_section=""

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Section header: "tcp_bw:", "udp_lat:", etc.
        if _strat_qperf_is_section_header "$line"; then
            current_section=$(_strat_qperf_get_section_name "$line")
            continue
        fi

        # Data line: "    bw              =    11.2 GB/sec"
        if [[ -n "$current_section" ]] && [[ "$line" == *"="* ]]; then
            local field_name field_value
            field_name=$(_strat_qperf_extract_field_name "$line")
            field_value=$(_strat_qperf_extract_field_value "$line")
            if [[ -n "$field_name" && -n "$field_value" ]]; then
                result+="${current_section}.${field_name} ${field_value}"$'\n'
            fi
        fi
    done <<< "$text"

    echo "$result"
}

_strat_qperf_is_section_header () {
    [[ "$1" =~ ^[a-zA-Z0-9_]+_(bw|lat|bi_bw|bi_lat):[\ ]*$ ]]
}

_strat_qperf_get_section_name () {
    local line="$1"
    # Strip trailing colon and whitespace
    line="${line%%:*}"
    echo "$line"
}

_strat_qperf_extract_field_name () {
    local line="$1"
    # Extract field name: everything before '=' trimmed
    local name="${line%%=*}"
    # Trim leading/trailing spaces
    while [[ "$name" == " "* ]]; do name="${name# }"; done
    while [[ "$name" == *" " ]]; do name="${name% }"; done
    echo "$name"
}

_strat_qperf_extract_field_value () {
    local line="$1"
    # Extract value after '=', trim leading whitespace, collapse spaces, replace spaces with underscores
    local value="${line#*=}"
    # Trim leading spaces
    while [[ "$value" == " "* ]]; do value="${value# }"; done
    # Trim trailing spaces
    while [[ "$value" == *" " ]]; do value="${value% }"; done
    # Collapse multiple spaces: use read to split and rejoin
    read -ra _arr <<< "$value"
    value="${_arr[*]}"
    # Replace spaces with underscores
    value="${value// /_}"
    echo "$value"
}
