#!/bin/bash
## Name: proc-slabinfo
## Description: Extract per-cache stats from /proc/slabinfo output
## Version: 1.0
## Priority: 26
## Technique: yes
## Sample: samples/proc-slabinfo/basic.txt

# /proc/slabinfo starts with a `slabinfo - version: 2.1` line and a `# name ...`
# header, then one row per kmem cache:
#   kmalloc-8192  128  128  8192  4  8 : tunables 0 0 0 : slabdata 32 32 0
# We emit one record per cache, keeping the first six columns (name,
# active_objs, num_objs, objsize, objperslab, pagesperslab) and skipping the
# version and `#` header lines.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=86
    [[ "$text" == *"slabinfo - version:"* ]] && return 0
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" line n=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        [[ "$line" == "slabinfo - version:"* ]] && continue
        [[ "$line" == "#"* ]] && continue

        local -a f=()
        read -ra f <<< "$line"
        [[ ${#f[@]} -lt 6 ]] && continue

        n=$((n + 1))
        result+="entry${n}.name ${f[0]}"$'\n'
        result+="entry${n}.active_objs ${f[1]}"$'\n'
        result+="entry${n}.num_objs ${f[2]}"$'\n'
        result+="entry${n}.objsize ${f[3]}"$'\n'
        result+="entry${n}.objperslab ${f[4]}"$'\n'
        result+="entry${n}.pagesperslab ${f[5]}"$'\n'
    done <<< "$text"

    [[ $n -gt 0 ]] && result+="total_entries ${n}"$'\n'
    echo "$result"
}
