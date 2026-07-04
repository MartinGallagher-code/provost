#!/bin/bash
## Name: vasp
## Description: Extract energies and parameters from VASP OUTCAR/OSZICAR output
## Version: 1.0
## Priority: 10
## Sample: samples/vasp/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0

    local hits=0
    [[ "$text" == *"VASP"* ]] && hits=$((hits + 1))
    [[ "$text" == *"OUTCAR"* ]] && hits=$((hits + 1))
    [[ "$text" == *"POTCAR"* ]] && hits=$((hits + 1))
    [[ "$text" == *"EDIFF"* ]] && hits=$((hits + 1))
    [[ "$text" == *"ENCUT"* ]] && hits=$((hits + 1))
    [[ "$text" == *"free  energy"* || "$text" == *"free energy"* ]] && hits=$((hits + 1))
    [[ "$text" == *"TOTEN"* ]] && hits=$((hits + 1))
    [[ "$text" == *"INCAR"* ]] && hits=$((hits + 1))
    [[ "$text" == *"POSCAR"* ]] && hits=$((hits + 1))

    if [[ $hits -ge 3 ]]; then
        _STRATEGY_CONFIDENCE=95
        return 0
    fi
    if [[ $hits -ge 2 ]] && [[ "$text" == *"VASP"* ]]; then
        _STRATEGY_CONFIDENCE=85
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""

    local total_energy=""
    local fermi_energy=""
    local encut=""
    local ediff=""
    local num_ions=""
    local num_kpoints=""
    local elapsed_time=""
    local num_bands=""
    local num_scf_steps=0

    while IFS= read -r line; do
        local trimmed="$line"
        while [[ "$trimmed" == " "* ]]; do trimmed="${trimmed# }"; done

        # VASP version
        if [[ "$trimmed" =~ vasp\.([0-9.]+) ]]; then
            result+="vasp_version ${BASH_REMATCH[1]}"$'\n'
        fi

        # ENCUT: "ENCUT  =  400.00 eV"
        if [[ "$trimmed" =~ ^ENCUT\ *=\ *([0-9.]+) ]]; then
            encut="${BASH_REMATCH[1]}"
        fi

        # EDIFF: "EDIFF  = 0.1E-05"
        if [[ "$trimmed" =~ ^EDIFF\ *=\ *([^ ]+) ]]; then
            ediff="${BASH_REMATCH[1]}"
        fi

        # Number of ions: "NIONS =    12"
        if [[ "$trimmed" =~ NIONS\ *=\ *([0-9]+) ]]; then
            num_ions="${BASH_REMATCH[1]}"
        fi

        # Number of k-points: "k-points           NKPTS =     10"
        if [[ "$trimmed" =~ NKPTS\ *=\ *([0-9]+) ]]; then
            num_kpoints="${BASH_REMATCH[1]}"
        fi

        # Number of bands: "NBANDS=     24"
        if [[ "$trimmed" =~ NBANDS\ *=\ *([0-9]+) ]]; then
            num_bands="${BASH_REMATCH[1]}"
        fi

        # Free energy TOTEN: "free  energy   TOTEN  =      -123.456789 eV"
        if [[ "$trimmed" =~ TOTEN\ *=\ *(-?[0-9.]+) ]]; then
            total_energy="${BASH_REMATCH[1]}"
            num_scf_steps=$((num_scf_steps + 1))
        fi

        # E-fermi: "E-fermi :   5.1234"
        if [[ "$trimmed" =~ ^E-fermi\ *:\ *(-?[0-9.]+) ]]; then
            fermi_energy="${BASH_REMATCH[1]}"
        fi

        # Elapsed time: "Elapsed time (sec):    123.456"
        if [[ "$trimmed" =~ ^Elapsed\ time.*:\ *([0-9.]+) ]]; then
            elapsed_time="${BASH_REMATCH[1]}"
        fi

        # POTCAR: "POTCAR:    PAW_PBE Si 05Jan2001"
        if [[ "$trimmed" =~ ^POTCAR:\ +(.+) ]]; then
            local potcar="${BASH_REMATCH[1]}"
            while [[ "$potcar" == *" " ]]; do potcar="${potcar% }"; done
            # Only record first POTCAR (avoid duplicates from OUTCAR repeated sections)
            if [[ "$result" != *"potcar "* ]]; then
                result+="potcar ${potcar}"$'\n'
            fi
        fi

        # ISPIN
        if [[ "$trimmed" =~ ^ISPIN\ *=\ *([0-9]+) ]]; then
            result+="ispin ${BASH_REMATCH[1]}"$'\n'
        fi

        # ISMEAR
        if [[ "$trimmed" =~ ^ISMEAR\ *=\ *(-?[0-9]+) ]]; then
            result+="ismear ${BASH_REMATCH[1]}"$'\n'
        fi
    done <<< "$text"

    # Report final values (last occurrence = converged)
    [[ -n "$encut" ]] && result+="encut ${encut}"$'\n'
    [[ -n "$ediff" ]] && result+="ediff ${ediff}"$'\n'
    [[ -n "$num_ions" ]] && result+="num_ions ${num_ions}"$'\n'
    [[ -n "$num_kpoints" ]] && result+="num_kpoints ${num_kpoints}"$'\n'
    [[ -n "$num_bands" ]] && result+="num_bands ${num_bands}"$'\n'
    [[ -n "$total_energy" ]] && result+="total_energy ${total_energy}"$'\n'
    [[ -n "$fermi_energy" ]] && result+="fermi_energy ${fermi_energy}"$'\n'
    [[ -n "$elapsed_time" ]] && result+="elapsed_time ${elapsed_time}"$'\n'
    [[ $num_scf_steps -gt 0 ]] && result+="num_scf_steps ${num_scf_steps}"$'\n'

    echo "$result"
}
