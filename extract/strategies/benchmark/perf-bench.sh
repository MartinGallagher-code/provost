#!/bin/bash
## Name: perf-bench
## Description: Extract perf bench kernel benchmark results
## Version: 1.0
## Priority: 12
## Sample: samples/perf-bench/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=85

    # Reject perf stat output (different strategy)
    if [[ "$text" == *"Performance counter stats"* ]]; then
        return 1
    fi
    if [[ "$text" == *"perf stat"* ]]; then
        return 1
    fi

    # Detect "Running" + "benchmark" pattern
    local has_running=0
    if [[ "$text" =~ (^|$'\n')#?\ *Running.*benchmark ]]; then
        has_running=1
    fi

    # Detect benchmark metric lines
    local has_metrics=0
    if [[ "$text" == *"ops/sec"* || "$text" == *"usecs/op"* || "$text" == *"GB/sec"* ]]; then
        has_metrics=1
    fi

    # Need both running header AND metrics, or just running header with "# Running" pattern
    if [[ $has_running -eq 1 && $has_metrics -eq 1 ]]; then
        return 0
    fi

    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local current_bench=""

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Track current sub-benchmark from "# Running '<name>' benchmark:" lines
        # Must contain single-quoted name to avoid matching "# Running with N threads..."
        if [[ "$line" =~ ^#[[:space:]]*Running\ \' ]]; then
            current_bench=$(_strat_perf_bench_parse_bench_name "$line")
            continue
        fi

        # Skip other comment lines
        if [[ "$line" == "#"* ]]; then
            continue
        fi

        # Total time line: "     Total time: 5.123 [sec]"
        if [[ "$line" == *"Total time:"* ]]; then
            local time_val
            time_val=$(_strat_perf_bench_extract_total_time "$line")
            if [[ -n "$time_val" && -n "$current_bench" ]]; then
                result+="${current_bench}.total_time_sec ${time_val}"$'\n'
            fi
            continue
        fi

        # usecs/op line: "       5.123456 usecs/op"
        if [[ "$line" == *"usecs/op"* ]]; then
            local val
            val=$(_strat_perf_bench_extract_number "$line")
            if [[ -n "$val" && -n "$current_bench" ]]; then
                result+="${current_bench}.usecs_per_op ${val}"$'\n'
            fi
            continue
        fi

        # ops/sec line: "         195180 ops/sec"
        if [[ "$line" == *"ops/sec"* && "$line" != *"Averaged"* ]]; then
            local val
            val=$(_strat_perf_bench_extract_number "$line")
            if [[ -n "$val" && -n "$current_bench" ]]; then
                result+="${current_bench}.ops_per_sec ${val}"$'\n'
            fi
            continue
        fi

        # GB/sec line: "       8.901234 GB/sec"
        if [[ "$line" == *"GB/sec"* && "$line" != *"Averaged"* ]]; then
            local val
            val=$(_strat_perf_bench_extract_number "$line")
            if [[ -n "$val" && -n "$current_bench" ]]; then
                result+="${current_bench}.throughput_GB_per_sec ${val}"$'\n'
            fi
            continue
        fi

        # Averaged line: "Averaged 234567 operations/sec (+- 0.12%), total secs = 10"
        if [[ "$line" == "Averaged"* ]]; then
            local val
            val=$(_strat_perf_bench_extract_averaged_ops "$line")
            if [[ -n "$val" && -n "$current_bench" ]]; then
                result+="${current_bench}.avg_ops_per_sec ${val}"$'\n'
            fi
            continue
        fi

    done <<< "$text"

    echo "$result"
}

# Parse sub-benchmark name from "# Running 'sched/pipe' benchmark:" line
# Converts slashes to underscores: sched/pipe -> sched_pipe
_strat_perf_bench_parse_bench_name () {
    local line="$1"
    # Extract text between single quotes
    local after="${line#*\'}"
    local name="${after%%\'*}"
    # Convert / to _
    echo "${name//\//_}"
}

# Extract total time value from "     Total time: 5.123 [sec]"
_strat_perf_bench_extract_total_time () {
    local line="$1"
    local after="${line#*Total time:}"
    while [[ "$after" == " "* ]]; do after="${after# }"; done
    read -ra _arr <<< "$after"
    echo "${_arr[0]}"
}

# Extract leading number from a line like "       5.123456 usecs/op"
_strat_perf_bench_extract_number () {
    local line="$1"
    while [[ "$line" == " "* ]]; do line="${line# }"; done
    read -ra _arr <<< "$line"
    echo "${_arr[0]}"
}

# Extract averaged ops/sec from "Averaged 234567 operations/sec ..."
_strat_perf_bench_extract_averaged_ops () {
    local line="$1"
    read -ra _arr <<< "$line"
    echo "${_arr[1]}"
}
