#!/bin/bash
## Name: pip-list
## Description: Extract package names and versions from pip list or pip freeze output
## Version: 1.0
## Priority: 25
## Sample: samples/pip-list/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=80

    # Detect pip list format: first line is "Package    Version" header
    local first_line=""
    while IFS= read -r _line; do
        first_line="$_line"
        break
    done <<< "$text"
    if [[ "$first_line" == "Package "* && "$first_line" == *"Version"* && "$first_line" != *"Latest"* ]]; then
        return 0
    fi

    # Detect pip freeze format: lines with name==version
    local freeze_count=0
    while IFS= read -r _line; do
        if [[ "$_line" =~ ^[a-zA-Z][a-zA-Z0-9._-]*== ]]; then
            freeze_count=$((freeze_count + 1))
        fi
    done <<< "$text"
    [[ $freeze_count -ge 2 ]] && return 0

    return 1
}

strategy_extract () {
    local text="$1"

    local result=""
    local first_line=""
    while IFS= read -r _line; do
        first_line="$_line"
        break
    done <<< "$text"

    # Check if this is pip list format (has Package Version header)
    if [[ "$first_line" == "Package "* && "$first_line" == *"Version"* ]]; then
        local row_num=0
        while IFS= read -r line; do
            row_num=$((row_num + 1))
            # Skip header (line 1) and separator (line 2)
            [[ $row_num -le 2 ]] && continue
            [[ -z "$line" ]] && continue

            # Extract package name and version from aligned columns
            read -ra _arr <<< "$line"
            local pkg="${_arr[0]}"
            local version="${_arr[1]}"

            [[ -z "$pkg" ]] && continue
            [[ -z "$version" ]] && continue

            # Replace hyphens with underscores in package name for field name
            local field_name="${pkg//-/_}"

            result+="Package_${field_name} ${version}"$'\n'
        done <<< "$text"
    else
        # pip freeze format: name==version
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            [[ "$line" == *"=="* ]] || continue

            local pkg="${line%%==*}"
            local version="${line##*==}"

            [[ -z "$pkg" ]] && continue
            [[ -z "$version" ]] && continue

            local field_name="${pkg//-/_}"

            result+="Package_${field_name} ${version}"$'\n'
        done <<< "$text"
    fi

    echo "$result"
}
