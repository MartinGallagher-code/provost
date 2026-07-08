#!/bin/bash
## Name: coremark
## Description: Extract CoreMark benchmark scores and configuration
## Version: 1.0
## Priority: 10
## Sample: samples/coremark/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=95
    if [[ "$text" == *"CoreMark"* ]]; then
        if [[ "$text" =~ Iterations/Sec|CoreMark\ Size|CoreMark\ 1\.0 ]]; then
            return 0
        fi
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # CoreMark Size: "CoreMark Size    : 666"
        if [[ "$line" == *"CoreMark Size"* ]]; then
            local val="${line##*: }"
            while [[ "$val" == " "* ]]; do val="${val# }"; done
            [[ -n "$val" ]] && result+="coremark_size ${val}"$'\n'
            continue
        fi

        # Total ticks: "Total ticks      : 12345"
        if [[ "$line" == *"Total ticks"* ]]; then
            local val="${line##*: }"
            while [[ "$val" == " "* ]]; do val="${val# }"; done
            [[ -n "$val" ]] && result+="total_ticks ${val}"$'\n'
            continue
        fi

        # Total time (secs): "Total time (secs): 12.345678"
        if [[ "$line" == *"Total time (secs)"* ]]; then
            local val="${line##*: }"
            while [[ "$val" == " "* ]]; do val="${val# }"; done
            [[ -n "$val" ]] && result+="total_time_secs ${val}"$'\n'
            continue
        fi

        # Iterations/Sec: "Iterations/Sec   : 25000.000000"
        if [[ "$line" == *"Iterations/Sec"* ]]; then
            local val="${line##*: }"
            while [[ "$val" == " "* ]]; do val="${val# }"; done
            [[ -n "$val" ]] && result+="iterations_per_sec ${val}"$'\n'
            continue
        fi

        # Iterations: "Iterations       : 300000"
        if [[ "$line" == "Iterations"* ]] && \
           [[ "$line" != *"Iterations/Sec"* ]]; then
            local val="${line##*: }"
            while [[ "$val" == " "* ]]; do val="${val# }"; done
            [[ -n "$val" ]] && result+="iterations ${val}"$'\n'
            continue
        fi

        # Compiler version: "Compiler version : GCC10.2.0"
        if [[ "$line" == *"Compiler version"* ]]; then
            local val="${line##*: }"
            while [[ "$val" == " "* ]]; do val="${val# }"; done
            [[ -n "$val" ]] && result+="compiler_version ${val}"$'\n'
            continue
        fi

        # Compiler flags: "Compiler flags   : -O2 -march=native"
        if [[ "$line" == *"Compiler flags"* ]]; then
            local val="${line##*: }"
            while [[ "$val" == " "* ]]; do val="${val# }"; done
            [[ -n "$val" ]] && result+="compiler_flags ${val}"$'\n'
            continue
        fi

        # Parallel execution: "Parallel PThreads : 4"
        if [[ "$line" == *"Parallel"* ]]; then
            local val="${line##*: }"
            while [[ "$val" == " "* ]]; do val="${val# }"; done
            [[ -n "$val" ]] && result+="parallel_threads ${val}"$'\n'
            continue
        fi

        # Seed values: "seed_volatile : 0x0"
        if [[ "$line" == *"seed"* ]]; then
            local key="${line%%:*}"
            # Trim trailing spaces
            while [[ "$key" == *" " ]]; do key="${key% }"; done
            key="${key// /_}"
            local val="${line##*: }"
            while [[ "$val" == " "* ]]; do val="${val# }"; done
            [[ -n "$key" && -n "$val" ]] && result+="${key} ${val}"$'\n'
            continue
        fi

        # CoreMark/MHz: often in a results summary line
        if [[ "$line" == *"CoreMark"*"MHz"* ]]; then
            local val="${line##*: }"
            while [[ "$val" == " "* ]]; do val="${val# }"; done
            read -ra _arr <<< "$val"
            val="${_arr[0]}"
            [[ -n "$val" ]] && result+="coremark_per_mhz ${val}"$'\n'
            continue
        fi
    done <<< "$text"

    echo "$result"
}
