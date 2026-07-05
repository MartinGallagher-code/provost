#!/bin/bash
## Name: lammps
## Description: Extract thermodynamic and performance data from LAMMPS log output
## Version: 1.0
## Priority: 10
## Sample: samples/lammps/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0

    local hits=0
    [[ "$text" == *"LAMMPS"* ]] && hits=$((hits + 1))
    [[ "$text" == *"Step Temp"* || "$text" == *"Step        Temp"* ]] && hits=$((hits + 1))
    [[ "$text" == *"Loop time"* ]] && hits=$((hits + 1))
    [[ "$text" == *"Performance:"* ]] && hits=$((hits + 1))
    [[ "$text" == *"units"* ]] && hits=$((hits + 1))
    [[ "$text" == *"atom_style"* ]] && hits=$((hits + 1))
    [[ "$text" == *"Total wall time"* ]] && hits=$((hits + 1))

    if [[ $hits -ge 3 ]]; then
        _STRATEGY_CONFIDENCE=95
        return 0
    fi
    if [[ $hits -ge 2 ]] && [[ "$text" == *"LAMMPS"* ]]; then
        _STRATEGY_CONFIDENCE=85
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""

    # LAMMPS version
    while IFS= read -r line; do
        if [[ "$line" == *"LAMMPS ("* ]]; then
            local _after="${line#*LAMMPS (}"
            local _ver="${_after%%)*}"
            result+="lammps_version ${_ver}"$'\n'
            break
        fi
    done <<< "$text"

    # Parse thermo output table
    # Header: "Step Temp Press TotEng KinEng PotEng ..."
    # Data rows follow until "Loop time" or blank
    local in_thermo=0
    local -a thermo_cols=()
    local last_step="" last_temp="" last_press=""
    local last_toteng="" last_kineng="" last_poteng=""
    local num_thermo_rows=0

    while IFS= read -r line; do
        local trimmed="$line"
        while [[ "$trimmed" == " "* ]]; do trimmed="${trimmed# }"; done

        # Detect thermo header
        if [[ "$trimmed" =~ ^Step\ +Temp ]]; then
            in_thermo=1
            read -ra thermo_cols <<< "$trimmed"
            continue
        fi

        # End of thermo block
        if [[ $in_thermo -eq 1 ]]; then
            if [[ "$trimmed" == "Loop time"* || -z "$trimmed" || "$trimmed" == "WARNING"* ]]; then
                in_thermo=0
                continue
            fi

            # Parse data row
            if [[ "$trimmed" =~ ^[0-9] ]]; then
                num_thermo_rows=$((num_thermo_rows + 1))
                read -ra vals <<< "$trimmed"
                local i
                for i in "${!thermo_cols[@]}"; do
                    local col="${thermo_cols[$i]}"
                    local val="${vals[$i]}"
                    [[ -z "$val" ]] && continue
                    case "$col" in
                        Step)    last_step="$val" ;;
                        Temp)    last_temp="$val" ;;
                        Press)   last_press="$val" ;;
                        TotEng)  last_toteng="$val" ;;
                        KinEng)  last_kineng="$val" ;;
                        PotEng)  last_poteng="$val" ;;
                    esac
                done
                # Record first row as initial values
                if [[ $num_thermo_rows -eq 1 ]]; then
                    [[ -n "$last_step" ]] && result+="initial_step ${last_step}"$'\n'
                    [[ -n "$last_temp" ]] && result+="initial_temp ${last_temp}"$'\n'
                fi
                continue
            fi
        fi

        # Loop time: "Loop time of 12.345 on 4 procs for 1000 steps with 8000 atoms"
        if [[ "$trimmed" =~ ^Loop\ time\ of\ ([0-9.]+)\ on\ ([0-9]+)\ procs\ for\ ([0-9]+)\ steps\ with\ ([0-9]+)\ atoms ]]; then
            result+="loop_time ${BASH_REMATCH[1]}"$'\n'
            result+="num_procs ${BASH_REMATCH[2]}"$'\n'
            result+="num_steps ${BASH_REMATCH[3]}"$'\n'
            result+="num_atoms ${BASH_REMATCH[4]}"$'\n'
            continue
        fi

        # Performance: "Performance: 12.345 tau/day, 678.9 timesteps/s"
        if [[ "$trimmed" =~ ^Performance: ]]; then
            if [[ "$trimmed" =~ ([0-9.]+)\ +ns/day ]]; then
                result+="ns_per_day ${BASH_REMATCH[1]}"$'\n'
            fi
            if [[ "$trimmed" =~ ([0-9.]+)\ +tau/day ]]; then
                result+="tau_per_day ${BASH_REMATCH[1]}"$'\n'
            fi
            if [[ "$trimmed" =~ ([0-9.]+)\ +timesteps/s ]]; then
                result+="timesteps_per_s ${BASH_REMATCH[1]}"$'\n'
            fi
            continue
        fi

        # Total wall time
        if [[ "$trimmed" =~ ^Total\ wall\ time:\ +(.+) ]]; then
            result+="total_wall_time ${BASH_REMATCH[1]}"$'\n'
            continue
        fi
    done <<< "$text"

    # Report final thermo values
    [[ -n "$last_step" ]] && result+="final_step ${last_step}"$'\n'
    [[ -n "$last_temp" ]] && result+="final_temp ${last_temp}"$'\n'
    [[ -n "$last_press" ]] && result+="final_press ${last_press}"$'\n'
    [[ -n "$last_toteng" ]] && result+="total_energy ${last_toteng}"$'\n'
    [[ -n "$last_kineng" ]] && result+="kinetic_energy ${last_kineng}"$'\n'
    [[ -n "$last_poteng" ]] && result+="potential_energy ${last_poteng}"$'\n'
    [[ $num_thermo_rows -gt 0 ]] && result+="num_thermo_rows ${num_thermo_rows}"$'\n'

    echo "$result"
}
