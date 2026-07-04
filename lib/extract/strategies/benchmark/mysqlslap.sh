#!/bin/bash
## Name: mysqlslap
## Description: Extract benchmark metrics from mysqlslap output (avg/min/max seconds, clients, queries per client)
## Version: 1.0
## Priority: 12
## Sample: samples/mysqlslap/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=85
    # Must have "Benchmark" on its own line and the avg seconds metric
    if [[ "$text" == *$'\n'"Benchmark"$'\n'* || "$text" == "Benchmark"$'\n'* ]] &&
       [[ "$text" == *"Average number of seconds to run all queries"* ]]; then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local run_num=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Count benchmark sections
        if [[ "$line" == "Benchmark" ]]; then
            run_num=$((run_num + 1))
            continue
        fi

        local prefix=""
        if [[ $run_num -gt 1 ]]; then
            prefix="run${run_num}."
        fi

        # Average number of seconds to run all queries: 0.345 seconds
        if [[ "$line" == *"Average number of seconds to run all queries"* ]]; then
            local val
            val=$(_strat_mysqlslap_extract_number "$line")
            [[ -n "$val" ]] && result+="${prefix}avg_seconds ${val}"$'\n'
            continue
        fi

        # Minimum number of seconds to run all queries: 0.312 seconds
        if [[ "$line" == *"Minimum number of seconds to run all queries"* ]]; then
            local val
            val=$(_strat_mysqlslap_extract_number "$line")
            [[ -n "$val" ]] && result+="${prefix}min_seconds ${val}"$'\n'
            continue
        fi

        # Maximum number of seconds to run all queries: 0.389 seconds
        if [[ "$line" == *"Maximum number of seconds to run all queries"* ]]; then
            local val
            val=$(_strat_mysqlslap_extract_number "$line")
            [[ -n "$val" ]] && result+="${prefix}max_seconds ${val}"$'\n'
            continue
        fi

        # Number of clients running queries: 50
        if [[ "$line" == *"Number of clients running queries"* ]]; then
            local val
            val=$(_strat_mysqlslap_extract_number "$line")
            [[ -n "$val" ]] && result+="${prefix}clients ${val}"$'\n'
            continue
        fi

        # Average number of queries per client: 100
        if [[ "$line" == *"Average number of queries per client"* ]]; then
            local val
            val=$(_strat_mysqlslap_extract_number "$line")
            [[ -n "$val" ]] && result+="${prefix}queries_per_client ${val}"$'\n'
            continue
        fi

    done <<< "$text"

    echo "$result"
}

_strat_mysqlslap_extract_number () {
    # Extract the numeric value after the last colon
    # "	Average number of seconds to run all queries: 0.345 seconds" -> "0.345"
    local line="$1"
    local after="${line##*: }"
    if [[ "$after" == "$line" ]]; then
        after="${line##*:}"
        while [[ "$after" == " "* ]]; do after="${after# }"; done
    fi
    read -ra _arr <<< "$after"
    echo "${_arr[0]}"
}
