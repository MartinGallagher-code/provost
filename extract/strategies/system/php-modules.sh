#!/bin/bash
## Name: php-modules
## Description: Extract module names from `php -m` output (skips [PHP Modules]/[Zend Modules] section headers)
## Version: 1.0
## Priority: 26
## Technique: yes
## Sample: samples/php-modules/basic.txt

# `php -m` prints bracketed section headers ("[PHP Modules]", "[Zend Modules]")
# followed by one module name per line. The bracket lines and blank separators
# are skipped; every remaining line is a module. Single-column list; a module
# name containing a space (e.g. "Zend OPcache") is joined with an underscore so
# it stays one value.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    # NB: no _is_json guard here — this output legitimately begins with '[',
    # which _is_json treats as JSON. The literal section-header check below is
    # specific enough on its own.
    # Distinctive: the "[PHP Modules]" section header.
    [[ "$text" == *"[PHP Modules]"* ]] || return 1
    _STRATEGY_CONFIDENCE=86
    return 0
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line
    while IFS= read -r line; do
        # Trim surrounding whitespace.
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -z "$line" ]] && continue
        # Skip bracketed section headers.
        [[ "$line" =~ ^\[.*\]$ ]] && continue
        # Collapse internal spaces to underscores so multi-word names stay one value.
        local v="${line// /_}"
        entry=$((entry + 1))
        result+="entry${entry}.c1 ${v}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
