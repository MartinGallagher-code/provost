#!/bin/bash
## Name: pgbench
## Description: Extract PostgreSQL benchmark results from pgbench output
## Version: 1.0
## Priority: 12
## Sample: samples/pgbench/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90
    if [[ "$text" == *"pgbench"* ]] && \
       [[ "$text" == *"tps"* ]]; then
        return 0
    fi
    if [[ "$text" == *"transaction type"* ]] && \
       [[ "$text" == *"latency average"* ]]; then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        case "$line" in
            *"transaction type:"*)
                local val="${line#*transaction type:}"
                while [[ "$val" == " "* ]]; do val="${val# }"; done
                result+="transaction_type ${val}"$'\n' ;;
            *"scaling factor:"*)
                result+="scaling_factor $(_strat_pgbench_extract_colon "$line")"$'\n' ;;
            *"query mode:"*)
                result+="query_mode $(_strat_pgbench_extract_colon "$line")"$'\n' ;;
            *"number of clients:"*)
                result+="number_of_clients $(_strat_pgbench_extract_colon "$line")"$'\n' ;;
            *"number of threads:"*)
                result+="number_of_threads $(_strat_pgbench_extract_colon "$line")"$'\n' ;;
            *"maximum number of tries:"*)
                result+="max_tries $(_strat_pgbench_extract_colon "$line")"$'\n' ;;
            *"number of transactions actually processed:"*)
                local val
                val=$(_strat_pgbench_extract_colon "$line")
                read -ra _arr <<< "$val"
                result+="number_of_transactions ${_arr[0]}"$'\n' ;;
            *"number of failed transactions:"*)
                local val
                val=$(_strat_pgbench_extract_colon "$line")
                read -ra _arr <<< "$val"
                result+="failed_transactions ${_arr[0]}"$'\n' ;;
            *"tps = "*"(including connections establishing)"*)
                local tps="${line#*tps = }"
                read -ra _arr <<< "$tps"
                tps="${_arr[0]}"
                [[ -n "$tps" ]] && result+="tps_including_connections ${tps}"$'\n'
                ;;
            *"tps = "*"(without initial connection time)"*)
                local tps="${line#*tps = }"
                read -ra _arr <<< "$tps"
                tps="${_arr[0]}"
                [[ -n "$tps" ]] && result+="tps_excluding_connections ${tps}"$'\n'
                ;;
            *"latency average"*)
                result+="latency_average $(_strat_pgbench_extract_equals "$line")"$'\n' ;;
            *"latency stddev"*)
                result+="latency_stddev $(_strat_pgbench_extract_equals "$line")"$'\n' ;;
            *"initial connection time"*)
                result+="initial_connection_time $(_strat_pgbench_extract_equals "$line")"$'\n' ;;
        esac
    done <<< "$text"

    echo "$result"
}

_strat_pgbench_extract_colon () {
    local line="$1"
    local val="${line#*: }"
    if [[ "$val" == "$line" ]]; then
        val="${line#*:}"
        while [[ "$val" == " "* ]]; do val="${val# }"; done
    fi
    echo "$val"
}

_strat_pgbench_extract_equals () {
    local line="$1"
    local val="${line#*= }"
    if [[ "$val" == "$line" ]]; then
        val="${line#*=}"
        while [[ "$val" == " "* ]]; do val="${val# }"; done
    fi
    echo "$val"
}
