#!/bin/bash
## Name: iostat-d
## Description: iostat -d device throughput table → one tidy row per device
## Version: 1.0
## Priority: 22
## Technique: yes
## Sample: samples/iostat-d/basic.txt

# `iostat -d` prints a "Linux ..." banner, a blank line, a
# "Device tps kB_read/s kB_wrtn/s kB_read kB_wrtn" header, then one row per
# block device. We start emitting once the Device header is seen and take each
# following 6-field row as a device record (banner/header/blank are skipped).

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    [[ "$text" == *"Device"* && "$text" == *"tps"* \
       && "$text" == *"kB_read/s"* && "$text" == *"kB_wrtn/s"* ]] || return 1
    _STRATEGY_CONFIDENCE=86
    return 0
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line in_data=0
    local toks
    while IFS= read -r line; do
        toks=(); read -ra toks <<< "$line"
        if [[ ${#toks[@]} -ge 1 && "${toks[0]}" == "Device" ]]; then
            in_data=1
            continue
        fi
        [[ $in_data -eq 1 ]] || continue
        [[ ${#toks[@]} -ge 6 ]] || continue
        entry=$((entry + 1))
        result+="entry${entry}.device ${toks[0]}"$'\n'
        result+="entry${entry}.tps ${toks[1]}"$'\n'
        result+="entry${entry}.kb_read_s ${toks[2]}"$'\n'
        result+="entry${entry}.kb_wrtn_s ${toks[3]}"$'\n'
        result+="entry${entry}.kb_read ${toks[4]}"$'\n'
        result+="entry${entry}.kb_wrtn ${toks[5]}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
