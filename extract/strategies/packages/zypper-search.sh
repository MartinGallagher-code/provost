#!/bin/bash
## Name: zypper-search
## Description: Extract package rows from `zypper search` pipe-delimited output
## Version: 1.0
## Priority: 26
## Technique: yes
## Sample: samples/zypper-search/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    # Distinctive signature: a "S | Name | Summary | Type" header, a "--+--+--"
    # separator, and pipe-delimited rows. df-h.txt has no pipes and declines.
    local line hdr=0 sep=0
    while IFS= read -r line; do
        case "$line" in
            *"| Name "*"| Summary "*"| Type"*) hdr=1 ;;
        esac
        case "$line" in
            *"-+-"*) sep=1 ;;
        esac
    done <<< "$text"
    if [[ $hdr -eq 1 && $sep -eq 1 ]]; then
        _STRATEGY_CONFIDENCE=86
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line seen_sep=0
    while IFS= read -r line; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        # Skip everything up to and including the "--+--+--" separator, so the
        # 3-line preamble and the header row are dropped.
        case "$line" in
            *"-+-"*) seen_sep=1; continue ;;
        esac
        [[ $seen_sep -eq 0 ]] && continue
        # A data row must be pipe-delimited.
        case "$line" in
            *"|"*) ;;
            *) continue ;;
        esac
        # Split on '|' into status | name | summary | type.
        local IFSbak="$IFS"; IFS='|'
        read -ra cols <<< "$line"
        IFS="$IFSbak"
        [[ ${#cols[@]} -ge 4 ]] || continue
        local status name summary type
        status="$(_zs_trim "${cols[0]}")"
        name="$(_zs_trim "${cols[1]}")"
        summary="$(_zs_trim "${cols[2]}")"
        type="$(_zs_trim "${cols[3]}")"
        status="${status// /_}"
        summary="${summary// /_}"
        entry=$((entry + 1))
        result+="entry${entry}.status ${status}"$'\n'
        result+="entry${entry}.name ${name}"$'\n'
        result+="entry${entry}.summary ${summary}"$'\n'
        result+="entry${entry}.type ${type}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    printf '%s' "$result"
}

# Trim leading/trailing whitespace from a single field.
_zs_trim () {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}
