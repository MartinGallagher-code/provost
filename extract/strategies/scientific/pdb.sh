#!/bin/bash
## Name: pdb
## Description: Extract structure metadata from Protein Data Bank (PDB) format files
## Version: 1.0
## Priority: 10
## Sample: samples/pdb/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0

    local hits=0
    [[ "$text" == *"HEADER"* ]] && hits=$((hits + 1))
    [[ "$text" == *"ATOM "* || "$text" == *$'\n'"ATOM "* ]] && hits=$((hits + 1))
    [[ "$text" == *"HETATM"* ]] && hits=$((hits + 1))
    [[ "$text" == *"COMPND"* ]] && hits=$((hits + 1))
    [[ "$text" == *"REMARK"* ]] && hits=$((hits + 1))
    [[ "$text" == *"TITLE"* ]] && hits=$((hits + 1))
    [[ "$text" == *"CRYST1"* ]] && hits=$((hits + 1))
    [[ "$text" == *"END"* ]] && hits=$((hits + 1))

    if [[ $hits -ge 4 ]]; then
        _STRATEGY_CONFIDENCE=95
        return 0
    fi
    if [[ $hits -ge 3 ]] && [[ "$text" == *"ATOM "* ]]; then
        _STRATEGY_CONFIDENCE=80
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""

    local title=""
    local compound=""
    local num_atoms=0
    local num_hetatm=0
    local resolution=""
    local r_factor=""
    local space_group=""
    local header_class=""
    local pdb_id=""
    local num_models=0
    local residues_seen=""
    local num_residues=0

    while IFS= read -r line; do
        # HEADER: "HEADER    OXIDOREDUCTASE                          01-JAN-00   1ABC"
        if [[ "$line" == HEADER* ]]; then
            local hdata="${line:10}"
            # Classification is columns 11-50, PDB ID is columns 63-66
            if [[ ${#line} -ge 66 ]]; then
                pdb_id="${line:62:4}"
                # Trim spaces
                while [[ "$pdb_id" == *" " ]]; do pdb_id="${pdb_id% }"; done
            fi
            header_class="${hdata%%  *}"
            while [[ "$header_class" == *" " ]]; do header_class="${header_class% }"; done
            continue
        fi

        # TITLE
        if [[ "$line" == TITLE* ]]; then
            local tdata="${line:10}"
            while [[ "$tdata" == " "* ]]; do tdata="${tdata# }"; done
            while [[ "$tdata" == *" " ]]; do tdata="${tdata% }"; done
            if [[ -n "$title" ]]; then
                title+=" $tdata"
            else
                title="$tdata"
            fi
            continue
        fi

        # COMPND
        if [[ "$line" == COMPND* ]]; then
            local cdata="${line:10}"
            while [[ "$cdata" == " "* ]]; do cdata="${cdata# }"; done
            while [[ "$cdata" == *" " ]]; do cdata="${cdata% }"; done
            if [[ -n "$compound" ]]; then
                compound+=" $cdata"
            else
                compound="$cdata"
            fi
            continue
        fi

        # ATOM records
        if [[ "$line" == "ATOM  "* ]]; then
            num_atoms=$((num_atoms + 1))
            # Track unique residues (residue name + chain + seq number: cols 18-26)
            if [[ ${#line} -ge 26 ]]; then
                local res_key="${line:17:9}"
                if [[ "$residues_seen" != *"|${res_key}|"* ]]; then
                    residues_seen+="|${res_key}|"
                    num_residues=$((num_residues + 1))
                fi
            fi
            continue
        fi

        # HETATM records
        if [[ "$line" == HETATM* ]]; then
            num_hetatm=$((num_hetatm + 1))
            continue
        fi

        # MODEL records
        if [[ "$line" == MODEL* ]]; then
            num_models=$((num_models + 1))
            continue
        fi

        # REMARK   2 RESOLUTION
        if [[ "$line" == *"RESOLUTION"*"ANGSTROMS"* ]]; then
            if [[ "$line" =~ ([0-9]+\.[0-9]+)\ *ANGSTROMS ]]; then
                resolution="${BASH_REMATCH[1]}"
            fi
            continue
        fi

        # REMARK   3  R VALUE (WORKING SET)
        if [[ "$line" == *"R VALUE"*"WORKING"* ]] && [[ -z "$r_factor" ]]; then
            if [[ "$line" =~ :\ *([0-9]+\.[0-9]+) ]]; then
                r_factor="${BASH_REMATCH[1]}"
            fi
            continue
        fi

        # CRYST1 for space group
        # Format: CRYST1 a b c alpha beta gamma sGroup Z
        if [[ "$line" == CRYST1* ]]; then
            # Extract by reading fields: skip first 7 tokens (CRYST1 a b c alpha beta gamma)
            read -ra _cryst <<< "$line"
            if [[ ${#_cryst[@]} -ge 8 ]]; then
                # Space group tokens are after the 6 numeric values, before the Z value (last token if numeric)
                local sg_parts=""
                local i
                for ((i=7; i<${#_cryst[@]}; i++)); do
                    local tok="${_cryst[$i]}"
                    # Skip trailing Z value (pure integer)
                    if [[ $i -eq $((${#_cryst[@]}-1)) ]] && [[ "$tok" =~ ^[0-9]+$ ]]; then
                        continue
                    fi
                    [[ -n "$sg_parts" ]] && sg_parts+=" "
                    sg_parts+="$tok"
                done
                [[ -n "$sg_parts" ]] && space_group="$sg_parts"
            fi
            continue
        fi
    done <<< "$text"

    [[ -n "$pdb_id" ]] && result+="pdb_id ${pdb_id}"$'\n'
    [[ -n "$header_class" ]] && result+="classification ${header_class}"$'\n'
    [[ -n "$title" ]] && result+="title ${title}"$'\n'
    [[ -n "$compound" ]] && result+="compound ${compound}"$'\n'
    [[ $num_atoms -gt 0 ]] && result+="num_atoms ${num_atoms}"$'\n'
    [[ $num_hetatm -gt 0 ]] && result+="num_hetatm ${num_hetatm}"$'\n'
    [[ $num_residues -gt 0 ]] && result+="num_residues ${num_residues}"$'\n'
    [[ $num_models -gt 0 ]] && result+="num_models ${num_models}"$'\n'
    [[ -n "$resolution" ]] && result+="resolution ${resolution}"$'\n'
    [[ -n "$r_factor" ]] && result+="r_factor ${r_factor}"$'\n'
    [[ -n "$space_group" ]] && result+="space_group ${space_group}"$'\n'

    echo "$result"
}
