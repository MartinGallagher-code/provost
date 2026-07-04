#!/bin/bash
## Name: openssl-speed
## Description: Extract algorithm throughput from openssl speed output
## Version: 1.0
## Priority: 12
## Sample: samples/openssl-speed/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90

    # Pattern 1: "OpenSSL" + "bytes per second"
    if [[ "$text" == *"OpenSSL"* ]]; then
        if [[ "$text" == *"bytes per second"* ]]; then
            return 0
        fi
    fi

    # Pattern 2: table header "type" + "16 bytes" + "64 bytes"
    if [[ "$text" == *"type"* ]]; then
        if [[ "$text" == *"16 bytes"* ]]; then
            if [[ "$text" == *"64 bytes"* ]]; then
                return 0
            fi
        fi
    fi

    # Pattern 3: "Doing" + "for" + "on" + "size blocks"
    if [[ "$text" == *"Doing"*"for"*"on"*"size blocks"* ]]; then
        return 0
    fi

    return 1
}

strategy_extract () {
    local text="$1"
    local result=""

    # Extract OpenSSL version
    local version_line=""
    while IFS= read -r _line; do
        if [[ "$_line" == "OpenSSL "* ]]; then
            version_line="$_line"
            break
        fi
    done <<< "$text"
    if [ -n "$version_line" ]; then
        local version_val
        version_val=$(_strat_openssl_speed_extract_version "$version_line")
        if [ -n "$version_val" ]; then
            result+="openssl_version ${version_val}"$'\n'
        fi
    fi

    # Extract "Doing" lines for operation counts
    local doing_lines=""
    while IFS= read -r _line; do
        if [[ "$_line" == "Doing "* ]]; then
            doing_lines+="$_line"$'\n'
        fi
    done <<< "$text"
    if [ -n "$doing_lines" ]; then
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            _strat_openssl_speed_parse_doing_line "$line"
            if [ -n "$_OSS_DOING_ALGO" ] && [ -n "$_OSS_DOING_SIZE" ] && [ -n "$_OSS_DOING_COUNT" ]; then
                result+="${_OSS_DOING_ALGO}.ops_${_OSS_DOING_SIZE}_bytes ${_OSS_DOING_COUNT}"$'\n'
            fi
        done <<< "$doing_lines"
    fi

    # Find and parse the throughput table
    # Detect the header line to know column positions
    local header_line=""
    while IFS= read -r _line; do
        if [[ "$_line" == "type "* || "$_line" == "type	"* ]]; then
            header_line="$_line"
            break
        fi
    done <<< "$text"
    if [ -n "$header_line" ]; then
        # Extract column size labels from header
        local col_labels
        col_labels=$(_strat_openssl_speed_parse_header "$header_line")

        # Parse data rows (lines starting with an algorithm name, followed by throughput values)
        while IFS= read -r line; do
            [ -z "$line" ] && continue

            # Skip known non-data lines
            [[ "$line" == "type "* || "$line" == "type	"* ]] && continue
            [[ "$line" == "OpenSSL"* ]] && continue
            [[ "$line" == "built on"* ]] && continue
            [[ "$line" == "options:"* ]] && continue
            [[ "$line" == "compiler:"* ]] && continue
            [[ "$line" == "CPUINFO:"* ]] && continue
            [[ "$line" == "The 'numbers'"* ]] && continue
            [[ "$line" == "Doing "* ]] && continue

            # Try to parse as a data row: algorithm name followed by numeric values ending in 'k'
            read -ra _arr <<< "$line"
            local algo="${_arr[0]}"
            # Validate: must start with a letter and the second field must be numeric-ish
            [[ "$algo" =~ ^[a-zA-Z] ]] || continue
            local second_field="${_arr[1]:-}"
            [[ "$second_field" =~ ^[0-9] ]] || continue

            # Extract values from columns
            _strat_openssl_speed_parse_data_row "$line" "$col_labels"
            if [ -n "$_OSS_DATA_RESULT" ]; then
                result+="${_OSS_DATA_RESULT}"
            fi
        done <<< "$text"
    fi

    echo "$result"
}

# Extract version string from "OpenSSL X.Y.Z date" line
_strat_openssl_speed_extract_version () {
    local line="$1"
    # Remove everything after the parenthetical, trim
    local result="${line%% (Library:*}"
    while [[ "$result" == *" " ]]; do result="${result% }"; done
    result="${result// /_}"
    echo "$result"
}

# Parse a "Doing" line to extract algorithm, block size, and operation count
# Sets global vars: _OSS_DOING_ALGO, _OSS_DOING_SIZE, _OSS_DOING_COUNT
_strat_openssl_speed_parse_doing_line () {
    local line="$1"
    _OSS_DOING_ALGO=""
    _OSS_DOING_SIZE=""
    _OSS_DOING_COUNT=""

    # Format: "Doing aes-256-cbc for 3s on 16 size blocks: 37623788 aes-256-cbc's in 3.00s"
    local after_doing="${line#Doing }"
    read -ra _arr <<< "$after_doing"
    local algo="${_arr[0]}"
    # Find "on N size blocks"
    local size=""
    local i
    for ((i=0; i<${#_arr[@]}; i++)); do
        if [[ "${_arr[$i]}" == "on" && "${_arr[$((i+2))]-}" == "size" ]]; then
            size="${_arr[$((i+1))]}"
            break
        fi
    done
    # Find count after ": "
    local count=""
    if [[ "$line" == *": "* ]]; then
        local after_colon="${line##*: }"
        read -ra _arr2 <<< "$after_colon"
        count="${_arr2[0]}"
    fi

    if [ -n "$algo" ] && [ -n "$size" ] && [ -n "$count" ]; then
        _OSS_DOING_ALGO="$algo"
        _OSS_DOING_SIZE="$size"
        _OSS_DOING_COUNT="$count"
    fi
}

# Parse the header line to extract column size labels
# Returns space-separated list of size labels (e.g., "16_bytes 64_bytes 256_bytes ...")
_strat_openssl_speed_parse_header () {
    local header="$1"
    # Extract all "N bytes" patterns from the header
    local labels=""
    local rest="${header#type}"
    while [ -n "$rest" ]; do
        while [[ "$rest" == " "* || "$rest" == $'\t'* ]]; do rest="${rest#?}"; done
        [ -z "$rest" ] && break
        # Extract the number and "bytes" word
        read -ra _arr <<< "$rest"
        local num="${_arr[0]}"
        [[ "$num" =~ ^[0-9] ]] || break
        local word="${_arr[1]:-}"
        if [ "$word" = "bytes" ]; then
            labels="${labels}${num}_bytes "
            # Remove the consumed "N bytes" from rest
            rest="${rest#"$num"}"
            while [[ "$rest" == " "* || "$rest" == $'\t'* ]]; do rest="${rest#?}"; done
            rest="${rest#bytes}"
        else
            break
        fi
    done
    echo "$labels"
}

# Parse a data row and produce fieldname value lines
# Sets global var: _OSS_DATA_RESULT
_strat_openssl_speed_parse_data_row () {
    local line="$1"
    local col_labels="$2"
    _OSS_DATA_RESULT=""

    read -ra _arr <<< "$line"
    local algo="${_arr[0]}"

    # Get all value fields (skip the algorithm name)
    local col_idx=1
    local label
    for label in $col_labels; do
        local val="${_arr[$col_idx]:-}"
        if [ -n "$val" ] && [ -n "$label" ]; then
            _OSS_DATA_RESULT+="${algo}.${label} ${val}"$'\n'
        fi
        col_idx=$((col_idx + 1))
    done
}
