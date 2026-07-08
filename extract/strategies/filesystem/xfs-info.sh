#!/bin/bash
## Name: xfs-info
## Description: Extract geometry fields from `xfs_info` (section `key=value` tokens)
## Version: 1.0
## Priority: 9
## Technique: yes
## Sample: samples/xfs-info/basic.txt

# `xfs_info` prints aligned sections (meta-data, data, naming, log, realtime),
# each with several `key=value` tokens spread across continuation lines, e.g.
#   meta-data=/dev/sda2   isize=512    agcount=4, agsize=6553600 blks
#            =            sectsz=512   attr=2, projid32bit=1
# Generic parsers can't cope with the aligned continuations and duplicate token
# names (bsize/sectsz/blocks recur per section). This emits ONE wide record with
# each token as a section-prefixed field, e.g. entry1.meta_data_isize 512.

_xfsinfo_field () {
    local s; s="$(printf '%s' "$1" | tr 'A-Z' 'a-z')"
    local out="" i c
    for ((i=0; i<${#s}; i++)); do
        c="${s:$i:1}"
        case "$c" in
            [a-z0-9_]) out+="$c" ;;
            *) out+="_" ;;
        esac
    done
    printf '%s' "$out"
}

_xfsinfo_sanitize_val () {
    local v="$1"
    v="${v%,}"
    v="${v//$'\t'/_}"
    printf '%s' "$v"
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    # xfs_info signature: the meta-data section header plus its distinctive tokens.
    [[ "$text" == *"meta-data"* ]] || return 1
    [[ "$text" == *"isize="* ]]    || return 1
    [[ "$text" == *"agcount="* ]]  || return 1
    _STRATEGY_CONFIDENCE=86
    return 0
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line section leading tok key val field
    local -a toks
    while IFS= read -r line; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        leading=""
        # A section-starting line begins in column 0; the section name is the run
        # of chars before the first '=' or whitespace (continuation lines are
        # indented and inherit the current section).
        if [[ "$line" =~ ^[^[:space:]] ]]; then
            leading="${line%%[=[:space:]]*}"
            section="$(_xfsinfo_field "$leading")"
        fi
        read -ra toks <<< "$line"
        for tok in "${toks[@]}"; do
            [[ "$tok" == *"="* ]] || continue
            key="${tok%%=*}"
            val="${tok#*=}"
            [[ -n "$key" && "$key" =~ ^[A-Za-z] ]] || continue
            [[ -n "${val%,}" ]] || continue
            if [[ "$key" == "$leading" ]]; then
                field="$section"
            else
                field="${section}_$(_xfsinfo_field "$key")"
            fi
            entry=1
            result+="entry1.${field} $(_xfsinfo_sanitize_val "$val")"$'\n'
        done
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries 1"$'\n'
    echo "$result"
}
