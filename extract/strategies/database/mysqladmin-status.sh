#!/bin/bash
## Name: mysqladmin-status
## Description: `mysqladmin status` single line of "Key: value" pairs
## Version: 1.0
## Priority: 9
## Technique: yes
## Sample: samples/mysqladmin-status/basic.txt

# `mysqladmin status` prints one line of space-padded "Key: value" pairs whose
# keys contain spaces ("Slow queries", "Queries per second avg"). Generic
# key/value parsers split on the first colon and merge everything after it into
# one blob. This tokenises the line into one wide record: a key runs up to the
# token ending in ":", the next token is its value.

_myadm_key () {
    local s="$1" out="" c i n=${#1}
    for ((i = 0; i < n; i++)); do
        c="${s:i:1}"
        case "$c" in
            [A-Za-z0-9]) out+="$c" ;;
            *) out+="_" ;;
        esac
    done
    while [[ "$out" == *__* ]]; do out="${out//__/_}"; done
    out="${out#_}"; out="${out%_}"
    printf '%s' "$out"
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0

    # Exactly one non-blank line.
    local nb=0 first="" line trimmed
    while IFS= read -r line; do
        trimmed="${line//[[:space:]]/}"
        [[ -z "$trimmed" ]] && continue
        nb=$((nb + 1))
        [[ -z "$first" ]] && first="$line"
    done <<< "$text"
    [[ $nb -eq 1 ]] || return 1

    # Distinctive mysqladmin status pairs.
    [[ "$first" == *"Uptime:"* ]] || return 1
    [[ "$first" == *"Threads:"* ]] || return 1
    [[ "$first" == *"Questions:"* ]] || return 1
    [[ "$first" == *"Queries per second"* ]] || return 1

    _STRATEGY_CONFIDENCE=86
    return 0
}

strategy_extract () {
    local text="$1"
    local first="" line trimmed
    while IFS= read -r line; do
        trimmed="${line//[[:space:]]/}"
        [[ -z "$trimmed" ]] && continue
        first="$line"
        break
    done <<< "$text"

    # Tokenise: a key runs across words up to the token ending in ":", then the
    # very next token is its value ("Slow queries: 2", "Queries per second avg:
    # 2.223"). Accumulate every word into the key until the colon token so
    # multi-word keys stay distinct.
    local result="" tok key="" mode="key" san
    local -a toks
    toks=(); read -ra toks <<< "$first"
    for tok in "${toks[@]}"; do
        if [[ "$mode" == "key" ]]; then
            if [[ "$tok" == *: ]]; then
                [[ -n "$key" ]] && key+=" "
                key+="${tok%:}"
                mode="value"
            else
                [[ -n "$key" ]] && key+=" "
                key+="$tok"
            fi
        else
            san="$(_myadm_key "$key")"
            [[ -n "$san" ]] && result+="entry1.${san} ${tok}"$'\n'
            key=""; mode="key"
        fi
    done

    result+="total_entries 1"$'\n'
    printf '%s' "$result"
}
