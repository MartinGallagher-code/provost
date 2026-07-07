#!/bin/bash
## Name: pcp-pmstat
## Description: pcp pmstat columnar samples → one tidy row per sample
## Version: 1.0
## Priority: 22
## Technique: yes
## Sample: samples/pcp-pmstat/basic.txt

# `pcp pmstat` prints two header rows (a grouped banner "loadavg memory swap io
# system cpu" and a column header "1 min swpd free buff cache si so bi bo in cs
# us sy id"), then one sample row per interval. Every sample row's first field is
# a decimal load average (e.g. "0.42") — that distinguishes it from both header
# rows, so we emit exactly one record per sample.

_pcp_pmstat_is_row () {
    [[ "$1" =~ ^[0-9]+\.[0-9]+$ ]]
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    [[ "$text" == *"loadavg"* && "$text" == *"swpd"* && "$text" == *"cache"* \
       && "$text" == *"swap"* ]] || return 1
    _STRATEGY_CONFIDENCE=86
    return 0
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line
    local toks
    while IFS= read -r line; do
        toks=(); read -ra toks <<< "$line"
        [[ ${#toks[@]} -ge 14 ]] || continue
        _pcp_pmstat_is_row "${toks[0]}" || continue
        entry=$((entry + 1))
        result+="entry${entry}.load1 ${toks[0]}"$'\n'
        result+="entry${entry}.swpd ${toks[1]}"$'\n'
        result+="entry${entry}.free ${toks[2]}"$'\n'
        result+="entry${entry}.buff ${toks[3]}"$'\n'
        result+="entry${entry}.cache ${toks[4]}"$'\n'
        result+="entry${entry}.si ${toks[5]}"$'\n'
        result+="entry${entry}.so ${toks[6]}"$'\n'
        result+="entry${entry}.bi ${toks[7]}"$'\n'
        result+="entry${entry}.bo ${toks[8]}"$'\n'
        result+="entry${entry}.in ${toks[9]}"$'\n'
        result+="entry${entry}.cs ${toks[10]}"$'\n'
        result+="entry${entry}.us ${toks[11]}"$'\n'
        result+="entry${entry}.sy ${toks[12]}"$'\n'
        result+="entry${entry}.id ${toks[13]}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
