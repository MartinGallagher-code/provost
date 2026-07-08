#!/bin/bash
## Name: spec-cpu
## Description: Extract benchmark scores from SPEC CPU 2017 text result output
## Version: 1.0
## Priority: 12
## Sample: samples/spec-cpu/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90
    # Must contain "SPEC CPU"
    [[ "$text" == *"SPEC CPU"* ]] || return 1
    # Must contain SPECrate or SPECspeed or benchmark table header
    if [[ "$text" == *"SPECrate"* || "$text" == *"SPECspeed"* ]]; then
        return 0
    fi
    if [[ "$text" == *"Benchmarks"* ]] && \
       [[ "$text" == *"Run Time"* ]] && \
       [[ "$text" == *"Rate"* ]]; then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local bench_num=0

    # Determine suite name from the title line
    local suite
    suite=$(_strat_spec_cpu_extract_suite "$text")
    [[ -n "$suite" ]] && result+="suite ${suite}"$'\n'

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Test Sponsor line
        if [[ "$line" == *"Test Sponsor"* ]]; then
            local val
            val=$(_strat_spec_cpu_after_colon "$line")
            [[ -n "$val" ]] && result+="sponsor ${val}"$'\n'
            continue
        fi

        # System line
        if [[ "$line" == *"System:"* ]] && [[ "$line" != *"Operating System"* ]]; then
            local val
            val=$(_strat_spec_cpu_after_colon "$line")
            [[ -n "$val" ]] && result+="system ${val}"$'\n'
            continue
        fi

        # Hardware Vendor
        if [[ "$line" == *"Hardware Vendor"* ]]; then
            local val
            val=$(_strat_spec_cpu_after_colon "$line")
            [[ -n "$val" ]] && result+="hardware_vendor ${val}"$'\n'
            continue
        fi

        # # of CPUs
        if [[ "$line" == *"# of CPUs"* ]]; then
            local val
            val=$(_strat_spec_cpu_after_colon "$line")
            [[ -n "$val" ]] && result+="cpus ${val}"$'\n'
            continue
        fi

        # Total Cores/Threads
        if [[ "$line" == *"Total Cores/Threads"* ]]; then
            local val
            val=$(_strat_spec_cpu_after_colon "$line")
            [[ -n "$val" ]] && result+="cores_threads ${val}"$'\n'
            continue
        fi

        # Base Copies
        if [[ "$line" == *"Base Copies"* ]]; then
            local val
            val=$(_strat_spec_cpu_after_colon "$line")
            [[ -n "$val" ]] && result+="base_copies ${val}"$'\n'
            continue
        fi

        # Peak Copies
        if [[ "$line" == *"Peak Copies"* ]]; then
            local val
            val=$(_strat_spec_cpu_after_colon "$line")
            [[ -n "$val" ]] && result+="peak_copies ${val}"$'\n'
            continue
        fi

        # Compiler
        if [[ "$line" == *"Compiler:"* ]]; then
            local val
            val=$(_strat_spec_cpu_after_colon "$line")
            [[ -n "$val" ]] && result+="compiler ${val}"$'\n'
            continue
        fi

        # Firmware
        if [[ "$line" == *"Firmware:"* ]]; then
            local val
            val=$(_strat_spec_cpu_after_colon "$line")
            [[ -n "$val" ]] && result+="firmware ${val}"$'\n'
            continue
        fi

        # Benchmark result lines: e.g. "500.perlbench_r   128      234       678 ..."
        # Pattern: starts with optional spaces, then a digit, then digits.name_r or digits.name_s
        if [[ "$line" =~ ^[\ ]*[0-9]+\.[a-zA-Z0-9_]+_[rs] ]]; then
            bench_num=$((bench_num + 1))
            # Use read to split on whitespace (collapses spaces naturally)
            read -ra _arr <<< "$line"
            local name="${_arr[0]}"
            local base_copies="${_arr[1]}"
            local base_runtime="${_arr[2]}"
            local base_rate="${_arr[3]}"
            local peak_copies="${_arr[4]}"
            local peak_runtime="${_arr[5]}"
            local peak_rate="${_arr[6]}"
            [[ -n "$name" ]] && result+="bench${bench_num}.name ${name}"$'\n'
            [[ -n "$base_copies" && "$base_copies" != "" ]] && result+="bench${bench_num}.base_copies ${base_copies}"$'\n'
            [[ -n "$base_runtime" && "$base_runtime" != "" ]] && result+="bench${bench_num}.base_runtime ${base_runtime}"$'\n'
            [[ -n "$base_rate" && "$base_rate" != "" ]] && result+="bench${bench_num}.base_rate ${base_rate}"$'\n'
            [[ -n "$peak_copies" && "$peak_copies" != "" ]] && result+="bench${bench_num}.peak_copies ${peak_copies}"$'\n'
            [[ -n "$peak_runtime" && "$peak_runtime" != "" ]] && result+="bench${bench_num}.peak_runtime ${peak_runtime}"$'\n'
            [[ -n "$peak_rate" && "$peak_rate" != "" ]] && result+="bench${bench_num}.peak_rate ${peak_rate}"$'\n'
            continue
        fi

        # SPECrate/SPECspeed summary lines
        # e.g. " Est. SPECrate2017_int_base             867"
        if [[ "$line" == *"SPECrate"* || "$line" == *"SPECspeed"* ]]; then
            _strat_spec_cpu_extract_summary_line "$line"
            continue
        fi

    done <<< "$text"

    echo "$result"
}

