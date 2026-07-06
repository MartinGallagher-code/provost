#!/bin/bash
## Name: cargo-tree
## Description: Extract dependency names and versions from cargo tree output
## Version: 1.0
## Priority: 25
## Sample: samples/cargo-tree/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=80
    # Reject JSON
    _is_json "$1" && return 1

    # Must have tree-drawing characters AND crate@version patterns
    # Tree chars: lines containing box-drawing sequences
    local tree_count=0
    local _re_version=' v[0-9]+\.[0-9]+\.[0-9]+'
    while IFS= read -r _line; do
        [[ -z "$_line" ]] && continue
        # Check for tree markers AND version pattern
        if [[ "$_line" == *"── "* || "$_line" == *"│"* ]]; then
            if [[ "$_line" =~ $_re_version ]]; then
                tree_count=$((tree_count + 1))
            fi
        fi
        # Also check the root line (no tree chars, just name v0.0.0)
        if [[ $tree_count -eq 0 && "$_line" =~ $_re_version ]]; then
            # Root package line — count it but keep looking for tree chars
            :
        fi
    done <<< "$text"

    [[ $tree_count -ge 2 ]] && return 0
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local dep_num=0
    local is_root=1

    local _re_name_ver='^(.*) v([0-9]+\.[0-9]+[.0-9]*)'

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Strip tree-drawing characters to get the package info
        local pkg_part="$line"

        # Remove leading tree characters: spaces, │, ├, └, ──, etc.
        # Strip from left until we hit an alphanumeric or @ character
        while true; do
            case "$pkg_part" in
                " "*) pkg_part="${pkg_part# }" ;;
                "│"*) pkg_part="${pkg_part#│}" ;;
                "├"*) pkg_part="${pkg_part#├}" ;;
                "└"*) pkg_part="${pkg_part#└}" ;;
                "─"*) pkg_part="${pkg_part#─}" ;;
                *) break ;;
            esac
        done

        # Trim leading spaces after stripping
        while [[ "$pkg_part" == " "* ]]; do pkg_part="${pkg_part# }"; done

        [[ -z "$pkg_part" ]] && continue

        # Extract name and version: "name v0.1.0 (path)" or "name v0.1.0"
        if [[ "$pkg_part" =~ $_re_name_ver ]]; then
            local name="${BASH_REMATCH[1]}"
            local version="${BASH_REMATCH[2]}"

            # Trim whitespace from name
            while [[ "$name" == " "* ]]; do name="${name# }"; done
            while [[ "$name" == *" " ]]; do name="${name% }"; done

            # Replace spaces/special chars in name with underscores
            name="${name// /_}"
            name="${name//-/_}"

            if [[ $is_root -eq 1 ]]; then
                result+="root.name ${name}"$'\n'
                result+="root.version ${version}"$'\n'
                is_root=0
            else
                dep_num=$((dep_num + 1))
                result+="dep${dep_num}.name ${name}"$'\n'
                result+="dep${dep_num}.version ${version}"$'\n'
            fi
        fi
    done <<< "$text"

    echo "$result"
}
