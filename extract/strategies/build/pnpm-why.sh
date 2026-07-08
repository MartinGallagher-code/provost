#!/bin/bash
## Name: pnpm-why
## Description: Extract dependency lines from `pnpm why` tree output
## Version: 1.0
## Priority: 20
## Technique: yes
## Sample: samples/pnpm-why/basic.txt

# `pnpm why` prints a project banner ("<name>@<ver> <path>"), a "dependencies:"
# header, then a Unicode tree of "<name> <version>" nodes. Each dependency node
# is one record; the cleaned value strips the leading tree glyphs (single
# column).

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    # A "dependencies:" section drawn with box tree glyphs.
    if [[ "$text" == *"dependencies:"* && ( "$text" == *"├"* || "$text" == *"└"* ) ]]; then
        _STRATEGY_CONFIDENCE=86
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line s
    while IFS= read -r line; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        # Skip section headers ("dependencies:", "devDependencies:").
        [[ "$line" == *: && "$line" != *" "* ]] && continue
        # Skip the project banner: "<name>@<ver> <path>".
        [[ "$line" =~ ^[^[:space:]]+@[^[:space:]]+[[:space:]]+/ ]] && continue
        # Strip leading non-alphanumeric bytes (tree glyphs + spaces).
        s="$line"
        while [[ -n "$s" && "$s" != [A-Za-z0-9]* ]]; do s="${s#?}"; done
        s="${s%"${s##*[![:space:]]}"}"
        [[ -z "$s" ]] && continue
        entry=$((entry + 1))
        result+="entry${entry}.c1 ${s}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
