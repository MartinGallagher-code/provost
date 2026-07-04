#!/bin/bash
## Name: sysbench
## Description: Extract benchmark results from sysbench (cpu, memory, oltp modes)
## Version: 1.0
## Priority: 10
## Sample: samples/sysbench/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90
    if [[ "$text" == *"sysbench"* ]]; then
        if [[ "$text" == *"Number of threads:"* ]] || \
           [[ "$text" == *"General statistics:"* ]] || \
           [[ "$text" == *"Latency"* || "$text" == *"events per second"* ]]; then
            return 0
        fi
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""

    # Extract thread count: "Number of threads: 4"
    local threads_line=""
    while IFS= read -r _line; do
        if [[ "$_line" == *"Number of threads:"* ]]; then
            threads_line="$_line"
            break
        fi
    done <<< "$text"
    if [[ -n "$threads_line" ]]; then
        local threads="${threads_line##*: }"
        while [[ "$threads" == " "* ]]; do threads="${threads# }"; done
        [[ -n "$threads" ]] && result+="threads ${threads}"$'\n'
    fi

    # Detect mode and extract mode-specific fields
    if [[ "$text" == *"CPU speed:"* ]]; then
        result+="mode cpu"$'\n'
        local _cpu_out
        _cpu_out=$(_strat_sysbench_extract_cpu "$text")
        [[ -n "$_cpu_out" ]] && result+="${_cpu_out}"$'\n'
    elif [[ "$text" == *"SQL statistics:"* || "$text" == *"OLTP"* ]]; then
        result+="mode oltp"$'\n'
        local _oltp_out
        _oltp_out=$(_strat_sysbench_extract_oltp "$text")
        [[ -n "$_oltp_out" ]] && result+="${_oltp_out}"$'\n'
    elif [[ "$text" == *"Total operations:"* ]]; then
        result+="mode memory"$'\n'
        local _mem_out
        _mem_out=$(_strat_sysbench_extract_memory "$text")
        [[ -n "$_mem_out" ]] && result+="${_mem_out}"$'\n'
    fi

    # Common: General statistics
    local total_time="" total_events=""
    while IFS= read -r _line; do
        if [[ "$_line" == *"total time:"* && -z "$total_time" ]]; then
            total_time="${_line##*: }"
            while [[ "$total_time" == " "* ]]; do total_time="${total_time# }"; done
        fi
        if [[ "$_line" == *"total number of events:"* && -z "$total_events" ]]; then
            total_events="${_line##*: }"
            while [[ "$total_events" == " "* ]]; do total_events="${total_events# }"; done
        fi
    done <<< "$text"
    [[ -n "$total_time" ]] && result+="total_time ${total_time}"$'\n'
    [[ -n "$total_events" ]] && result+="total_events ${total_events}"$'\n'

    # Common: Latency - get last min/avg/max lines (latency section is at the end)
    local lat_min="" lat_avg="" lat_max="" lat_p95=""
    while IFS= read -r _line; do
        if [[ "$_line" == *"min:"* ]]; then
            lat_min="${_line##*: }"
            while [[ "$lat_min" == " "* ]]; do lat_min="${lat_min# }"; done
        fi
        if [[ "$_line" == *"avg:"* ]]; then
            lat_avg="${_line##*: }"
            while [[ "$lat_avg" == " "* ]]; do lat_avg="${lat_avg# }"; done
        fi
        if [[ "$_line" == *"max:"* ]]; then
            lat_max="${_line##*: }"
            while [[ "$lat_max" == " "* ]]; do lat_max="${lat_max# }"; done
        fi
        if [[ "$_line" == *"95th percentile:"* && -z "$lat_p95" ]]; then
            lat_p95="${_line##*: }"
            while [[ "$lat_p95" == " "* ]]; do lat_p95="${lat_p95# }"; done
        fi
    done <<< "$text"
    [[ -n "$lat_min" ]] && result+="latency_min ${lat_min}"$'\n'
    [[ -n "$lat_avg" ]] && result+="latency_avg ${lat_avg}"$'\n'
    [[ -n "$lat_max" ]] && result+="latency_max ${lat_max}"$'\n'
    [[ -n "$lat_p95" ]] && result+="latency_p95 ${lat_p95}"$'\n'

    echo "$result"
}

