#!/bin/bash
## Name: ycsb
## Description: Extract throughput, latency, and operation metrics from Yahoo! Cloud Serving Benchmark (YCSB) output
## Version: 1.0
## Priority: 12
## Sample: samples/ycsb/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90
    # Must have [OVERALL] with Throughput and at least one operation section
    [[ "$text" == *"[OVERALL]"* ]] || return 1
    [[ "$text" == *"Throughput(ops/sec)"* ]] || return 1
    if [[ "$text" == *"[READ]"* || "$text" == *"[UPDATE]"* || "$text" == *"[INSERT]"* ]]; then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # YCSB lines: [SECTION], MetricName, Value
        if [[ "$line" == "["* ]]; then
            local section metric value fieldname

            section=$(_strat_ycsb_get_section "$line")
            metric=$(_strat_ycsb_get_metric "$line")
            value=$(_strat_ycsb_get_value "$line")

            [[ -z "$section" || -z "$metric" || -z "$value" ]] && continue

            fieldname=$(_strat_ycsb_build_fieldname "$section" "$metric")
            [[ -n "$fieldname" ]] && result+="${fieldname} ${value}"$'\n'
        fi
    done <<< "$text"

    echo "$result"
}

_strat_ycsb_get_section () {
    local line="$1"
    # Extract text between [ and ]
    local section="${line#*\[}"
    section="${section%%\]*}"
    # Lowercase
    echo "$section" | tr '[:upper:]' '[:lower:]'
}

_strat_ycsb_get_metric () {
    local line="$1"
    # After first "], " get the metric name (second CSV field)
    local rest="${line#*], }"
    local metric="${rest%%,*}"
    # Trim leading/trailing spaces
    while [[ "$metric" == " "* ]]; do metric="${metric# }"; done
    while [[ "$metric" == *" " ]]; do metric="${metric% }"; done
    echo "$metric"
}

_strat_ycsb_get_value () {
    local line="$1"
    # Get everything after the second comma
    local rest="${line#*], }"
    local after_metric="${rest#*, }"
    # Trim spaces
    while [[ "$after_metric" == " "* ]]; do after_metric="${after_metric# }"; done
    while [[ "$after_metric" == *" " ]]; do after_metric="${after_metric% }"; done
    echo "$after_metric"
}

_strat_ycsb_build_fieldname () {
    local section="$1"
    local metric="$2"

    # Remove parenthesized units: RunTime(ms) -> RunTime, AverageLatency(us) -> AverageLatency
    local clean="${metric%%(*}"
    # Remove trailing spaces from stripping parens
    while [[ "$clean" == *" " ]]; do clean="${clean% }"; done

    # Handle special metrics
    case "$metric" in
        Return=*)
            # Skip Return=OK lines
            return
            ;;
    esac

    # Replace specific metric names to match expected field names
    local fname=""
    case "$clean" in
        RunTime)         fname="runtime_ms" ;;
        Throughput)      fname="throughput_ops_per_sec" ;;
        Operations)      fname="operations" ;;
        AverageLatency)  fname="avg_latency_us" ;;
        MinLatency)      fname="min_latency_us" ;;
        MaxLatency)      fname="max_latency_us" ;;
        95thPercentileLatency) fname="p95_latency_us" ;;
        99thPercentileLatency) fname="p99_latency_us" ;;
        Count)           fname="count" ;;
        Time)            fname="time_ms" ;;
        *)
            # Generic: replace spaces with underscores, lowercase
            fname="${clean// /_}"
            fname=$(echo "$fname" | tr '[:upper:]' '[:lower:]')
            ;;
    esac

    [[ -z "$fname" ]] && return

    echo "${section}.${fname}"
}
