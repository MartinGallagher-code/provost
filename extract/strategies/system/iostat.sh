#!/bin/bash
## Name: iostat
## Description: Extract disk I/O statistics from iostat output
## Version: 1.0
## Priority: 25
## Sample: samples/iostat/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=85
    # Detect iostat column headers: KB/t + tps + MB/s (macOS format)
    if [[ "$text" == *"KB/t"* ]] && \
       [[ "$text" == *"tps"* ]] && \
       [[ "$text" == *"MB/s"* ]]; then
        return 0
    fi
    # Linux format: "Device:" header
    if [[ "$text" == *$'\n'"Device:"* ]] || [[ "$text" == "Device:"* ]]; then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""

    # Detect which format we have
    if [[ "$text" == *"KB/t"* ]]; then
        result=$(_strat_iostat_extract_macos "$text")
    elif [[ "$text" == *"Device:"* ]]; then
        result=$(_strat_iostat_extract_linux "$text")
    fi

    echo "$result"
}

_strat_iostat_extract_macos () {
    local text="$1"
    local result=""

    # First line: device names spaced across columns
    # Second line: column headers (KB/t  tps  MB/s) repeated per device
    # Third+ lines: data values

    local device_line=""
    local header_line=""
    local data_lines=""
    local line_idx=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        line_idx=$((line_idx + 1))

        if [[ $line_idx -eq 1 ]]; then
            device_line="$line"
        elif [[ $line_idx -eq 2 ]]; then
            header_line="$line"
        else
            data_lines+="$line"$'\n'
        fi
    done <<< "$text"

    [[ -z "$device_line" || -z "$header_line" ]] && return 0

    # Parse device names from the device line
    local devices=()
    read -ra devices <<< "$device_line"

    # Parse column headers per device
    local cols_per_device
    local all_cols=()
    read -ra all_cols <<< "$header_line"

    local num_devices=${#devices[@]}
    [[ $num_devices -eq 0 ]] && return 0
    cols_per_device=$(( ${#all_cols[@]} / num_devices ))
    [[ $cols_per_device -eq 0 ]] && return 0

    # Parse data lines
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local all_vals=()
        read -ra all_vals <<< "$line"

        local di
        for ((di=0; di<num_devices; di++)); do
            local dev_name="${devices[$di]}"
            local ci
            for ((ci=0; ci<cols_per_device; ci++)); do
                local val_idx=$((di * cols_per_device + ci))
                local col_idx=$((di * cols_per_device + ci))
                local col_name="${all_cols[$col_idx]:-}"
                local val="${all_vals[$val_idx]:-}"
                [[ -z "$col_name" || -z "$val" ]] && continue
                # Normalize column name: KB/t -> KB_per_t, MB/s -> MB_per_s
                col_name=$(_strat_iostat_normalize_col "$col_name")
                result+="${dev_name}.${col_name} ${val}"$'\n'
            done
        done
    done <<< "$data_lines"

    echo "$result"
}

_strat_iostat_extract_linux () {
    local text="$1"
    local result=""

    # Linux format: "Device:  rrqm/s wrqm/s r/s w/s ..."
    local header_line=""
    local in_data=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        if [[ "$line" == "Device:"* ]]; then
            header_line="$line"
            in_data=1
            continue
        fi

        [[ $in_data -eq 0 ]] && continue

        local headers=()
        read -ra headers <<< "$header_line"

        local vals=()
        read -ra vals <<< "$line"

        local dev_name="${vals[0]}"
        [[ -z "$dev_name" ]] && continue

        local i
        for ((i=1; i<${#headers[@]}; i++)); do
            local col="${headers[$i]}"
            local val="${vals[$i]:-}"
            [[ -z "$val" ]] && continue
            col=$(_strat_iostat_normalize_col "$col")
            result+="${dev_name}.${col} ${val}"$'\n'
        done
    done <<< "$text"

    echo "$result"
}

_strat_iostat_normalize_col () {
    local col="$1"
    # KB/t -> KB_per_t, MB/s -> MB_per_s, rrqm/s -> rrqm_per_s
    echo "${col//\//_per_}"
}
