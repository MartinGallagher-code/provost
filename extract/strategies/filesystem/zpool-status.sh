#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: zpool-status
## Description: Extract the vdev/device table from `zpool status` output
## Version: 1.0
## Priority: 27
## Sample: samples/zpool-status/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    _is_json "$text" && return 1
    # `zpool status` has a distinctive `pool:` header, a `config:` line, and a
    # device table whose header is exactly `NAME STATE READ WRITE CKSUM`.
    local has_pool=0 has_config=0 has_hdr=0
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "$line" == *"pool:"* ]] && has_pool=1
        [[ "$line" == "config:"* ]] && has_config=1
        if [[ "$line" == *"NAME"* && "$line" == *"STATE"* \
              && "$line" == *"READ"* && "$line" == *"WRITE"* \
              && "$line" == *"CKSUM"* ]]; then
            has_hdr=1
        fi
    done
    if [[ $has_pool -eq 1 && $has_config -eq 1 && $has_hdr -eq 1 ]]; then
        _STRATEGY_CONFIDENCE=92
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local entry=0
    local in_table=0
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        # The `NAME STATE READ WRITE CKSUM` header opens the device table.
        if [[ "$line" == *"NAME"* && "$line" == *"STATE"* \
              && "$line" == *"READ"* && "$line" == *"WRITE"* \
              && "$line" == *"CKSUM"* ]]; then
            in_table=1
            continue
        fi
        [[ $in_table -eq 1 ]] || continue
        # A blank line ends the table (before the trailing `errors:` block).
        [[ -z "${line// }" ]] && break

        { _fr_tok "$line"; f=("${_FR_TOK[@]}"); }
        # Each device row is: name state read write cksum
        [[ ${#f[@]} -ge 5 ]] || continue

        entry=$((entry + 1))
        result+="entry${entry}.name ${f[0]}"$'\n'
        result+="entry${entry}.state ${f[1]}"$'\n'
        result+="entry${entry}.read ${f[2]}"$'\n'
        result+="entry${entry}.write ${f[3]}"$'\n'
        result+="entry${entry}.cksum ${f[4]}"$'\n'
    done
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
