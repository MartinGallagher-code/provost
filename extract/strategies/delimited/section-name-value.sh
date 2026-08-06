#!/bin/bash
## Name: section-name-value
## Description: `Section:` headers over `name value` rows (pnpm list) -> section/name/value rows — hint-routed
## Version: 1.0
## Priority: 46
## Sample: samples/section-name-value/basic.txt

# `pnpm list` groups packages under bare `Section:` headers:
#
#   dependencies:
#   express 4.19.2
#   pino 9.2.0
#
#   devDependencies:
#   typescript 5.4.5
#
# The bare headers broke the row parsers. Carrying the active section down as
# its own column keeps the grouping while making every package a row:
#
#   section          name        value
#   dependencies     express     4.19.2
#   dependencies     pino        9.2.0
#   devDependencies  typescript  5.4.5
#
# A line that is a single bare word ending in `:` sets the active section; any
# other non-blank line splits on its first whitespace into name/value under it.
#
# HINT-ONLY: routes on the leading `dependencies:` section via hints.tsv.

strategy_extract () {
    local text="$1"
    local line result="" entry=0 section=""
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        local s="${line#"${line%%[![:space:]]*}"}"
        s="${s%"${s##*[![:space:]]}"}"
        # A lone `word:` (no interior space) is a section header.
        if [[ "$s" == *: && "$s" != *[[:space:]]* ]]; then
            section="${s%:}"
            continue
        fi
        local name="${s%%[[:space:]]*}" val="${s#"${s%%[[:space:]]*}"}"
        val="${val#"${val%%[![:space:]]*}"}"
        entry=$((entry + 1))
        result+="entry${entry}.section ${section}"$'\n'
        result+="entry${entry}.name ${name}"$'\n'
        [[ -n "$val" ]] && result+="entry${entry}.value ${val}"$'\n'
    done <<< "$text"
    [[ $entry -ge 1 ]] || return 0
    result+="total_entries ${entry}"$'\n'
    echo "$result"
}

strategy_detect () {
    # HINT-ONLY (see header) — never auto-fires.
    _STRATEGY_CONFIDENCE=0
    return 1
}
