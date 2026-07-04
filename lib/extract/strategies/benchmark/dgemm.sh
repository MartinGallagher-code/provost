#!/bin/bash
## Name: dgemm
## Description: Extract DGEMM dense matrix multiply benchmark results
## Version: 1.0
## Priority: 10
## Sample: samples/dgemm/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90
    if [[ "$text" == *[Dd][Gg][Ee][Mm][Mm]* ]]; then
        if [[ "$text" =~ [Gg][Ff][Ll][Oo][Pp][Ss]|[Gg]flop ]]; then
            return 0
        fi
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local run_num=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Header info: "DGEMM benchmark" or similar
        if [[ "$line" =~ ^[Dd][Gg][Ee][Mm][Mm] ]] && \
           ! [[ "$line" =~ [Gg][Ff][Ll][Oo][Pp][Ss]|[Gg]flop|[0-9] ]]; then
            continue
        fi

        # Result lines with matrix size and GFLOPS
        # Format varies: "N=1000  GFLOPS=45.67  Time=0.0438s"
        # or: "1000    45.67    0.0438"
        # or: "Size: 1000 x 1000  GFLOPS: 45.67  Time: 0.0438 s"

        # Pattern 1: key=value style
        if [[ "$line" =~ [Nn]=|[Ss]ize.*= ]] && \
           [[ "$line" =~ [Gg][Ff][Ll][Oo][Pp][Ss]|[Gg]flop ]]; then
            run_num=$((run_num + 1))
            local prefix=""
            if [[ $run_num -gt 1 ]]; then
                prefix="run${run_num}."
            fi
            local n gflops time_s
            n=$(_strat_dgemm_extract_kv "$line" '[Nn]')
            if [[ -z "$n" ]]; then
                n=$(_strat_dgemm_extract_kv "$line" '[Ss]ize')
            fi
            gflops=$(_strat_dgemm_extract_kv "$line" '[Gg][Ff][Ll][Oo][Pp][Ss]')
            time_s=$(_strat_dgemm_extract_kv "$line" '[Tt]ime')
            [[ -n "$n" ]] && result+="${prefix}matrix_size ${n}"$'\n'
            [[ -n "$gflops" ]] && result+="${prefix}gflops ${gflops}"$'\n'
            [[ -n "$time_s" ]] && result+="${prefix}time_seconds ${time_s}"$'\n'
            continue
        fi

        # Pattern 2: "key: value" style
        if [[ "$line" =~ [Gg][Ff][Ll][Oo][Pp][Ss]: ]]; then
            run_num=$((run_num + 1))
            local prefix=""
            if [[ $run_num -gt 1 ]]; then
                prefix="run${run_num}."
            fi
            local gflops
            local _after="${line##*GFLOPS:}"
            if [[ "$_after" == "$line" ]]; then
                _after="${line##*[Gg][Ff][Ll][Oo][Pp][Ss]:}"
            fi
            while [[ "$_after" == " "* ]]; do _after="${_after# }"; done
            read -ra _arr <<< "$_after"
            gflops="${_arr[0]}"
            [[ -n "$gflops" ]] && result+="${prefix}gflops ${gflops}"$'\n'
            continue
        fi

        # Pattern 3: tabular "Size  GFLOPS  Time" data rows
        if [[ "$line" =~ ^[[:space:]]*[0-9]+[[:space:]]+[0-9] ]]; then
            # Check if we're in a DGEMM table context
            read -ra _arr <<< "$line"
            local col1="${_arr[0]}"
            local col2="${_arr[1]}"
            local col3="${_arr[2]}"
            # col1 should be a reasonable matrix size (>= 100)
            if [[ -n "$col1" && -n "$col2" ]] && [[ "$col1" =~ ^[0-9]+$ ]]; then
                run_num=$((run_num + 1))
                local prefix=""
                if [[ $run_num -gt 1 ]]; then
                    prefix="run${run_num}."
                fi
                result+="${prefix}matrix_size ${col1}"$'\n'
                result+="${prefix}gflops ${col2}"$'\n'
                [[ -n "$col3" ]] && result+="${prefix}time_seconds ${col3}"$'\n'
            fi
            continue
        fi

        # Efficiency line: "Efficiency: 85.2%"
        if [[ "$line" == *[Ee]fficiency* ]]; then
            local _after="${line##*: }"
            while [[ "$_after" == " "* ]]; do _after="${_after# }"; done
            read -ra _arr <<< "$_after"
            local eff="${_arr[0]}"
            [[ -n "$eff" ]] && result+="efficiency ${eff}"$'\n'
        fi

        # Peak performance line: "Peak: 53.4 GFLOPS"
        if [[ "$line" == *[Pp]eak* ]] && [[ "$line" =~ [Gg][Ff][Ll][Oo][Pp][Ss]|[Gg]flop ]]; then
            local _after="${line##*: }"
            while [[ "$_after" == " "* ]]; do _after="${_after# }"; done
            read -ra _arr <<< "$_after"
            local peak="${_arr[0]}"
            [[ -n "$peak" ]] && result+="peak_gflops ${peak}"$'\n'
        fi
    done <<< "$text"

    echo "$result"
}

_strat_dgemm_extract_kv () {
    local line="$1"
    local key="$2"
    # Match key=value or key: value or key<space>value
    # key is a regex character class like [Nn] or [Gg][Ff]...
    local _re="${key}[=: ]*(.*)"
    if [[ "$line" =~ $_re ]]; then
        local _rest="${BASH_REMATCH[1]}"
        # Get first word
        read -ra _arr <<< "$_rest"
        local _val="${_arr[0]}"
        # Strip trailing 's' (e.g. "seconds" -> "second")
        _val="${_val%s}"
        echo "$_val"
    fi
}
