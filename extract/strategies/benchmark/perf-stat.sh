#!/bin/bash
## Name: perf-stat
## Description: Extract performance counters from perf stat output
## Version: 1.0
## Priority: 20
## Sample: samples/perf-stat/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=85
    # Detect "Performance counter stats" header
    if [[ "$text" == *"Performance counter stats"* ]]; then
        return 0
    fi
    # Or detect typical counter lines: number + cycles/instructions pattern
    local cycles_count=0
    while IFS= read -r _line; do
        if [[ "$_line" == *"cycles"* || "$_line" == *"instructions"* ]]; then
            cycles_count=$((cycles_count + 1))
        fi
    done <<< "$text"
    [[ $cycles_count -ge 2 ]]
}

strategy_extract () {
    local text="$1"
    local result=""

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Skip header and empty/comment lines
        [[ "$line" == *"Performance counter stats"* ]] && continue

        # Match counter lines: "  1,234,567      cycles   # ..."
        if [[ "$line" =~ ^[[:space:]]*[0-9,]+[[:space:]]+[a-z] ]]; then
            local count name
            count=$(_strat_perf_stat_extract_count "$line")
            name=$(_strat_perf_stat_extract_name "$line")
            [[ -z "$count" || -z "$name" ]] && continue
            result+="${name} ${count}"$'\n'
            continue
        fi

        # Match time lines: "  0.385432100 seconds time elapsed"
        if [[ "$line" =~ ^[[:space:]]*[0-9]+\.[0-9]+[[:space:]]+"seconds" ]]; then
            local time_val time_type
            time_val=$(_strat_perf_stat_extract_time_val "$line")
            time_type=$(_strat_perf_stat_extract_time_type "$line")
            [[ -z "$time_val" || -z "$time_type" ]] && continue
            result+="${time_type} ${time_val}"$'\n'
        fi
    done <<< "$text"

    echo "$result"
}

_strat_perf_stat_extract_count () {
    local line="$1"
    # Extract the numeric count, removing commas
    while [[ "$line" == " "* ]]; do line="${line# }"; done
    read -ra _arr <<< "$line"
    local count="${_arr[0]}"
    echo "${count//,/}"
}

_strat_perf_stat_extract_name () {
    local line="$1"
    # Extract the counter name (second word after the count)
    while [[ "$line" == " "* ]]; do line="${line# }"; done
    read -ra _arr <<< "$line"
    local name="${_arr[1]}"
    echo "${name//-/_}"
}

_strat_perf_stat_extract_time_val () {
    local line="$1"
    while [[ "$line" == " "* ]]; do line="${line# }"; done
    read -ra _arr <<< "$line"
    echo "${_arr[0]}"
}

_strat_perf_stat_extract_time_type () {
    local line="$1"
    # "0.385 seconds time elapsed" -> "time_elapsed"
    # "0.234 seconds user" -> "user"
    # "0.150 seconds sys" -> "sys"
    while [[ "$line" == " "* ]]; do line="${line# }"; done
    read -ra _arr <<< "$line"
    # Build words from index 2 onwards (skip number and "seconds")
    local words=""
    local i
    for ((i=2; i<${#_arr[@]}; i++)); do
        if [[ -n "$words" ]]; then
            words+="_"
        fi
        words+="${_arr[$i]}"
    done
    # Map common patterns
    case "$words" in
        time_elapsed) echo "time_elapsed" ;;
        user) echo "seconds_user" ;;
        sys) echo "seconds_sys" ;;
        *) echo "$words" ;;
    esac
}
