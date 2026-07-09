#!/bin/bash
## Name: dig-answer
## Description: Extract DNS answer/delegation records from dig output (NS/ANY/+trace/+noall+answer)
## Version: 1.0
## Priority: 8
## Sample: samples/dig-answer/basic.txt

# Merged parser for the dig report variants whose answer rows share the generic
# shape `name TTL IN TYPE value` and want no per-type column split (unlike
# `dig-mx` → preference/exchange and `dig-txt` → text, which keep their own
# strategies). It covers, with one code path:
#   dig NS     — ANSWER SECTION lists a zone's nameservers
#   dig ANY    — ANSWER SECTION carries mixed record types
#   dig +trace — several delegation groups separated by `;; Received …`
#   dig +noall +answer — only answer rows, no comments/markers at all
# We emit one record per answer row across all groups; `;`-comment lines, section
# markers and blanks are skipped.

# Does the whitespace-split line look like a dig answer row?  name TTL IN TYPE value…
# Args are the fields, 1-indexed: $1=name $2=TTL $3=class(IN) $4=type $5…=value.
_dig_answer_row () {
    [[ $# -ge 5 && "$3" == "IN" && "$2" =~ ^[0-9]+$ ]]
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=86
    local line banner=0 answer=0 pure=1 seen=0
    while IFS= read -r line; do
        [[ "$line" == *"<<>>"*"NS "* || "$line" == *"<<>>"*"ANY"* || "$line" == *"<<>>"*"+trace"* ]] && banner=1
        [[ -z "$line" ]] && continue
        [[ "$line" == ";"* ]] && { pure=0; continue; }
        local -a f=(); read -ra f <<< "$line"
        if _dig_answer_row "${f[@]}"; then answer=1; seen=1; else pure=0; fi
    done <<< "$text"
    # A full NS/ANY/+trace report (banner + at least one answer row) …
    [[ $banner -eq 1 && $answer -eq 1 ]] && return 0
    # … or a bare `+noall +answer` dump (every non-blank line is an answer row).
    [[ $pure -eq 1 && $seen -eq 1 ]] && return 0
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line
    while IFS= read -r line; do
        [[ -z "$line" || "$line" == ";"* ]] && continue
        local -a f=()
        read -ra f <<< "$line"
        _dig_answer_row "${f[@]}" || continue
        local val="" i
        for ((i=4; i<${#f[@]}; i++)); do
            if [[ -z "$val" ]]; then val="${f[$i]}"; else val="${val}_${f[$i]}"; fi
        done
        entry=$((entry + 1))
        result+="entry${entry}.name ${f[0]}"$'\n'
        result+="entry${entry}.ttl ${f[1]}"$'\n'
        result+="entry${entry}.class ${f[2]}"$'\n'
        result+="entry${entry}.type ${f[3]}"$'\n'
        result+="entry${entry}.value ${val}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    printf '%s' "$result"
}
