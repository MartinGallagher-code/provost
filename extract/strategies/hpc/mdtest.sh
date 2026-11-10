#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: mdtest
## Description: mdtest (IOR 3.x/4.x) SUMMARY tables — one row per summary and operation (max/min/mean/std_dev, unit)
## Version: 1.0
## Priority: 20
## Sample: samples/mdtest/mdtest-4.0.0.txt

# mdtest prints its run header (started at, launch line, command line, Path,
# FS, Nodemap, task count), then a SUMMARY table per measure:
#
#   SUMMARY rate: (of 3 iterations)
#      Operation                      Max            Min           Mean        Std Dev
#      ---------                      ---            ---           ----        -------
#      Directory creation        :      34219.243      28941.334      31678.979       2157.819
#      ...
#      Tree removal              :        362.345        287.018        330.115         31.698
#   -- finished at 11/09/2026 10:47:57 --
#
# mdtest 3.x puts a ` :` after the padded operation name, 4.x does not; 4.x
# adds `Directory rename`; `SUMMARY time:` (seconds) follows at higher
# verbosity and in some versions. The generic fixed-width parse keeps the
# colon in the Max column and runs on into the "finished" line. One record per
# operation row: summary (rate / time), operation, max, min, mean, std_dev,
# and unit (ops/s for rate, s for time), with iterations from the SUMMARY line.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    _STRATEGY_CONFIDENCE_REASON="mdtest SUMMARY tables (Operation Max Min Mean Std Dev)"
    [[ "$text" == *mdtest* ]] || return 1
    [[ "$text" =~ SUMMARY\ [a-z]+:?\ ?\(of\ [0-9]+\ iterations\) ]] || return 1
    [[ "$text" =~ Operation[[:space:]]+Max[[:space:]]+Min[[:space:]]+Mean[[:space:]]+Std\ Dev ]] || return 1
    _STRATEGY_CONFIDENCE=92
    return 0
}

strategy_extract () {
    local text="$1" result="" entry=0 line summary="" iters="" op rest unit
    local -a t=()
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        if [[ "$line" =~ ^SUMMARY\ ([a-z]+):?\ ?\(of\ ([0-9]+)\ iterations\) ]]; then
            summary="${BASH_REMATCH[1]}"; iters="${BASH_REMATCH[2]}"
            case "$summary" in rate) unit="ops/s" ;; time) unit="s" ;; *) unit="" ;; esac
            continue
        fi
        [[ -n "$summary" ]] || continue
        [[ "$line" == "-- finished"* ]] && { summary=""; continue; }
        # an operation row: a name (letters and spaces), an optional ':', four numbers
        [[ "$line" =~ ^[[:space:]]+([A-Za-z][A-Za-z ]*[A-Za-z])[[:space:]]*:?[[:space:]]+([0-9][0-9.eE+-]*)[[:space:]]+([0-9][0-9.eE+-]*)[[:space:]]+([0-9][0-9.eE+-]*)[[:space:]]+([0-9][0-9.eE+-]*)[[:space:]]*$ ]] || continue
        op="${BASH_REMATCH[1]}"
        entry=$((entry + 1))
        result+="entry${entry}.summary ${summary}"$'\n'
        result+="entry${entry}.operation ${op}"$'\n'
        result+="entry${entry}.max ${BASH_REMATCH[2]}"$'\n'
        result+="entry${entry}.min ${BASH_REMATCH[3]}"$'\n'
        result+="entry${entry}.mean ${BASH_REMATCH[4]}"$'\n'
        result+="entry${entry}.std_dev ${BASH_REMATCH[5]}"$'\n'
        [[ -n "$unit" ]] && result+="entry${entry}.unit ${unit}"$'\n'
        result+="entry${entry}.iterations ${iters}"$'\n'
    done
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
