#!/bin/bash
## Name: h5dump
## Description: Extract dataset structure and metadata from HDF5 h5dump text output
## Version: 1.0
## Priority: 10
## Sample: samples/h5dump/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0

    local hits=0
    [[ "$text" == *"HDF5"* ]] && hits=$((hits + 1))
    [[ "$text" == *"h5dump"* ]] && hits=$((hits + 1))
    [[ "$text" == *"DATASET"* ]] && hits=$((hits + 1))
    [[ "$text" == *"DATASPACE"* ]] && hits=$((hits + 1))
    [[ "$text" == *"DATATYPE"* ]] && hits=$((hits + 1))
    [[ "$text" == *"GROUP"* ]] && hits=$((hits + 1))

    if [[ $hits -ge 3 ]]; then
        _STRATEGY_CONFIDENCE=95
        return 0
    fi
    if [[ $hits -ge 2 ]] && [[ "$text" == *"HDF5"* ]]; then
        _STRATEGY_CONFIDENCE=80
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""

    # Extract HDF5 filename: HDF5 "filename.h5" {
    while IFS= read -r line; do
        if [[ "$line" =~ ^HDF5\ \"([^\"]+)\" ]]; then
            result+="filename ${BASH_REMATCH[1]}"$'\n'
            break
        fi
    done <<< "$text"

    # Count datasets, groups, attributes
    local num_datasets=0
    local num_groups=0
    local num_attributes=0
    local dataset_names=""
    local group_names=""

    local current_path=""
    while IFS= read -r line; do
        # Trim leading whitespace
        local trimmed="$line"
        while [[ "$trimmed" == " "* ]]; do trimmed="${trimmed# }"; done

        # GROUP "name"
        if [[ "$trimmed" =~ ^GROUP\ \"([^\"]+)\" ]]; then
            num_groups=$((num_groups + 1))
            local gname="${BASH_REMATCH[1]}"
            [[ -n "$dataset_names" ]] && group_names+=","
            group_names+="$gname"
            current_path="$gname"
            continue
        fi

        # DATASET "name"
        if [[ "$trimmed" =~ ^DATASET\ \"([^\"]+)\" ]]; then
            num_datasets=$((num_datasets + 1))
            local dname="${BASH_REMATCH[1]}"
            [[ -n "$dataset_names" ]] && dataset_names+=","
            if [[ -n "$current_path" && "$current_path" != "/" ]]; then
                dataset_names+="${current_path}/${dname}"
            else
                dataset_names+="$dname"
            fi
            continue
        fi

        # DATATYPE
        if [[ "$trimmed" =~ ^DATATYPE\ +(.+) ]]; then
            local dtype="${BASH_REMATCH[1]}"
            # Clean up the datatype
            dtype="${dtype%;}"
            dtype="${dtype# }"
            # Report per-dataset datatype using dataset count as index
            result+="dataset${num_datasets}.datatype ${dtype}"$'\n'
            continue
        fi

        # DATASPACE  SIMPLE { ( dim1, dim2 ) / ( dim1, dim2 ) }
        if [[ "$trimmed" == DATASPACE*SIMPLE* ]]; then
            local _after="${trimmed#*(}"
            local dims="${_after%%)*}"
            # Clean spaces
            dims="${dims// /}"
            result+="dataset${num_datasets}.dimensions ${dims}"$'\n'
            continue
        fi
        if [[ "$trimmed" =~ ^DATASPACE\ +SCALAR ]]; then
            result+="dataset${num_datasets}.dimensions scalar"$'\n'
            continue
        fi

        # ATTRIBUTE "name"
        if [[ "$trimmed" =~ ^ATTRIBUTE\ \"([^\"]+)\" ]]; then
            num_attributes=$((num_attributes + 1))
            local aname="${BASH_REMATCH[1]}"
            result+="attribute${num_attributes}.name ${aname}"$'\n'
            continue
        fi

        # DATA values inside attributes (simple single-value case)
        if [[ "$trimmed" =~ ^\(0\):\ *(.*) ]]; then
            local aval="${BASH_REMATCH[1]}"
            if [[ $num_attributes -gt 0 ]]; then
                result+="attribute${num_attributes}.value ${aval}"$'\n'
            fi
            continue
        fi
    done <<< "$text"

    [[ $num_groups -gt 0 ]] && result+="num_groups ${num_groups}"$'\n'
    [[ $num_datasets -gt 0 ]] && result+="num_datasets ${num_datasets}"$'\n'
    [[ $num_attributes -gt 0 ]] && result+="num_attributes ${num_attributes}"$'\n'
    [[ -n "$dataset_names" ]] && result+="dataset_names ${dataset_names}"$'\n'

    echo "$result"
}
