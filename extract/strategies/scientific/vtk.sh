#!/bin/bash
## Name: vtk
## Description: Extract structure and metadata from VTK legacy format text files
## Version: 1.0
## Priority: 10
## Sample: samples/vtk/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0

    local hits=0
    [[ "$text" == *"# vtk DataFile"* ]] && hits=$((hits + 2))
    [[ "$text" == *"ASCII"* ]] && hits=$((hits + 1))
    [[ "$text" == *"STRUCTURED_POINTS"* ]] && hits=$((hits + 1))
    [[ "$text" == *"POLYDATA"* ]] && hits=$((hits + 1))
    [[ "$text" == *"UNSTRUCTURED_GRID"* ]] && hits=$((hits + 1))
    [[ "$text" == *"STRUCTURED_GRID"* ]] && hits=$((hits + 1))
    [[ "$text" == *"RECTILINEAR_GRID"* ]] && hits=$((hits + 1))
    [[ "$text" == *"POINT_DATA"* ]] && hits=$((hits + 1))
    [[ "$text" == *"CELL_DATA"* ]] && hits=$((hits + 1))
    [[ "$text" == *"POINTS"* ]] && hits=$((hits + 1))

    if [[ "$text" == *"# vtk DataFile"* ]]; then
        _STRATEGY_CONFIDENCE=95
        return 0
    fi
    if [[ $hits -ge 3 ]]; then
        _STRATEGY_CONFIDENCE=80
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""

    local line_num=0
    local title=""
    local format=""
    local dataset_type=""
    local num_points=0
    local num_cells=0
    local num_data_arrays=0
    local dimensions=""

    while IFS= read -r line; do
        line_num=$((line_num + 1))
        local trimmed="$line"
        while [[ "$trimmed" == " "* ]]; do trimmed="${trimmed# }"; done
        [[ -z "$trimmed" ]] && continue

        # Line 1: version header "# vtk DataFile Version X.X"
        if [[ "$trimmed" == "# vtk DataFile"* ]]; then
            if [[ "$trimmed" =~ Version\ +([0-9.]+) ]]; then
                result+="version ${BASH_REMATCH[1]}"$'\n'
            fi
            continue
        fi

        # Line 2: title (if line_num is 2 and we saw the header)
        if [[ $line_num -eq 2 && -z "$title" ]]; then
            title="$trimmed"
            result+="title ${title}"$'\n'
            continue
        fi

        # Format: ASCII or BINARY
        if [[ "$trimmed" == "ASCII" || "$trimmed" == "BINARY" ]]; then
            format="$trimmed"
            result+="format ${format}"$'\n'
            continue
        fi

        # Dataset type: DATASET STRUCTURED_POINTS / POLYDATA / etc.
        if [[ "$trimmed" =~ ^DATASET\ +(.+) ]]; then
            dataset_type="${BASH_REMATCH[1]}"
            result+="dataset_type ${dataset_type}"$'\n'
            continue
        fi

        # DIMENSIONS nx ny nz (for structured types)
        if [[ "$trimmed" =~ ^DIMENSIONS\ +([0-9]+)\ +([0-9]+)\ +([0-9]+) ]]; then
            result+="dimensions ${BASH_REMATCH[1]}x${BASH_REMATCH[2]}x${BASH_REMATCH[3]}"$'\n'
            continue
        fi

        # ORIGIN x y z
        if [[ "$trimmed" =~ ^ORIGIN\ +([^ ]+)\ +([^ ]+)\ +([^ ]+) ]]; then
            result+="origin ${BASH_REMATCH[1]},${BASH_REMATCH[2]},${BASH_REMATCH[3]}"$'\n'
            continue
        fi

        # SPACING sx sy sz
        if [[ "$trimmed" =~ ^SPACING\ +([^ ]+)\ +([^ ]+)\ +([^ ]+) ]]; then
            result+="spacing ${BASH_REMATCH[1]},${BASH_REMATCH[2]},${BASH_REMATCH[3]}"$'\n'
            continue
        fi

        # POINTS n dataType
        if [[ "$trimmed" =~ ^POINTS\ +([0-9]+)\ +(.+) ]]; then
            num_points="${BASH_REMATCH[1]}"
            result+="num_points ${num_points}"$'\n'
            result+="points_datatype ${BASH_REMATCH[2]}"$'\n'
            continue
        fi

        # CELLS n size / POLYGONS n size
        if [[ "$trimmed" =~ ^(CELLS|POLYGONS|TRIANGLE_STRIPS|LINES|VERTICES)\ +([0-9]+)\ +([0-9]+) ]]; then
            num_cells="${BASH_REMATCH[2]}"
            result+="num_cells ${num_cells}"$'\n'
            result+="cell_type ${BASH_REMATCH[1]}"$'\n'
            continue
        fi

        # POINT_DATA n
        if [[ "$trimmed" =~ ^POINT_DATA\ +([0-9]+) ]]; then
            result+="num_point_data ${BASH_REMATCH[1]}"$'\n'
            continue
        fi

        # CELL_DATA n
        if [[ "$trimmed" =~ ^CELL_DATA\ +([0-9]+) ]]; then
            result+="num_cell_data ${BASH_REMATCH[1]}"$'\n'
            continue
        fi

        # SCALARS name dataType numComp
        if [[ "$trimmed" =~ ^SCALARS\ +([^ ]+)\ +([^ ]+) ]]; then
            num_data_arrays=$((num_data_arrays + 1))
            result+="data_array${num_data_arrays}.name ${BASH_REMATCH[1]}"$'\n'
            result+="data_array${num_data_arrays}.type scalars"$'\n'
            result+="data_array${num_data_arrays}.datatype ${BASH_REMATCH[2]}"$'\n'
            continue
        fi

        # VECTORS name dataType
        if [[ "$trimmed" =~ ^VECTORS\ +([^ ]+)\ +([^ ]+) ]]; then
            num_data_arrays=$((num_data_arrays + 1))
            result+="data_array${num_data_arrays}.name ${BASH_REMATCH[1]}"$'\n'
            result+="data_array${num_data_arrays}.type vectors"$'\n'
            result+="data_array${num_data_arrays}.datatype ${BASH_REMATCH[2]}"$'\n'
            continue
        fi

        # TENSORS name dataType
        if [[ "$trimmed" =~ ^TENSORS\ +([^ ]+)\ +([^ ]+) ]]; then
            num_data_arrays=$((num_data_arrays + 1))
            result+="data_array${num_data_arrays}.name ${BASH_REMATCH[1]}"$'\n'
            result+="data_array${num_data_arrays}.type tensors"$'\n'
            result+="data_array${num_data_arrays}.datatype ${BASH_REMATCH[2]}"$'\n'
            continue
        fi
    done <<< "$text"

    [[ $num_data_arrays -gt 0 ]] && result+="num_data_arrays ${num_data_arrays}"$'\n'

    echo "$result"
}
