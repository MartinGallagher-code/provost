#!/bin/bash
## Name: gaussian
## Description: Extract energies and molecular data from Gaussian .log output
## Version: 1.0
## Priority: 10
## Sample: samples/gaussian/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0

    local hits=0
    [[ "$text" == *"Gaussian"* ]] && hits=$((hits + 1))
    [[ "$text" == *"Entering Link"* ]] && hits=$((hits + 1))
    [[ "$text" == *"SCF Done"* ]] && hits=$((hits + 1))
    [[ "$text" == *"Normal termination"* ]] && hits=$((hits + 1))
    [[ "$text" == *"Entering Gaussian System"* ]] && hits=$((hits + 1))
    [[ "$text" == *"basis functions"* ]] && hits=$((hits + 1))
    [[ "$text" == *"NAtoms="* ]] && hits=$((hits + 1))

    if [[ $hits -ge 3 ]]; then
        _STRATEGY_CONFIDENCE=95
        return 0
    fi
    if [[ $hits -ge 2 ]] && [[ "$text" == *"Gaussian"* ]]; then
        _STRATEGY_CONFIDENCE=85
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""

    local scf_energy=""
    local method=""
    local basis_set=""
    local num_atoms=""
    local num_basis_functions=""
    local dipole_moment=""
    local normal_termination="no"
    local charge=""
    local multiplicity=""
    local zero_point_energy=""
    local thermal_energy=""

    while IFS= read -r line; do
        local trimmed="$line"
        while [[ "$trimmed" == " "* ]]; do trimmed="${trimmed# }"; done

        # Gaussian version: "Gaussian 16, Revision C.01"
        if [[ "$trimmed" =~ Gaussian\ +([0-9]+),?\ *Revision\ +([^ ,]+) ]]; then
            result+="gaussian_version ${BASH_REMATCH[1]}"$'\n'
            result+="revision ${BASH_REMATCH[2]}"$'\n'
        fi

        # Method/basis from route: "#p B3LYP/6-31G(d) opt freq"
        # or: "# HF/STO-3G"
        if [[ "$trimmed" =~ ^\#[pPnNtT]?\ +(.+) ]]; then
            local route="${BASH_REMATCH[1]}"
            # Extract method/basis: first token with /
            if [[ "$route" =~ ([^ ]+)/([^ ]+) ]]; then
                method="${BASH_REMATCH[1]}"
                basis_set="${BASH_REMATCH[2]}"
            fi
        fi

        # SCF Done: "SCF Done:  E(RB3LYP) =  -76.4089661     A.U. after   10 cycles"
        if [[ "$trimmed" == *"SCF Done"* ]]; then
            # Extract method from E(METHOD)
            local _after="${trimmed#*E(}"
            local scf_method="${_after%%)*}"
            # Extract energy value after = sign
            _after="${trimmed#*= }"
            while [[ "$_after" == " "* ]]; do _after="${_after# }"; done
            read -ra _earr <<< "$_after"
            scf_energy="${_earr[0]}"
            # Use the SCF method if we didn't get one from route
            [[ -z "$method" ]] && method="$scf_method"
        fi

        # NAtoms: "NAtoms=    3 NActive=    3"
        if [[ "$trimmed" =~ NAtoms=\ *([0-9]+) ]]; then
            num_atoms="${BASH_REMATCH[1]}"
        fi

        # Basis functions: "123 basis functions,  456 primitive gaussians"
        if [[ "$trimmed" =~ ^([0-9]+)\ +basis\ functions ]]; then
            num_basis_functions="${BASH_REMATCH[1]}"
        fi

        # Charge and multiplicity: "Charge =  0 Multiplicity = 1"
        if [[ "$trimmed" =~ Charge\ *=\ *(-?[0-9]+)\ +Multiplicity\ *=\ *([0-9]+) ]]; then
            charge="${BASH_REMATCH[1]}"
            multiplicity="${BASH_REMATCH[2]}"
        fi

        # Dipole moment: "Tot=   1.8546"  (after "Dipole moment" header)
        if [[ "$trimmed" =~ ^Tot=\ *([0-9.]+) ]]; then
            dipole_moment="${BASH_REMATCH[1]}"
        fi

        # Zero-point energy: "Zero-point correction=           0.021428"
        if [[ "$trimmed" =~ ^Zero-point\ correction=\ *([0-9.]+) ]]; then
            zero_point_energy="${BASH_REMATCH[1]}"
        fi

        # Thermal energy: "Thermal correction to Energy=          0.024103"
        if [[ "$trimmed" =~ ^Thermal\ correction\ to\ Energy=\ *([0-9.]+) ]]; then
            thermal_energy="${BASH_REMATCH[1]}"
        fi

        # Normal termination
        if [[ "$trimmed" == *"Normal termination"* ]]; then
            normal_termination="yes"
        fi

        # Error termination
        if [[ "$trimmed" == *"Error termination"* ]]; then
            normal_termination="error"
        fi
    done <<< "$text"

    [[ -n "$method" ]] && result+="method ${method}"$'\n'
    [[ -n "$basis_set" ]] && result+="basis_set ${basis_set}"$'\n'
    [[ -n "$charge" ]] && result+="charge ${charge}"$'\n'
    [[ -n "$multiplicity" ]] && result+="multiplicity ${multiplicity}"$'\n'
    [[ -n "$num_atoms" ]] && result+="num_atoms ${num_atoms}"$'\n'
    [[ -n "$num_basis_functions" ]] && result+="num_basis_functions ${num_basis_functions}"$'\n'
    [[ -n "$scf_energy" ]] && result+="scf_energy ${scf_energy}"$'\n'
    [[ -n "$dipole_moment" ]] && result+="dipole_moment ${dipole_moment}"$'\n'
    [[ -n "$zero_point_energy" ]] && result+="zero_point_energy ${zero_point_energy}"$'\n'
    [[ -n "$thermal_energy" ]] && result+="thermal_energy ${thermal_energy}"$'\n'
    result+="normal_termination ${normal_termination}"$'\n'

    echo "$result"
}
