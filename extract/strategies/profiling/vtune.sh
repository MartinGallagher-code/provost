#!/bin/bash
## Name: vtune
## Description: Extract performance metrics from Intel VTune summary output
## Version: 1.0
## Priority: 25
## Sample: samples/vtune/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90
    # Strong indicator: VTune header
    if [[ "$text" == *"VTune"* ]] || [[ "$text" == *"vtune"* ]]; then
        # Confirm with at least one metric keyword
        if [[ "$text" == *"Elapsed Time"* ]] || [[ "$text" == *"CPU Time"* ]] || \
           [[ "$text" == *"CPI Rate"* ]] || [[ "$text" == *"Hotspots"* ]]; then
            return 0
        fi
    fi
    # Alternative: detect by metric pattern without VTune name
    local metric_count=0
    if [[ "$text" == *"Elapsed Time"* ]]; then metric_count=$((metric_count + 1)); fi
    if [[ "$text" == *"CPU Time"* ]]; then metric_count=$((metric_count + 1)); fi
    if [[ "$text" == *"CPI Rate"* ]]; then metric_count=$((metric_count + 1)); fi
    if [[ "$text" == *"Hotspots"* ]]; then metric_count=$((metric_count + 1)); fi
    # Need at least 3 VTune-specific metrics to avoid false positives
    [[ $metric_count -ge 3 ]]
}

strategy_extract () {
    local text="$1"
    local result=""
    local hotspot_n=0
    local in_hotspots=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Extract Elapsed Time: "Elapsed Time: 12.345s" or "Elapsed Time    12.345"
        if [[ "$line" == *"Elapsed Time"* ]]; then
            local val
            val=$(_strat_vtune_extract_value "$line")
            [[ -n "$val" ]] && result+="elapsed_time ${val}"$'\n'
            continue
        fi

        # Extract CPU Time
        if [[ "$line" == *"CPU Time"* ]] && [[ "$line" != *"Effective CPU"* ]]; then
            local val
            val=$(_strat_vtune_extract_value "$line")
            [[ -n "$val" ]] && result+="cpu_time ${val}"$'\n'
            continue
        fi

        # Extract CPI Rate
        if [[ "$line" == *"CPI Rate"* ]]; then
            local val
            val=$(_strat_vtune_extract_value "$line")
            [[ -n "$val" ]] && result+="cpi_rate ${val}"$'\n'
            continue
        fi

        # Detect hotspot section
        if [[ "$line" == *"Hotspots"* ]] || [[ "$line" == *"Top Hotspots"* ]] || \
           [[ "$line" == *"Function"*"CPU Time"* ]] || [[ "$line" == *"Function"*"Self Time"* ]]; then
            in_hotspots=1
            continue
        fi

        # Parse hotspot function lines (tabular: function_name  self_time  %)
        if [[ $in_hotspots -eq 1 ]]; then
            # Skip separator/header lines
            [[ "$line" == ------* ]] && continue
            [[ "$line" == *"Function"* ]] && continue

            # Stop at blank section or new section header
            if [[ "$line" =~ ^[A-Z][a-z]+:$ ]] || [[ "$line" =~ ^[[:space:]]*$ ]]; then
                in_hotspots=0
                continue
            fi

            # Parse: "function_name    1.234s" or "function_name    1.234    12.5%"
            read -ra _arr <<< "$line"
            if [[ ${#_arr[@]} -ge 2 ]]; then
                hotspot_n=$((hotspot_n + 1))
                local fname="${_arr[0]}"
                local ftime="${_arr[1]}"
                # Remove trailing 's' from time if present
                ftime="${ftime%s}"
                result+="hotspot${hotspot_n}_function ${fname}"$'\n'
                result+="hotspot${hotspot_n}_self_time ${ftime}"$'\n'
                # If there's a percentage field
                if [[ ${#_arr[@]} -ge 3 ]]; then
                    local pct="${_arr[2]}"
                    pct="${pct%%%}"
                    result+="hotspot${hotspot_n}_percent ${pct}"$'\n'
                fi
            fi
        fi
    done <<< "$text"

    echo "$result"
}

_strat_vtune_extract_value () {
    local line="$1"
    # Handle "Key: value" or "Key    value" formats
    local val=""
    if [[ "$line" == *":"* ]]; then
        val="${line#*:}"
    else
        # Take last numeric-looking token
        read -ra _arr <<< "$line"
        local i
        for ((i=${#_arr[@]}-1; i>=0; i--)); do
            if [[ "${_arr[$i]}" =~ ^[0-9] ]]; then
                val="${_arr[$i]}"
                break
            fi
        done
    fi
    # Trim whitespace and trailing units
    val="${val#"${val%%[![:space:]]*}"}"
    val="${val%"${val##*[![:space:]]}"}"
    val="${val%s}"
    echo "$val"
}
