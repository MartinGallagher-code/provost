#!/bin/bash
## Name: namd
## Description: Extract energy and performance data from NAMD molecular dynamics output
## Version: 1.0
## Priority: 10
## Sample: samples/namd/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0

    local hits=0
    [[ "$text" == *"NAMD"* ]] && hits=$((hits + 1))
    [[ "$text" == *"Info:"* ]] && hits=$((hits + 1))
    [[ "$text" == *"ENERGY:"* ]] && hits=$((hits + 1))
    [[ "$text" == *"WallClock:"* ]] && hits=$((hits + 1))
    [[ "$text" == *"TIMING:"* ]] && hits=$((hits + 1))
    [[ "$text" == *"ETITLE:"* ]] && hits=$((hits + 1))

    if [[ $hits -ge 3 ]]; then
        _STRATEGY_CONFIDENCE=95
        return 0
    fi
    if [[ $hits -ge 2 ]] && [[ "$text" == *"NAMD"* ]]; then
        _STRATEGY_CONFIDENCE=85
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""

    # Number of atoms: "Info: 24030 ATOMS"
    while IFS= read -r line; do
        if [[ "$line" =~ Info:\ +([0-9]+)\ +ATOMS ]]; then
            result+="num_atoms ${BASH_REMATCH[1]}"$'\n'
            break
        fi
    done <<< "$text"

    # Timestep: "Info: TIMESTEP               1"
    while IFS= read -r line; do
        if [[ "$line" =~ Info:\ +TIMESTEP\ +([0-9.]+) ]]; then
            result+="timestep ${BASH_REMATCH[1]}"$'\n'
            break
        fi
    done <<< "$text"

    # Parse ETITLE to get column names, then parse ENERGY: lines
    local -a energy_cols=()
    local last_ts="" last_bond="" last_angle="" last_dihed="" last_imprp=""
    local last_elect="" last_vdw="" last_total="" last_temp="" last_pressure=""
    local num_energy_rows=0

    while IFS= read -r line; do
        local trimmed="$line"
        while [[ "$trimmed" == " "* ]]; do trimmed="${trimmed# }"; done

        # ETITLE header
        if [[ "$trimmed" == "ETITLE:"* ]]; then
            local hdr="${trimmed#ETITLE:}"
            read -ra energy_cols <<< "$hdr"
            continue
        fi

        # ENERGY: data line
        if [[ "$trimmed" == "ENERGY:"* ]]; then
            num_energy_rows=$((num_energy_rows + 1))
            local data="${trimmed#ENERGY:}"
            read -ra vals <<< "$data"

            _strat_namd_map_energy_cols

            if [[ $num_energy_rows -eq 1 ]]; then
                [[ -n "$last_ts" ]] && result+="initial_ts ${last_ts}"$'\n'
                [[ -n "$last_temp" ]] && result+="initial_temp ${last_temp}"$'\n'
            fi
            continue
        fi

        # TIMING line: "TIMING: 5000  CPU: 45.23, 0.00904600/step  Wall: 50.12, 0.01002400/step ..."
        if [[ "$trimmed" =~ ^TIMING: ]]; then
            if [[ "$trimmed" =~ ([0-9.]+)/step\ +Wall:\ +([0-9.]+) ]]; then
                true  # captured but we want wall per step
            fi
            if [[ "$trimmed" =~ Wall:\ +([0-9.]+),\ +([0-9.]+)/step ]]; then
                result+="timing_per_step ${BASH_REMATCH[2]}"$'\n'
            fi
            continue
        fi

        # WallClock: "WallClock: 52.340000  CPUTime: 46.120000 ..."
        if [[ "$trimmed" =~ ^WallClock:\ +([0-9.]+) ]]; then
            result+="wallclock ${BASH_REMATCH[1]}"$'\n'
            continue
        fi
    done <<< "$text"

    # Report final energy values
    [[ -n "$last_ts" ]] && result+="ts ${last_ts}"$'\n'
    [[ -n "$last_bond" ]] && result+="bond ${last_bond}"$'\n'
    [[ -n "$last_angle" ]] && result+="angle ${last_angle}"$'\n'
    [[ -n "$last_dihed" ]] && result+="dihed ${last_dihed}"$'\n'
    [[ -n "$last_imprp" ]] && result+="imprp ${last_imprp}"$'\n'
    [[ -n "$last_elect" ]] && result+="elect ${last_elect}"$'\n'
    [[ -n "$last_vdw" ]] && result+="vdw ${last_vdw}"$'\n'
    [[ -n "$last_total" ]] && result+="total ${last_total}"$'\n'
    [[ -n "$last_temp" ]] && result+="temp ${last_temp}"$'\n'
    [[ -n "$last_pressure" ]] && result+="pressure ${last_pressure}"$'\n'
    [[ $num_energy_rows -gt 0 ]] && result+="num_energy_rows ${num_energy_rows}"$'\n'

    echo "$result"
}

# Helper: map ETITLE columns to values from an ENERGY: line
# Uses energy_cols[] and vals[] from caller scope
_strat_namd_map_energy_cols () {
    local i
    for i in "${!energy_cols[@]}"; do
        local col="${energy_cols[$i]}"
        local val="${vals[$i]}"
        [[ -z "$val" ]] && continue
        case "$col" in
            TS)       last_ts="$val" ;;
            BOND)     last_bond="$val" ;;
            ANGLE)    last_angle="$val" ;;
            DIHED)    last_dihed="$val" ;;
            IMPRP)    last_imprp="$val" ;;
            ELECT)    last_elect="$val" ;;
            VDW)      last_vdw="$val" ;;
            TOTAL)    last_total="$val" ;;
            TEMP)     last_temp="$val" ;;
            PRESSURE) last_pressure="$val" ;;
        esac
    done
}
