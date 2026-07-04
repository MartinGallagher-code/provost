#!/bin/bash
## Name: lmbench
## Description: Extract system, processor, integer, context switch, communication, and memory metrics from lmbench summary output
## Version: 1.0
## Priority: 12
## Sample: samples/lmbench/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=85
    # Primary: spaced-out banner "L M B E N C H"
    if [[ "$text" == *"L M B E N C H"* ]]; then
        return 0
    fi
    # Secondary: "lmbench" keyword plus benchmark result markers
    if [[ "$text" == *[Ll][Mm][Bb][Ee][Nn][Cc][Hh]* ]]; then
        if [[ "$text" == *"microseconds"* ]]; then
            if [[ "$text" == *"smaller is better"* ]]; then
                return 0
            fi
        fi
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local section=""
    _lmbench_result=""

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Track which section we are in
        if [[ "$line" == *"Basic system parameters"* ]]; then
            section="system"
            continue
        fi
        if [[ "$line" == *"Processor, Processes"* ]]; then
            section="processor"
            continue
        fi
        if [[ "$line" == *"Basic integer operations"* ]]; then
            section="integer"
            continue
        fi
        if [[ "$line" == *"Context switching"* ]]; then
            section="context"
            continue
        fi
        if [[ "$line" == *"Communication latencies"* || "$line" =~ ^\*?Local\*?\ Communication ]]; then
            section="communication"
            continue
        fi
        if [[ "$line" == *"Memory latencies"* ]]; then
            section="memory"
            continue
        fi

        # Skip header/separator lines
        if [[ "$line" =~ ^-+$ ]]; then
            continue
        fi
        if [[ "$line" == "Host "* ]]; then
            continue
        fi
        # Skip column header lines (contain descriptive words but no data)
        local trimmed="$line"
        while [[ "$trimmed" == " "* || "$trimmed" == $'\t'* ]]; do trimmed="${trimmed#?}"; done
        if [[ "$trimmed" == "call"* || "$trimmed" == "ctxsw"* || "$trimmed" == "bit"* || "$trimmed" == "Mhz"* || "$trimmed" == "pages"* ]]; then
            continue
        fi
        # Skip WARNING lines
        if [[ "$line" == *"WARNING"* ]]; then
            continue
        fi

        # Parse data lines based on current section
        case "$section" in
            system)
                _strat_lmbench_parse_system "$line" && continue
                ;;
            processor)
                _strat_lmbench_parse_processor "$line" && continue
                ;;
            integer)
                _strat_lmbench_parse_integer "$line" && continue
                ;;
            context)
                _strat_lmbench_parse_context "$line" && continue
                ;;
            communication)
                _strat_lmbench_parse_communication "$line" && continue
                ;;
            memory)
                _strat_lmbench_parse_memory "$line" && continue
                ;;
        esac
    done <<< "$text"

    echo "$_lmbench_result"
}

# Shared accumulator for results (avoid subshell loss)
_lmbench_result=""

_strat_lmbench_parse_system () {
    local line="$1"
    # Data line: server1   Linux 5.4.0-8        x86_64-linux-gnu 3600    32   128  12.3    1
    # Fields: host(1) OS_name(2) OS_ver(3) Description(4) Mhz(5) tlb(6) cache(7) mem(8) scal(9)
    # Must start with a non-space hostname
    [[ "$line" =~ ^[a-zA-Z0-9] ]] || return 1
    read -ra _arr <<< "$line"
    local host="${_arr[0]}"
    local os="${_arr[1]} ${_arr[2]}"
    local mhz="${_arr[4]}"
    [[ -n "$host" ]] && _lmbench_result+="system.host ${host}"$'\n'
    [[ -n "$os" ]] && _lmbench_result+="system.os ${os}"$'\n'
    [[ -n "$mhz" ]] && _lmbench_result+="system.mhz ${mhz}"$'\n'
    return 0
}

_strat_lmbench_parse_processor () {
    local line="$1"
    [[ "$line" =~ ^[a-zA-Z0-9] ]] || return 1
    # server1   Linux 5.4.0-8 3600 0.27 0.35 1.23 2.45 7.89 0.45 2.34 234. 567. 1234
    # Fields after host+OS+Mhz: null_call null_io stat open_close select sig_inst sig_hndl fork exec sh
    local fields
    fields=$(_strat_lmbench_data_fields "$line")
    read -ra _arr <<< "$fields"
    local null_call="${_arr[1]}"
    local null_io="${_arr[2]}"
    local fork_proc="${_arr[8]}"
    local exec_proc="${_arr[9]}"
    local sh_proc="${_arr[10]}"
    [[ -n "$null_call" && "$null_call" != "" ]] && _lmbench_result+="processor.null_call_us ${null_call}"$'\n'
    [[ -n "$null_io" && "$null_io" != "" ]] && _lmbench_result+="processor.null_io_us ${null_io}"$'\n'
    [[ -n "$fork_proc" && "$fork_proc" != "" ]] && _lmbench_result+="processor.fork_proc_us ${fork_proc}"$'\n'
    [[ -n "$exec_proc" && "$exec_proc" != "" ]] && _lmbench_result+="processor.exec_proc_us ${exec_proc}"$'\n'
    [[ -n "$sh_proc" && "$sh_proc" != "" ]] && _lmbench_result+="processor.sh_proc_us ${sh_proc}"$'\n'
    return 0
}

