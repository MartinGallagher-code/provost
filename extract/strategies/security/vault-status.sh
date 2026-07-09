#!/bin/bash
## Name: vault-status
## Description: Extract the aligned Key/Value snapshot from `vault status` output
## Version: 1.0
## Priority: 18
## Sample: samples/vault-status/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    # Distinctive signature: a "Key   Value" header, a "--- -----" underline,
    # and Vault-specific keys such as "Seal Type". df-h.txt has none of these.
    local line hdr=0 sep=0 seal=0
    while IFS= read -r line; do
        case "$line" in
            "Key"[[:space:]]*"Value"*) hdr=1 ;;
        esac
        case "$line" in
            "---"[[:space:]]*"---"*) sep=1 ;;
        esac
        case "$line" in
            "Seal Type"[[:space:]]*) seal=1 ;;
        esac
    done <<< "$text"
    if [[ $hdr -eq 1 && $sep -eq 1 && $seal -eq 1 ]]; then
        _STRATEGY_CONFIDENCE=86
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" line n=0
    while IFS= read -r line; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        # Skip the "Key   Value" header and the "--- -----" underline.
        case "$line" in
            "Key"[[:space:]]*"Value"*) continue ;;
            "---"*) continue ;;
        esac
        # Split at the first run of 2+ spaces: everything before is the key
        # (may contain single spaces, e.g. "Seal Type"), the rest is the value.
        local key value
        if [[ "$line" =~ ^(.*[^[:space:]])[[:space:]][[:space:]]+(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
        else
            continue
        fi
        # Trim trailing whitespace on the value.
        value="${value%"${value##*[![:space:]]}"}"
        # Sanitise key into a field name ("Seal Type" -> Seal_Type).
        local field="${key// /_}"
        [[ -n "$field" ]] || continue
        result+="entry1.${field} ${value}"$'\n'
    done <<< "$text"
    [[ -n "$result" ]] && result+="total_entries 1"$'\n'
    printf '%s' "$result"
}
