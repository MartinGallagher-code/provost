#!/bin/bash
## Name: multipath-ll
## Description: Extract per-path rows from `multipath -ll` topology output
## Version: 1.0
## Priority: 27
## Sample: samples/multipath-ll/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    _is_json "$text" && return 1
    # `multipath -ll` is distinctive: a map line ending `dm-N ...`, a
    # `size=... features=... hwhandler=... wp=rw` line, and `policy='...'` groups.
    local has_wp=0 has_policy=0 has_hwhandler=0
    while IFS= read -r line; do
        [[ "$line" == *"wp=rw"* || "$line" == *"wp=ro"* ]] && has_wp=1
        [[ "$line" == *"policy='"* ]] && has_policy=1
        [[ "$line" == *"hwhandler='"* ]] && has_hwhandler=1
    done <<< "$text"
    if [[ $has_wp -eq 1 && $has_policy -eq 1 && $has_hwhandler -eq 1 ]]; then
        _STRATEGY_CONFIDENCE=88
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local entry=0
    while IFS= read -r line; do
        # Strip the leading tree drawing chars (spaces, |, `, -, +).
        local stripped="${line#"${line%%[!| \`+-]*}"}"
        read -ra f <<< "$stripped"
        # A leaf path row starts with an H:C:I:L tuple, e.g. `6:0:0:0 sdc 8:32 active ready running`
        [[ ${#f[@]} -ge 6 ]] || continue
        [[ "${f[0]}" =~ ^[0-9]+:[0-9]+:[0-9]+:[0-9]+$ ]] || continue

        entry=$((entry + 1))
        result+="entry${entry}.hcil ${f[0]}"$'\n'
        result+="entry${entry}.devnode ${f[1]}"$'\n'
        result+="entry${entry}.major_minor ${f[2]}"$'\n'
        result+="entry${entry}.dm_status ${f[3]}"$'\n'
        result+="entry${entry}.path_status ${f[4]}"$'\n'
        result+="entry${entry}.online ${f[5]}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