_strat_lmbench_parse_integer () {
    local line="$1"
    [[ "$line" =~ ^[a-zA-Z0-9] ]] || return 1
    # server1   Linux 5.4.0-8  0.28   0.28   1.39   7.23   6.89
    # Fields after host+OS: bit add mul div mod
    local fields
    fields=$(_strat_lmbench_data_fields "$line")
    read -ra _arr <<< "$fields"
    local bit="${_arr[0]}"
    local add="${_arr[1]}"
    local mul="${_arr[2]}"
    local div="${_arr[3]}"
    local mod="${_arr[4]}"
    [[ -n "$bit" ]] && _lmbench_result+="integer.bit_ns ${bit}"$'\n'
    [[ -n "$add" ]] && _lmbench_result+="integer.add_ns ${add}"$'\n'
    [[ -n "$mul" ]] && _lmbench_result+="integer.mul_ns ${mul}"$'\n'
    [[ -n "$div" ]] && _lmbench_result+="integer.div_ns ${div}"$'\n'
    [[ -n "$mod" ]] && _lmbench_result+="integer.mod_ns ${mod}"$'\n'
    return 0
}

_strat_lmbench_parse_context () {
    local line="$1"
    [[ "$line" =~ ^[a-zA-Z0-9] ]] || return 1
    # server1   Linux 5.4.0-8   1.23   2.34   3.45  4.56   5.67    6.78    7.89
    # Fields: 2p/0K 2p/16K 2p/64K 8p/16K 8p/64K 16p/16K 16p/64K
    local fields
    fields=$(_strat_lmbench_data_fields "$line")
    read -ra _arr <<< "$fields"
    local v1="${_arr[0]}"
    local v2="${_arr[1]}"
    local v3="${_arr[2]}"
    [[ -n "$v1" ]] && _lmbench_result+="context.2p_0K_us ${v1}"$'\n'
    [[ -n "$v2" ]] && _lmbench_result+="context.2p_16K_us ${v2}"$'\n'
    [[ -n "$v3" ]] && _lmbench_result+="context.2p_64K_us ${v3}"$'\n'
    return 0
}

_strat_lmbench_parse_communication () {
    local line="$1"
    [[ "$line" =~ ^[a-zA-Z0-9] ]] || return 1
    # server1   Linux 5.4.0-8  1.23  4.56 5.67  8.90 12.3  10.2  15.4 23.5
    # Fields: 2p/0K_ctxsw Pipe AF_UNIX UDP RPC/UDP TCP RPC/TCP TCP_conn
    local fields
    fields=$(_strat_lmbench_data_fields "$line")
    read -ra _arr <<< "$fields"
    local pipe="${_arr[1]}"
    local af_unix="${_arr[2]}"
    local udp="${_arr[3]}"
    local tcp="${_arr[5]}"
    local tcp_conn="${_arr[7]}"
    [[ -n "$pipe" ]] && _lmbench_result+="communication.pipe_us ${pipe}"$'\n'
    [[ -n "$af_unix" ]] && _lmbench_result+="communication.af_unix_us ${af_unix}"$'\n'
    [[ -n "$udp" ]] && _lmbench_result+="communication.udp_us ${udp}"$'\n'
    [[ -n "$tcp" ]] && _lmbench_result+="communication.tcp_us ${tcp}"$'\n'
    [[ -n "$tcp_conn" ]] && _lmbench_result+="communication.tcp_conn_us ${tcp_conn}"$'\n'
    return 0
}

_strat_lmbench_parse_memory () {
    local line="$1"
    [[ "$line" =~ ^[a-zA-Z0-9] ]] || return 1
    # server1   Linux 5.4.0-8   3600   1.23    4.56      12.34       89.01
    # Fields after host+OS: Mhz L1$ L2$ Main_mem Rand_mem
    local fields
    fields=$(_strat_lmbench_data_fields "$line")
    read -ra _arr <<< "$fields"
    local l1="${_arr[1]}"
    local l2="${_arr[2]}"
    local main_mem="${_arr[3]}"
    local rand_mem="${_arr[4]}"
    [[ -n "$l1" ]] && _lmbench_result+="memory.l1_cache_ns ${l1}"$'\n'
    [[ -n "$l2" ]] && _lmbench_result+="memory.l2_cache_ns ${l2}"$'\n'
    [[ -n "$main_mem" ]] && _lmbench_result+="memory.main_mem_ns ${main_mem}"$'\n'
    [[ -n "$rand_mem" ]] && _lmbench_result+="memory.rand_mem_ns ${rand_mem}"$'\n'
    return 0
}

# Extract numeric data fields from a line, skipping the hostname and OS fields.
# lmbench data lines start with: hostname OS_name OS_version [data...]
# We skip the first 3 whitespace-delimited fields (host, OS name, OS version).
_strat_lmbench_data_fields () {
    read -ra _arr <<< "$1"
    local i result=""
    for ((i=3; i<${#_arr[@]}; i++)); do
        if [[ -n "$result" ]]; then
            result+=" "
        fi
        result+="${_arr[$i]}"
    done
    echo "$result"
}

# Extract Nth number from a line
_strat_lmbench_find_number () {
    read -ra _arr <<< "$1"
    echo "${_arr[$(($2 - 1))]}"
}
