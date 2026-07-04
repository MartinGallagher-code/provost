#!/bin/bash
## Name: vmstat
## Description: Extract fields from vmstat output with mapped column names
## Version: 2.0
## Priority: 25
## Sample: samples/vmstat/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=85
    # Detect vmstat header: line containing "procs" and "memory" and "cpu"
    [[ "$text" == *"procs"* ]] || return 1
    [[ "$text" == *"memory"* ]] || return 1
    [[ "$text" == *"cpu"* ]] || return 1
    return 0
}

strategy_extract () {
    local text="$1"
    local result=""

    # Find the abbreviated header line (r  b  swpd  free ...)
    local header_line=""

    # Find header line: the line with "r  b" at the start (abbreviated column names)
    while IFS= read -r _line; do
        if [[ "$_line" =~ ^[\ ]*r[\ ]+b[\ ] ]]; then
            header_line="$_line"
            break
        fi
    done <<< "$text"
    [[ -z "$header_line" ]] && return 0

    # Parse header columns using read (collapses whitespace naturally)
    local headers_arr=()
    read -ra headers_arr <<< "$header_line"

    # Process data lines (lines after the header that start with numbers)
    local row_num=0
    local found_header=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Skip category header line (procs ---memory--- etc)
        [[ "$line" == *"procs"* ]] && continue

        # Skip the abbreviated header line itself
        if [[ "$line" =~ ^[\ ]*r[\ ]+b[\ ] ]]; then
            found_header=1
            continue
        fi

        [[ $found_header -eq 0 ]] && continue

        row_num=$((row_num + 1))
        # Use read to collapse whitespace
        local vals_arr=()
        read -ra vals_arr <<< "$line"

        # Emit every sample row as an indexed record group (entry<N>.<field>) so
        # the capture tidy melt renders one row per sample. (Previously the first
        # row was unprefixed and later rows used row<N>., a mixed shape that could
        # not melt and welded every sample into one wide row.)
        local prefix="entry${row_num}."

        local i
        for ((i=0; i<${#headers_arr[@]}; i++)); do
            local abbr="${headers_arr[$i]}"
            local val="${vals_arr[$i]:-}"
            [[ -z "$val" ]] && continue
            local full_name
            full_name=$(_strat_vmstat_map_name "$abbr")
            result+="${prefix}${full_name} ${val}"$'\n'
        done
    done <<< "$text"

    [[ $row_num -gt 0 ]] && result+="total_entries ${row_num}"$'\n'
    echo "$result"
}

_strat_vmstat_map_name () {
    local abbr="$1"
    case "$abbr" in
        r)     echo "running" ;;
        b)     echo "blocked" ;;
        swpd)  echo "swapped" ;;
        free)  echo "free_memory" ;;
        buff)  echo "buffers" ;;
        cache) echo "cached" ;;
        si)    echo "swap_in" ;;
        so)    echo "swap_out" ;;
        bi)    echo "blocks_in" ;;
        bo)    echo "blocks_out" ;;
        in)    echo "interrupts" ;;
        cs)    echo "context_switches" ;;
        us)    echo "user_cpu" ;;
        sy)    echo "system_cpu" ;;
        id)    echo "idle_cpu" ;;
        wa)    echo "io_wait" ;;
        st)    echo "steal_time" ;;
        *)     echo "$abbr" ;;
    esac
}
