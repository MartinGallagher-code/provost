#!/bin/bash
## Name: amber
## Description: Extract thermodynamic and performance data from AMBER molecular dynamics output
## Version: 1.0
## Priority: 10
## Sample: samples/amber/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0

    local hits=0
    [[ "$text" == *"AMBER"* || "$text" == *"Amber"* ]] && hits=$((hits + 1))
    [[ "$text" == *"sander"* || "$text" == *"pmemd"* ]] && hits=$((hits + 1))
    [[ "$text" == *"NSTEP"* ]] && hits=$((hits + 1))
    [[ "$text" == *"EAMBER"* ]] && hits=$((hits + 1))
    [[ "$text" == *"Etot"* ]] && hits=$((hits + 1))
    [[ "$text" == *"EKtot"* ]] && hits=$((hits + 1))
    [[ "$text" == *"EPtot"* ]] && hits=$((hits + 1))
    [[ "$text" == *"NATOM"* ]] && hits=$((hits + 1))

    if [[ $hits -ge 4 ]]; then
        _STRATEGY_CONFIDENCE=95
        return 0
    fi
    if [[ $hits -ge 2 ]] && [[ "$text" == *"AMBER"* || "$text" == *"Amber"* ]]; then
        _STRATEGY_CONFIDENCE=85
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""

    # Number of atoms
    local num_atoms=""
    num_atoms=$(_strat_amber_extract_field "$text" "NATOM" "=")
    [[ -n "$num_atoms" ]] && result+="num_atoms ${num_atoms}"$'\n'

    # Parse NSTEP blocks
    local last_nstep="" last_temp="" last_press=""
    local last_etot="" last_ektot="" last_eptot=""
    local last_density="" last_volume="" last_time=""
    local num_thermo_blocks=0
    local in_averages=0

    while IFS= read -r line; do
        local trimmed="$line"
        while [[ "$trimmed" == " "* ]]; do trimmed="${trimmed# }"; done

        # Detect averages section - skip it
        if [[ "$trimmed" == *"A V E R A G E S"* ]]; then
            in_averages=1
            continue
        fi

        # NSTEP line: "NSTEP =   1000   TIME(PS) =   2.000  TEMP(K) = 300.12  PRESS =  -45.2"
        if [[ "$trimmed" =~ ^NSTEP ]]; then
            if [[ $in_averages -eq 1 ]]; then
                continue
            fi
            num_thermo_blocks=$((num_thermo_blocks + 1))
            last_nstep=$(_strat_amber_grab_value "$trimmed" "NSTEP")
            last_time=$(_strat_amber_grab_value "$trimmed" "TIME(PS)")
            last_temp=$(_strat_amber_grab_value "$trimmed" "TEMP(K)")
            last_press=$(_strat_amber_grab_value "$trimmed" "PRESS")
            if [[ $num_thermo_blocks -eq 1 ]]; then
                [[ -n "$last_nstep" ]] && result+="initial_nstep ${last_nstep}"$'\n'
                [[ -n "$last_temp" ]] && result+="initial_temp ${last_temp}"$'\n'
            fi
            continue
        fi

        # Energy line: "Etot   =  -75432.1234  EKtot   =   17234.5678  EPtot   =  -92666.6912"
        if [[ "$trimmed" =~ ^Etot ]]; then
            if [[ $in_averages -eq 1 ]]; then
                continue
            fi
            last_etot=$(_strat_amber_grab_value "$trimmed" "Etot")
            last_ektot=$(_strat_amber_grab_value "$trimmed" "EKtot")
            last_eptot=$(_strat_amber_grab_value "$trimmed" "EPtot")
            continue
        fi

        # Density line
        if [[ "$trimmed" =~ Density ]]; then
            if [[ $in_averages -eq 1 ]]; then
                continue
            fi
            last_density=$(_strat_amber_grab_value "$trimmed" "Density")
            continue
        fi

        # Volume line
        if [[ "$trimmed" =~ VOLUME ]]; then
            if [[ $in_averages -eq 1 ]]; then
                continue
            fi
            last_volume=$(_strat_amber_grab_value "$trimmed" "VOLUME")
            continue
        fi

        # Wall time: "Master Total wall time:         125.00 seconds"
        if [[ "$trimmed" =~ Total\ wall\ time:\ +([0-9.]+) ]]; then
            result+="wallclock ${BASH_REMATCH[1]}"$'\n'
            continue
        fi

    done <<< "$text"

    # Report final thermo values
    [[ -n "$last_nstep" ]] && result+="nstep ${last_nstep}"$'\n'
    [[ -n "$last_time" ]] && result+="time ${last_time}"$'\n'
    [[ -n "$last_temp" ]] && result+="temp ${last_temp}"$'\n'
    [[ -n "$last_press" ]] && result+="press ${last_press}"$'\n'
    [[ -n "$last_etot" ]] && result+="etot ${last_etot}"$'\n'
    [[ -n "$last_ektot" ]] && result+="ektot ${last_ektot}"$'\n'
    [[ -n "$last_eptot" ]] && result+="eptot ${last_eptot}"$'\n'
    [[ -n "$last_density" ]] && result+="density ${last_density}"$'\n'
    [[ -n "$last_volume" ]] && result+="volume ${last_volume}"$'\n'
    [[ $num_thermo_blocks -gt 0 ]] && result+="num_thermo_blocks ${num_thermo_blocks}"$'\n'

    echo "$result"
}

# Helper: extract a simple "KEY = VALUE" field from NATOM-style lines
_strat_amber_extract_field () {
    local text="$1"
    local key="$2"
    local sep="$3"
    while IFS= read -r line; do
        if [[ "$line" == *"$key"* ]]; then
            local after="${line#*${key}}"
            after="${after#*${sep}}"
            while [[ "$after" == " "* ]]; do after="${after# }"; done
            local val="${after%% *}"
            val="${val%%$'\r'}"
            [[ -n "$val" ]] && echo "$val" && return 0
        fi
    done <<< "$text"
}

# Helper: grab value from "KEY = VALUE  KEY2 = VALUE2" style AMBER thermo lines
_strat_amber_grab_value () {
    local line="$1"
    local key="$2"
    if [[ "$line" == *"$key"* ]]; then
        local after="${line#*${key}}"
        after="${after#*=}"
        while [[ "$after" == " "* ]]; do after="${after# }"; done
        local val="${after%% *}"
        val="${val%%$'\r'}"
        echo "$val"
    fi
}
