#!/bin/bash
## Name: sockperf
## Description: Extract latency, throughput, and percentile data from sockperf benchmark output
## Version: 1.0
## Priority: 12
## Sample: samples/sockperf/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90
    # Must contain "sockperf" marker
    [[ "$text" == *"sockperf"* ]] || return 1
    # Must also contain one of the key result markers
    if [[ "$text" == *"avg-latency"* || "$text" == *"MsgPerSec"* || "$text" == *"Latency is"* ]]; then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Server IP/PORT/protocol: [ 0] IP = 192.168.1.100       PORT = 11111 # TCP
        if [[ "$line" =~ ^\[[\ 0-9]+\]\ IP ]]; then
            local ip port proto
            ip=$(_strat_sockperf_extract_after "$line" "IP = ")
            port=$(_strat_sockperf_extract_after "$line" "PORT = ")
            proto=$(_strat_sockperf_extract_proto "$line")
            [[ -n "$ip" ]] && result+="server_ip ${ip}"$'\n'
            [[ -n "$port" ]] && result+="server_port ${port}"$'\n'
            [[ -n "$proto" ]] && result+="protocol ${proto}"$'\n'
            continue
        fi

        # Total Run: RunTime=10.000 sec; Parallels=1; MsgPerSec=48763; TotalMsgs=487631
        if [[ "$line" == *"[Total Run]"* ]]; then
            local runtime parallels mps totmsgs
            runtime=$(_strat_sockperf_kv "$line" "RunTime")
            parallels=$(_strat_sockperf_kv "$line" "Parallels")
            mps=$(_strat_sockperf_kv "$line" "MsgPerSec")
            totmsgs=$(_strat_sockperf_kv "$line" "TotalMsgs")
            [[ -n "$runtime" ]] && result+="runtime_sec ${runtime}"$'\n'
            [[ -n "$parallels" ]] && result+="parallels ${parallels}"$'\n'
            [[ -n "$mps" ]] && result+="msg_per_sec ${mps}"$'\n'
            [[ -n "$totmsgs" ]] && result+="total_messages ${totmsgs}"$'\n'
            continue
        fi

        # Valid Duration: SentMessages=466423; ReceivedMessages=466423
        if [[ "$line" == *"[Valid Duration]"* ]]; then
            local sent recv
            sent=$(_strat_sockperf_kv "$line" "SentMessages")
            recv=$(_strat_sockperf_kv "$line" "ReceivedMessages")
            [[ -n "$sent" ]] && result+="sent_messages ${sent}"$'\n'
            [[ -n "$recv" ]] && result+="received_messages ${recv}"$'\n'
            continue
        fi

        # avg-latency=10.147 (std-dev=1.234, mean-deviation=0.891)
        if [[ "$line" == *"avg-latency="* ]]; then
            local avg stddev
            avg=$(_strat_sockperf_kv "$line" "avg-latency")
            # Extract std-dev: after "std-dev=" up to comma or closing paren
            local _after_std="${line#*std-dev=}"
            stddev="${_after_std%%[,)]*}"
            [[ -n "$avg" ]] && result+="avg_latency_usec ${avg}"$'\n'
            [[ -n "$stddev" ]] && result+="std_dev_usec ${stddev}"$'\n'
            continue
        fi

        # dropped messages = 0; # duplicated messages = 0; # out-of-order messages = 0
        if [[ "$line" == *"# dropped messages"* ]]; then
            local dropped duped ooo
            local _after_drop="${line#*# dropped messages = }"
            dropped="${_after_drop%%[;]*}"
            local _after_dup="${line#*# duplicated messages = }"
            duped="${_after_dup%%[;]*}"
            local _after_ooo="${line#*# out-of-order messages = }"
            ooo="${_after_ooo%%[;]*}"
            [[ -n "$dropped" ]] && result+="dropped_messages ${dropped}"$'\n'
            [[ -n "$duped" ]] && result+="duplicated_messages ${duped}"$'\n'
            [[ -n "$ooo" ]] && result+="out_of_order_messages ${ooo}"$'\n'
            continue
        fi

        # Percentile 99.000 =  15.432 usec
        if [[ "$line" == *"Percentile"* ]]; then
            local pname pval
            pname=$(_strat_sockperf_percentile_name "$line")
            # Extract value after "="
            local _after_eq="${line#*= }"
            while [[ "$_after_eq" == " "* ]]; do _after_eq="${_after_eq# }"; done
            read -ra _arr <<< "$_after_eq"
            pval="${_arr[0]}"
            [[ -n "$pname" && -n "$pval" ]] && result+="${pname} ${pval}"$'\n'
            continue
        fi

    done <<< "$text"

    echo "$result"
}

# Extract value after "Key=" from a line with semicolon-delimited key=value pairs
_strat_sockperf_kv () {
    local line="$1"
    local key="$2"
    local _after="${line#*${key}=}"
    local val="${_after%%[ ;]*}"
    echo "$val"
}

# Extract value after a given prefix, trimming trailing whitespace
_strat_sockperf_extract_after () {
    local line="$1"
    local prefix="$2"
    local _after="${line#*${prefix}}"
    read -ra _arr <<< "$_after"
    echo "${_arr[0]}"
}

# Extract protocol from comment at end of line (# TCP or # UDP)
_strat_sockperf_extract_proto () {
    local line="$1"
    if [[ "$line" == *"# TCP"* ]]; then
        echo "TCP"
    elif [[ "$line" == *"# UDP"* ]]; then
        echo "UDP"
    fi
}

# Convert percentile number to field name: 50.000 -> p50_usec, 99.900 -> p99_9_usec
_strat_sockperf_percentile_name () {
    local line="$1"
    # Find the number after "Percentile"
    local _after="${line#*Percentile }"
    while [[ "$_after" == " "* ]]; do _after="${_after# }"; done
    read -ra _arr <<< "$_after"
    local pnum="${_arr[0]}"
    # Map common percentiles to clean field names
    case "$pnum" in
        50.000)  echo "p50_usec" ;;
        75.000)  echo "p75_usec" ;;
        90.000)  echo "p90_usec" ;;
        95.000)  echo "p95_usec" ;;
        99.000)  echo "p99_usec" ;;
        99.500)  echo "p99_5_usec" ;;
        99.900)  echo "p99_9_usec" ;;
        99.990)  echo "p99_99_usec" ;;
        99.999)  echo "p99_999_usec" ;;
        *)
            # Generic: replace dots with underscores
            local clean="${pnum//./_}"
            # Strip trailing zeros after underscore
            while [[ "$clean" == *"_0" ]]; do clean="${clean%_0}"; done
            while [[ "$clean" == *0 && "$clean" == *_* ]]; do
                local last="${clean##*_}"
                if [[ "$last" == *0 && "$last" != "0" ]]; then
                    clean="${clean%0}"
                else
                    break
                fi
            done
            echo "p${clean}_usec"
            ;;
    esac
}
