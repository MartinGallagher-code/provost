#!/bin/bash
## Name: buildah-containers
## Description: Extract container information from buildah containers output
## Version: 1.0
## Priority: 25
## Technique: table
## Sample: samples/buildah-containers/sample1.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=88
    _is_json "$text" && return 1
    local first_line=""
    while IFS= read -r _line; do
        [[ -z "$_line" ]] && continue
        first_line="$_line"
        break
    done <<< "$text"
    # buildah containers header: CONTAINER ID  BUILDER  IMAGE ID  IMAGE NAME  CONTAINER NAME
    if [[ "$first_line" == "CONTAINER ID"* && "$first_line" == *"BUILDER"* && "$first_line" == *"CONTAINER NAME"* ]]; then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local row_num=0
    local past_header=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        if [[ "$line" == "CONTAINER ID"* && "$line" == *"BUILDER"* ]]; then
            past_header=1
            continue
        fi
        [[ $past_header -eq 0 ]] && continue

        read -ra _arr <<< "$line"
        [[ ${#_arr[@]} -lt 4 ]] && continue

        row_num=$((row_num + 1))
        local prefix="container${row_num}"

        local cid="${_arr[0]}"
        local builder="${_arr[1]}"
        local image_id="${_arr[2]}"
        # Image name may contain slashes/colons, container name is last
        local cname="${_arr[${#_arr[@]}-1]}"
        # Image name is tokens between image_id and cname
        local image_name=""
        local i
        for ((i=3; i<${#_arr[@]}-1; i++)); do
            if [[ -z "$image_name" ]]; then
                image_name="${_arr[$i]}"
            else
                image_name="${image_name}_${_arr[$i]}"
            fi
        done

        result+="${prefix}.id ${cid}"$'\n'
        result+="${prefix}.builder ${builder}"$'\n'
        result+="${prefix}.image_id ${image_id}"$'\n'
        [[ -n "$image_name" ]] && result+="${prefix}.image_name ${image_name}"$'\n'
        result+="${prefix}.name ${cname}"$'\n'
    done <<< "$text"

    echo "$result"
}
