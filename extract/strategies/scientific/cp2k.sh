#!/bin/bash
## Name: cp2k
## Description: Extract energies, SCF convergence, and timing data from CP2K output
## Version: 1.0
## Priority: 10
## Sample: samples/cp2k/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0

    local hits=0
    [[ "$text" == *"CP2K"* || "$text" == *"cp2k"* ]] && hits=$((hits + 1))
    [[ "$text" == *"QUICKSTEP"* ]] && hits=$((hits + 1))
    [[ "$text" == *"DBCSR"* ]] && hits=$((hits + 1))
    [[ "$text" == *"SCF run converged"* ]] && hits=$((hits + 1))
    [[ "$text" == *"FORCE_EVAL"* ]] && hits=$((hits + 1))
    [[ "$text" == *"ENERGY|"* ]] && hits=$((hits + 1))
    [[ "$text" == *"GLOBAL|"* ]] && hits=$((hits + 1))

    if [[ $hits -ge 3 ]]; then
        _STRATEGY_CONFIDENCE=95
        return 0
    fi
    if [[ $hits -ge 2 ]] && [[ "$text" == *"CP2K"* || "$text" == *"cp2k"* ]]; then
        _STRATEGY_CONFIDENCE=85
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""

    local total_energy=""
    local num_atoms=""
    local num_electrons=""
    local scf_cycles=0
    local max_scf_gradient=""
    local elapsed_time=""
    local method=""
    local functional=""

    while IFS= read -r line; do
        local trimmed="$line"
        while [[ "$trimmed" == " "* ]]; do trimmed="${trimmed# }"; done

        # Total energy: "ENERGY| Total FORCE_EVAL ( QS ) energy [a.u.]:     -123.456789"
        if [[ "$trimmed" =~ ^ENERGY\|.*Total.*energy.*:\ +([^ ]+) ]]; then
            total_energy="${BASH_REMATCH[1]}"
            continue
        fi

        # Number of atoms: "Total number of            - Atoms:                                         96"
        if [[ "$trimmed" =~ Atoms:\ +([0-9]+) ]]; then
            num_atoms="${BASH_REMATCH[1]}"
            continue
        fi

        # Number of electrons: "Number of electrons:                                                       256"
        if [[ "$trimmed" =~ ^Number\ of\ electrons:\ +([0-9]+) ]]; then
            num_electrons="${BASH_REMATCH[1]}"
            continue
        fi

        # SCF converged line: "*** SCF run converged in     7 steps ***"
        if [[ "$trimmed" =~ SCF\ run\ converged\ in\ +([0-9]+)\ +steps ]]; then
            scf_cycles="${BASH_REMATCH[1]}"
            continue
        fi

        # Maximum gradient: "Maximum gradient:                                           0.00000012"
        if [[ "$trimmed" =~ ^Maximum\ gradient:\ +([0-9.Ee+-]+) ]]; then
            max_scf_gradient="${BASH_REMATCH[1]}"
            continue
        fi

        # Elapsed time: "Elapsed time:                                               330.000 seconds"
        if [[ "$trimmed" =~ Elapsed\ time:\ +([0-9.]+)\ +seconds ]]; then
            elapsed_time="${BASH_REMATCH[1]}"
            continue
        fi

        # Method detection: MODULE QUICKSTEP: DFT
        if [[ "$trimmed" =~ ^MODULE\ QUICKSTEP:\ +([A-Za-z]+) ]]; then
            method="${BASH_REMATCH[1]}"
            continue
        fi

        # Functional: "DFT| Functional group                                               BLYP"
        if [[ "$trimmed" =~ ^DFT\|\ +Functional\ group\ +([A-Za-z0-9_-]+) ]]; then
            functional="${BASH_REMATCH[1]}"
            continue
        fi

        # Alternative functional: "DFT| Exchange-correlation functional   ..."
        if [[ -z "$functional" ]] && [[ "$trimmed" =~ ^DFT\|\ +Exchange-correlation\ functional\ +([A-Za-z0-9_-]+) ]]; then
            functional="${BASH_REMATCH[1]}"
            continue
        fi
    done <<< "$text"

    [[ -n "$total_energy" ]] && result+="total_energy ${total_energy}"$'\n'
    [[ -n "$num_atoms" ]] && result+="num_atoms ${num_atoms}"$'\n'
    [[ -n "$num_electrons" ]] && result+="num_electrons ${num_electrons}"$'\n'
    [[ $scf_cycles -gt 0 ]] && result+="scf_cycles ${scf_cycles}"$'\n'
    [[ -n "$max_scf_gradient" ]] && result+="max_scf_gradient ${max_scf_gradient}"$'\n'
    [[ -n "$elapsed_time" ]] && result+="elapsed_time ${elapsed_time}"$'\n'
    [[ -n "$method" ]] && result+="method ${method}"$'\n'
    [[ -n "$functional" ]] && result+="functional ${functional}"$'\n'

    echo "$result"
}
