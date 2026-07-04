#!/bin/bash
## Name: likwid
## Description: Extract performance metrics from LIKWID likwid-perfctr output
## Version: 1.0
## Priority: 25
## Sample: samples/likwid/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90
    # Strong: LIKWID name
    if [[ "$text" == *"LIKWID"* ]] || [[ "$text" == *"likwid"* ]]; then
        if [[ "$text" == *"Group"* ]] || [[ "$text" == *"Event"* ]] || \
           [[ "$text" == *"Runtime"* ]] || [[ "$text" == *"Counter"* ]]; then
            return 0
        fi
    fi
    # Detect by LIKWID-specific output pattern: "Group:" + "Event" + "Counter"
    local indicator_count=0
    if [[ "$text" == *"Group:"* ]]; then indicator_count=$((indicator_count + 1)); fi
    if [[ "$text" == *"Event"* ]] && [[ "$text" == *"Counter"* ]]; then indicator_count=$((indicator_count + 1)); fi
    if [[ "$text" == *"Runtime (RDTSC)"* ]] || [[ "$text" == *"Runtime [s]"* ]]; then indicator_count=$((indicator_count + 1)); fi
    if [[ "$text" == *"STAT"* ]] || [[ "$text" == *"Core"* ]]; then indicator_count=$((indicator_count + 1)); fi
    [[ $indicator_count -ge 2 ]]
}

strategy_extract () {
    local text="$1"
    local result=""
    local in_event_table=0
    local in_metric_table=0
    local event_n=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Group name
        if [[ "$line" == *"Group:"* ]]; then
            local val="${line##*Group:}"
            val="${val#"${val%%[![:space:]]*}"}"
            val="${val%"${val##*[![:space:]]}"}"
            [[ -n "$val" ]] && result+="group_name ${val}"$'\n'
            continue
        fi

        # Runtime
        if [[ "$line" == *"Runtime"* ]] && [[ "$line" =~ [0-9] ]]; then
            local val
            val=$(_strat_likwid_extract_value "$line")
            [[ -n "$val" ]] && result+="runtime ${val}"$'\n'
            continue
        fi

        # Clock frequency
        if [[ "$line" == *"clock"* ]] || [[ "$line" == *"Clock"* ]] || [[ "$line" == *"MHz"* ]]; then
            if [[ "$line" =~ [0-9] ]]; then
                local val
                val=$(_strat_likwid_extract_value "$line")
                [[ -n "$val" ]] && result+="clock_mhz ${val}"$'\n'
            fi
            continue
        fi

        # CPI
        if [[ "$line" == *"CPI"* ]] && [[ "$line" =~ [0-9] ]]; then
            local val
            val=$(_strat_likwid_extract_value "$line")
            [[ -n "$val" ]] && result+="cpi ${val}"$'\n'
            continue
        fi

        # MFLOP/s
        if [[ "$line" == *"MFLOP"* ]] || [[ "$line" == *"MFlops"* ]]; then
            if [[ "$line" =~ [0-9] ]]; then
                local val
                val=$(_strat_likwid_extract_value "$line")
                [[ -n "$val" ]] && result+="mflop_per_s ${val}"$'\n'
            fi
            continue
        fi

        # Bandwidth
        if [[ "$line" == *"bandwidth"* ]] || [[ "$line" == *"Bandwidth"* ]] || \
           [[ "$line" == *"Memory BW"* ]] || [[ "$line" == *"MByte/s"* ]]; then
            if [[ "$line" =~ [0-9] ]]; then
                local val
                val=$(_strat_likwid_extract_value "$line")
                [[ -n "$val" ]] && result+="bandwidth ${val}"$'\n'
            fi
            continue
        fi

        # Detect Event/Counter table
        if [[ "$line" == *"Event"* ]] && [[ "$line" == *"Counter"* ]]; then
            in_event_table=1
            in_metric_table=0
            continue
        fi

        # Detect Metric table
        if [[ "$line" == *"Metric"* ]] && [[ "$line" == *"Core"* || "$line" == *"Sum"* || "$line" == *"STAT"* ]]; then
            in_metric_table=1
            in_event_table=0
            continue
        fi

        # Skip table separators
        if [[ "$line" == *"|"*"-"*"|"* ]] || [[ "$line" == +*+*+ ]]; then
            continue
        fi

        # Parse Event/Counter rows: "| INSTR_RETIRED_ANY | FIXC0 | 123456789 |"
        if [[ $in_event_table -eq 1 ]] && [[ "$line" == *"|"* ]]; then
            # Split by pipe
            local cleaned="${line//|/ }"
            read -ra _arr <<< "$cleaned"
            if [[ ${#_arr[@]} -ge 3 ]]; then
                event_n=$((event_n + 1))
                local ename="${_arr[0]}"
                local counter="${_arr[1]}"
                # Value is typically the third+ field
                local eval_val="${_arr[2]}"
                eval_val="${eval_val//,/}"
                result+="event${event_n}_name ${ename}"$'\n'
                result+="event${event_n}_counter ${counter}"$'\n'
                result+="event${event_n}_value ${eval_val}"$'\n'
            fi
            continue
        fi

        # Parse Metric rows: "| CPI  |  1.234  |"
        if [[ $in_metric_table -eq 1 ]] && [[ "$line" == *"|"* ]]; then
            local cleaned="${line//|/ }"
            read -ra _arr <<< "$cleaned"
            if [[ ${#_arr[@]} -ge 2 ]]; then
                local mname="${_arr[0]}"
                local mval="${_arr[1]}"
                # Normalize metric name
                mname="${mname// /_}"
                mname="${mname//\//_per_}"
                result+="metric_${mname,,} ${mval}"$'\n'
            fi
            continue
        fi
    done <<< "$text"

    echo "$result"
}

_strat_likwid_extract_value () {
    local line="$1"
    local val=""
    # Try pipe-delimited format first
    if [[ "$line" == *"|"* ]]; then
        local cleaned="${line//|/ }"
        read -ra _arr <<< "$cleaned"
        local i
        for ((i=${#_arr[@]}-1; i>=0; i--)); do
            if [[ "${_arr[$i]}" =~ ^[0-9] ]]; then
                val="${_arr[$i]}"
                break
            fi
        done
    elif [[ "$line" == *":"* ]]; then
        val="${line##*:}"
    else
        read -ra _arr <<< "$line"
        local i
        for ((i=${#_arr[@]}-1; i>=0; i--)); do
            if [[ "${_arr[$i]}" =~ ^[0-9] ]]; then
                val="${_arr[$i]}"
                break
            fi
        done
    fi
    val="${val#"${val%%[![:space:]]*}"}"
    val="${val%"${val##*[![:space:]]}"}"
    val="${val//,/}"
    echo "$val"
}