_strat_sysbench_extract_cpu () {
    local text="$1"
    local result=""
    local events_per_sec=""
    while IFS= read -r _line; do
        if [[ "$_line" == *"events per second:"* && -z "$events_per_sec" ]]; then
            events_per_sec="${_line##*: }"
            while [[ "$events_per_sec" == " "* ]]; do events_per_sec="${events_per_sec# }"; done
        fi
    done <<< "$text"
    [[ -n "$events_per_sec" ]] && result+="cpu_events_per_sec ${events_per_sec}"$'\n'
    echo "$result"
}

_strat_sysbench_extract_memory () {
    local text="$1"
    local result=""
    # "Total operations: 104857600 (12345678.90 per second)"
    local ops_line=""
    while IFS= read -r _line; do
        if [[ "$_line" == *"Total operations:"* && -z "$ops_line" ]]; then
            ops_line="$_line"
        fi
    done <<< "$text"
    if [[ -n "$ops_line" ]]; then
        local _after="${ops_line##*: }"
        while [[ "$_after" == " "* ]]; do _after="${_after# }"; done
        read -ra _arr <<< "$_after"
        local total_ops="${_arr[0]}"
        # Extract ops_per_sec from parenthetical: "(12345678.90 per second)"
        local _paren="${ops_line#*(}"
        local ops_per_sec="${_paren%% per second*}"
        [[ -n "$total_ops" ]] && result+="total_operations ${total_ops}"$'\n'
        [[ -n "$ops_per_sec" ]] && result+="operations_per_sec ${ops_per_sec}"$'\n'
    fi
    # Transfer rate: "102400.00 MiB transferred (12345.67 MiB/sec)"
    local transfer_line=""
    while IFS= read -r _line; do
        if [[ "$_line" == *"MiB transferred"* && -z "$transfer_line" ]]; then
            transfer_line="$_line"
        fi
    done <<< "$text"
    if [[ -n "$transfer_line" ]]; then
        read -ra _arr <<< "$transfer_line"
        local transferred="${_arr[0]}"
        # Extract rate from parenthetical
        local _paren="${transfer_line#*(}"
        local rate="${_paren%% MiB/sec*}"
        [[ -n "$transferred" ]] && result+="transferred_MiB ${transferred}"$'\n'
        [[ -n "$rate" ]] && result+="transfer_rate_MiB_per_sec ${rate}"$'\n'
    fi
    echo "$result"
}

_strat_sysbench_extract_oltp () {
    local text="$1"
    local result=""
    # SQL statistics section
    local transactions="" queries="" tps="" qps=""
    local read_q="" write_q="" other_q=""
    while IFS= read -r _line; do
        if [[ "$_line" == *"transactions:"* && -z "$transactions" ]]; then
            local _after="${_line##*: }"
            while [[ "$_after" == " "* ]]; do _after="${_after# }"; done
            read -ra _arr <<< "$_after"
            transactions="${_arr[0]}"
            # Extract TPS from parenthetical
            local _paren="${_line#*(}"
            tps="${_paren%% per sec*}"
        fi
        if [[ "$_line" == *"queries:"* && -z "$queries" ]]; then
            local _after="${_line##*: }"
            while [[ "$_after" == " "* ]]; do _after="${_after# }"; done
            read -ra _arr <<< "$_after"
            queries="${_arr[0]}"
            # Extract QPS from parenthetical
            local _paren="${_line#*(}"
            qps="${_paren%% per sec*}"
        fi
        if [[ "$_line" == *"read:"* && -z "$read_q" ]]; then
            read_q="${_line##*: }"
            while [[ "$read_q" == " "* ]]; do read_q="${read_q# }"; done
        fi
        if [[ "$_line" == *"write:"* && -z "$write_q" ]]; then
            write_q="${_line##*: }"
            while [[ "$write_q" == " "* ]]; do write_q="${write_q# }"; done
        fi
        if [[ "$_line" == *"other:"* && -z "$other_q" ]]; then
            other_q="${_line##*: }"
            while [[ "$other_q" == " "* ]]; do other_q="${other_q# }"; done
        fi
    done <<< "$text"
    [[ -n "$transactions" ]] && result+="transactions ${transactions}"$'\n'
    [[ -n "$queries" ]] && result+="queries ${queries}"$'\n'

    [[ -n "$tps" ]] && result+="transactions_per_sec ${tps}"$'\n'
    [[ -n "$qps" ]] && result+="queries_per_sec ${qps}"$'\n'

    [[ -n "$read_q" ]] && result+="read_queries ${read_q}"$'\n'
    [[ -n "$write_q" ]] && result+="write_queries ${write_q}"$'\n'
    [[ -n "$other_q" ]] && result+="other_queries ${other_q}"$'\n'

    echo "$result"
}
