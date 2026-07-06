#!/bin/bash
## Name: npm-list
## Description: Extract package names and versions from npm list tree output
## Version: 1.0
## Priority: 25
## Sample: samples/npm-list/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=80

    # Must have tree marker lines: +-- or `-- with @version
    local tree_count=0
    while IFS= read -r _line; do
        if [[ "$_line" == *"+-- "* || "$_line" == *"\`-- "* ]]; then
            if [[ "$_line" == *"@"* ]]; then
                tree_count=$((tree_count + 1))
            fi
        fi
    done <<< "$text"
    [[ $tree_count -ge 1 ]] && return 0
    return 1
}

strategy_extract () {
    local text="$1"

    local result=""
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Check for root package (first line, no tree marker): name@version
        if [[ "$line" =~ ^[a-zA-Z@][a-zA-Z0-9./_@-]*@[0-9] ]]; then
            local pkg version
            # Handle scoped packages (@scope/name@version)
            if [[ "$line" == "@"* ]]; then
                # Scoped package: @scope/name@version
                # Find last @digit to split
                local temp="${line%@[0-9]*}"
                pkg="$temp"
                version="${line#"$temp"@}"
            else
                pkg="${line%%@[0-9]*}"
                version="${line#*@}"
            fi
            # Clean package name: replace /@- with underscores, strip leading _
            pkg="${pkg//\//_}"
            pkg="${pkg//@/_}"
            pkg="${pkg//-/_}"
            while [[ "$pkg" == "_"* ]]; do pkg="${pkg#_}"; done
            [[ -n "$pkg" && -n "$version" ]] && result+="${pkg} ${version}"$'\n'
            continue
        fi

        # Check for tree lines: +-- pkg@version or `-- pkg@version
        if [[ "$line" == *"+-- "* || "$line" == *"\`-- "* ]]; then
            local entry
            # Extract everything after the last +-- or `--
            if [[ "$line" == *"+-- "* ]]; then
                entry="${line##*+-- }"
            else
                entry="${line##*\`-- }"
            fi

            local pkg version
            if [[ "$entry" == "@"* ]]; then
                # Scoped package
                local temp="${entry%@[0-9]*}"
                pkg="$temp"
                version="${entry#"$temp"@}"
            else
                pkg="${entry%%@[0-9]*}"
                version="${entry#*@}"
            fi

            [[ -z "$pkg" ]] && continue
            [[ -z "$version" ]] && continue

            # Clean package name for field name (replace /, @, - with underscores)
            pkg="${pkg//\//_}"
            pkg="${pkg//@/_}"
            pkg="${pkg//-/_}"
            while [[ "$pkg" == "_"* ]]; do pkg="${pkg#_}"; done

            result+="${pkg} ${version}"$'\n'
        fi
    done <<< "$text"

    echo "$result"
}
