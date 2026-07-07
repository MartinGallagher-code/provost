#!/bin/bash
## Name: top-batch
## Description: top -b -n1 process table → one tidy row per process
## Version: 1.0
## Priority: 22
## Technique: yes
## Sample: samples/top-batch/basic.txt

# `top -b -n1` prints a summary block (top/Tasks/%Cpu(s)/MiB Mem/MiB Swap), a
# blank line, a "PID USER PR NI VIRT RES SHR S %CPU %MEM TIME+ COMMAND" header,
# then one row per process. Every process row begins with a numeric PID — that
# alone distinguishes it from the all-text summary and header lines, so we emit
# exactly one record per process.

_top_batch_is_row () {
    [[ "$1" =~ ^[0-9]+$ ]]
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    [[ "$text" == *"%Cpu(s)"* && "$text" == *"PID USER"* && "$text" == *"COMMAND"* ]] || return 1
    _STRATEGY_CONFIDENCE=86
    return 0
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line
    local toks
    while IFS= read -r line; do
        toks=(); read -ra toks <<< "$line"
        [[ ${#toks[@]} -ge 12 ]] || continue
        _top_batch_is_row "${toks[0]}" || continue
        local cmd="${toks[*]:11}"; cmd="${cmd// /_}"
        entry=$((entry + 1))
        result+="entry${entry}.pid ${toks[0]}"$'\n'
        result+="entry${entry}.user ${toks[1]}"$'\n'
        result+="entry${entry}.pr ${toks[2]}"$'\n'
        result+="entry${entry}.ni ${toks[3]}"$'\n'
        result+="entry${entry}.virt ${toks[4]}"$'\n'
        result+="entry${entry}.res ${toks[5]}"$'\n'
        result+="entry${entry}.shr ${toks[6]}"$'\n'
        result+="entry${entry}.s ${toks[7]}"$'\n'
        result+="entry${entry}.pct_cpu ${toks[8]}"$'\n'
        result+="entry${entry}.pct_mem ${toks[9]}"$'\n'
        result+="entry${entry}.time ${toks[10]}"$'\n'
        result+="entry${entry}.command ${cmd}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
