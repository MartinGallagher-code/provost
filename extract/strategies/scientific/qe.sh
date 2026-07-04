#!/bin/bash
## Name: qe
## Description: Extract energies, forces, and convergence data from Quantum ESPRESSO (pw.x) output
## Version: 1.0
## Priority: 10
## Sample: samples/qe/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0

    local hits=0
    [[ "$text" == *"Quantum ESPRESSO"* ]] && hits=$((hits + 1))
    [[ "$text" == *"PWSCF"* ]] && hits=$((hits + 1))
    [[ "$text" == *"Program PWSCF"* ]] && hits=$((hits + 1))
    [[ "$text" == *"total energy"* ]] && hits=$((hits + 1))
    [[ "$text" == *"Forces acting"* ]] && hits=$((hits + 1))
    [[ "$text" == *"kinetic-energy cutoff"* ]] && hits=$((hits + 1))
    [[ "$text" == *"convergence has been achieved"* ]] && hits=$((hits + 1))

    if [[ $hits -ge 3 ]]; then
        _STRATEGY_CONFIDENCE=95
        return 0
    fi
    if [[ $hits -ge 2 ]] && [[ "$text" == *"PWSCF"* || "$text" == *"Quantum ESPRESSO"* ]]; then
        _STRATEGY_CONFIDENCE=85
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""

    local total_energy_ry=""
    local total_force=""
    local pressure_kbar=""
    local num_atoms=""
    local num_electrons=""
    local ecutwfc=""
    local ecutrho=""
    local k_points=""
    local elapsed_time=""
    local convergence_achieved="no"

    while IFS= read -r line; do
        local trimmed="$line"
        while [[ "$trimmed" == " "* ]]; do trimmed="${trimmed# }"; done

        # Total energy: "!    total energy              =     -31.80883014 Ry"
        if [[ "$trimmed" =~ ^!\ +total\ energy\ +=\ +([^ ]+)\ +Ry ]]; then
            total_energy_ry="${BASH_REMATCH[1]}"
            continue
        fi

        # Total force: "Total force =     0.000000     Total SCF correction ..."
        if [[ "$trimmed" =~ ^Total\ force\ =\ +([0-9.]+) ]]; then
            total_force="${BASH_REMATCH[1]}"
            continue
        fi

        # Pressure: "(kbar)     P=      -3.45"
        if [[ "$trimmed" =~ \(kbar\)\ +P=\ +([^ ]+) ]]; then
            pressure_kbar="${BASH_REMATCH[1]}"
            continue
        fi

        # Number of atoms: "number of atoms/cell      =            2"
        if [[ "$trimmed" =~ ^number\ of\ atoms/cell\ +=\ +([0-9]+) ]]; then
            num_atoms="${BASH_REMATCH[1]}"
            continue
        fi

        # Number of electrons: "number of electrons       =         8.00"
        if [[ "$trimmed" =~ ^number\ of\ electrons\ +=\ +([0-9.]+) ]]; then
            num_electrons="${BASH_REMATCH[1]}"
            continue
        fi

        # ecutwfc: "kinetic-energy cutoff     =      60.0000  Ry"
        if [[ "$trimmed" =~ ^kinetic-energy\ cutoff\ +=\ +([0-9.]+)\ +Ry ]]; then
            ecutwfc="${BASH_REMATCH[1]}"
            continue
        fi

        # ecutrho: "charge-density cutoff     =     480.0000  Ry"
        if [[ "$trimmed" =~ ^charge-density\ cutoff\ +=\ +([0-9.]+)\ +Ry ]]; then
            ecutrho="${BASH_REMATCH[1]}"
            continue
        fi

        # k-points: "number of k points=    10"
        if [[ "$trimmed" =~ ^number\ of\ k\ points=\ +([0-9]+) ]]; then
            k_points="${BASH_REMATCH[1]}"
            continue
        fi

        # Convergence: "convergence has been achieved in   4 iterations"
        if [[ "$trimmed" =~ ^convergence\ has\ been\ achieved ]]; then
            convergence_achieved="yes"
            continue
        fi

        # WALL time: "PWSCF        :      1.23s CPU      1.48s WALL"
        if [[ "$trimmed" =~ ^PWSCF\ +:\ +[0-9.]+s\ +CPU\ +([0-9.]+)s\ +WALL ]]; then
            elapsed_time="${BASH_REMATCH[1]}"
            continue
        fi
    done <<< "$text"

    [[ -n "$total_energy_ry" ]] && result+="total_energy_Ry ${total_energy_ry}"$'\n'
    [[ -n "$total_force" ]] && result+="total_force ${total_force}"$'\n'
    [[ -n "$pressure_kbar" ]] && result+="pressure_kbar ${pressure_kbar}"$'\n'
    [[ -n "$num_atoms" ]] && result+="num_atoms ${num_atoms}"$'\n'
    [[ -n "$num_electrons" ]] && result+="num_electrons ${num_electrons}"$'\n'
    [[ -n "$ecutwfc" ]] && result+="ecutwfc ${ecutwfc}"$'\n'
    [[ -n "$ecutrho" ]] && result+="ecutrho ${ecutrho}"$'\n'
    [[ -n "$k_points" ]] && result+="k_points ${k_points}"$'\n'
    [[ -n "$elapsed_time" ]] && result+="elapsed_time ${elapsed_time}"$'\n'
    result+="convergence_achieved ${convergence_achieved}"$'\n'

    echo "$result"
}
