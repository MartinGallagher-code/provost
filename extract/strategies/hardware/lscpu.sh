#!/bin/bash
## Name: lscpu
## Description: Extract CPU topology and details from lscpu output
## Version: 1.0
## Priority: 15
## Sample: samples/lscpu/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90
    _is_json "$1" && return 1
    if [[ "$text" == *"lscpu"* ]]; then
        return 0
    fi
    if [[ "$text" == *"Architecture:"* ]] && [[ "$text" == *"CPU(s):"* ]]; then
        return 0
    fi
    if [[ "$text" == *"Thread(s) per core:"* ]] && [[ "$text" == *"Model name:"* ]]; then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local key=""
        local val=""

        # Extract key: value pairs
        if [[ "$line" == *":"* ]]; then
            key="${line%%:*}"
            val="${line#*:}"
            # Trim leading/trailing whitespace
            while [[ "$val" == " "* ]]; do val="${val# }"; done
            while [[ "$val" == *" " ]]; do val="${val% }"; done
            while [[ "$key" == " "* ]]; do key="${key# }"; done
            while [[ "$key" == *" " ]]; do key="${key% }"; done
        else
            continue
        fi

        case "$key" in
            "Architecture")
                result+="architecture ${val}"$'\n' ;;
            "CPU(s)")
                result+="cpus ${val}"$'\n' ;;
            "Thread(s) per core")
                result+="threads_per_core ${val}"$'\n' ;;
            "Core(s) per socket")
                result+="cores_per_socket ${val}"$'\n' ;;
            "Socket(s)")
                result+="sockets ${val}"$'\n' ;;
            "NUMA node(s)")
                result+="numa_nodes ${val}"$'\n' ;;
            "Model name")
                result+="model_name ${val}"$'\n' ;;
            "CPU MHz"|"CPU max MHz")
                if [[ "$key" == "CPU MHz" ]]; then
                    result+="cpu_mhz ${val}"$'\n'
                else
                    result+="cpu_max_mhz ${val}"$'\n'
                fi
                ;;
            "L1d cache")
                result+="l1d_cache ${val}"$'\n' ;;
            "L1i cache")
                result+="l1i_cache ${val}"$'\n' ;;
            "L2 cache")
                result+="l2_cache ${val}"$'\n' ;;
            "L3 cache")
                result+="l3_cache ${val}"$'\n' ;;
            "Flags")
                result+="flags ${val}"$'\n' ;;
            "Byte Order")
                result+="byte_order ${val}"$'\n' ;;
            "Vendor ID")
                result+="vendor_id ${val}"$'\n' ;;
            "CPU family")
                result+="cpu_family ${val}"$'\n' ;;
            "Model")
                result+="model ${val}"$'\n' ;;
            "Stepping")
                result+="stepping ${val}"$'\n' ;;
            "BogoMIPS")
                result+="bogomips ${val}"$'\n' ;;
        esac
    done <<< "$text"

    echo "$result"
}