# Extract the suite name from the title line
_strat_spec_cpu_extract_suite () {
    local text="$1"
    local title_line=""
    while IFS= read -r _line; do
        if [[ "$_line" == *"SPEC CPU"* ]]; then
            title_line="$_line"
            break
        fi
    done <<< "$text"
    if [[ -z "$title_line" ]]; then
        return
    fi
    # Extract the result type, e.g. "Integer Rate Result" -> "Integer_Rate"
    # or "Floating Point Speed Result" -> "Floating_Point_Speed"
    local _after="${title_line#*SPEC CPU}"
    # Strip leading non-digit chars then digits then space
    _after="${_after#*[0-9]}"
    while [[ "$_after" =~ ^[0-9] ]]; do _after="${_after#?}"; done
    while [[ "$_after" == " "* ]]; do _after="${_after# }"; done
    # Remove " Result" and everything after
    local result_type="${_after%% Result*}"
    while [[ "$result_type" == *" " ]]; do result_type="${result_type% }"; done
    if [[ -n "$result_type" ]]; then
        echo "SPEC_CPU_2017_${result_type}"
    else
        echo "SPEC_CPU_2017"
    fi
}

# Extract value after the last colon on a line, trimmed and underscored
_strat_spec_cpu_after_colon () {
    local line="$1"
    local val="${line##*:}"
    while [[ "$val" == " "* ]]; do val="${val# }"; done
    while [[ "$val" == *" " ]]; do val="${val% }"; done
    echo "$val"
}

# Extract SPECrate/SPECspeed summary values
_strat_spec_cpu_extract_summary_line () {
    local line="$1"
    # Normalize: use read to collapse spaces
    read -ra _arr <<< "$line"
    local normalized="${_arr[*]}"

    # Get last word as metric value
    local metric_value="${_arr[${#_arr[@]}-1]}"

    if [[ "$normalized" == *"SPECrate2017_int_base"* ]]; then
        if [[ "$metric_value" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            result+="specrate_int_base ${metric_value}"$'\n'
        fi
    fi
    if [[ "$normalized" == *"SPECrate2017_int_peak"* ]]; then
        if [[ "$metric_value" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            result+="specrate_int_peak ${metric_value}"$'\n'
        fi
    fi
    if [[ "$normalized" == *"SPECrate2017_fp_base"* ]]; then
        if [[ "$metric_value" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            result+="specrate_fp_base ${metric_value}"$'\n'
        fi
    fi
    if [[ "$normalized" == *"SPECrate2017_fp_peak"* ]]; then
        if [[ "$metric_value" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            result+="specrate_fp_peak ${metric_value}"$'\n'
        fi
    fi
    if [[ "$normalized" == *"SPECspeed2017_int_base"* ]]; then
        if [[ "$metric_value" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            result+="specspeed_int_base ${metric_value}"$'\n'
        fi
    fi
    if [[ "$normalized" == *"SPECspeed2017_int_peak"* ]]; then
        if [[ "$metric_value" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            result+="specspeed_int_peak ${metric_value}"$'\n'
        fi
    fi
    if [[ "$normalized" == *"SPECspeed2017_fp_base"* ]]; then
        if [[ "$metric_value" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            result+="specspeed_fp_base ${metric_value}"$'\n'
        fi
    fi
    if [[ "$normalized" == *"SPECspeed2017_fp_peak"* ]]; then
        if [[ "$metric_value" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            result+="specspeed_fp_peak ${metric_value}"$'\n'
        fi
    fi
}
