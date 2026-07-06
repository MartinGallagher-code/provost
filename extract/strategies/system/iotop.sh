#!/bin/bash
## Name: iotop
## Description: Extract per-process records from iotop output (tid, prio, user, io rates, command)
## Version: 1.0
## Priority: 20
## Sample: samples/iotop/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    # Distinctive signature: iotop's DISK READ/WRITE totals plus its
    # "TID PRIO USER ... IO> COMMAND" process header.
    if [[ "$text" == *"Total DISK READ"* ]] \
       && [[ "$text" == *"TID"* ]] \
       && [[ "$text" == *"DISK WRITE"* ]]; then
        _STRATEGY_CONFIDENCE=88
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0
    local in_table=0
    while IFS= read -r line; do
        [[ -z "${line//[[:space:]]/}" ]] && continue

        # Skip the Total/Current summary lines.
        [[ "$line" == *"DISK READ"*"|"* ]] && continue
        [[ "$line" == *"DISK WRITE"*"|"* ]] && continue

        # The TID/PRIO/... row is the process-table header.
        if [[ "$line" == *"TID"* ]] && [[ "$line" == *"COMMAND"* ]]; then
            in_table=1
            continue
        fi
        [[ $in_table -eq 0 ]] && continue

        local v
        read -ra v <<< "$line"
        [[ ${#v[@]} -lt 11 ]] && continue
        [[ "${v[0]}" =~ ^[0-9]+$ ]] || continue

        # Columns: TID PRIO USER  <read val+unit>  <write val+unit>
        #          <swapin val+unit>  <io val+unit>  COMMAND...
        local command="${v[*]:11}"

        entry=$((entry + 1))
        result+="entry${entry}.tid ${v[0]}"$'\n'
        result+="entry${entry}.prio ${v[1]}"$'\n'
        result+="entry${entry}.user ${v[2]}"$'\n'
        result+="entry${entry}.disk_read ${v[3]} ${v[4]}"$'\n'
        result+="entry${entry}.disk_write ${v[5]} ${v[6]}"$'\n'
        result+="entry${entry}.swapin ${v[7]} ${v[8]}"$'\n'
        result+="entry${entry}.io ${v[9]} ${v[10]}"$'\n'
        result+="entry${entry}.command ${command}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
