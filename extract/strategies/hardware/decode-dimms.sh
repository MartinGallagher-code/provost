#!/bin/bash
## Name: decode-dimms
## Description: `decode-dimms` SPD EEPROM snapshot ("field <TAB> value" block)
## Version: 1.0
## Priority: 26
## Sample: samples/decode-dimms/basic.txt

# `decode-dimms` prints the SPD EEPROM contents as "Field name<TABs>value"
# lines under "---=== ... ===---" section banners. The tab alignment and the
# multi-word, multi-word values (e.g. "16 x 16 x 10 x 64") defeat generic
# key/value parsers. This lifts the whole SPD snapshot into one wide record.

_dimms_key () {
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

_dimms_val () {
    local v="$1"
    v="${v//$'\t'/ }"
    while [[ "$v" == *"  "* ]]; do v="${v//  / }"; done
    v="${v# }"; v="${v% }"
    printf '%s' "$v"
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0

    # Distinctive: the decode-dimms banner or the SPD EEPROM section title.
    [[ "$text" == *"decode-dimms"* || "$text" == *"SPD EEPROM Information"* ]] || return 1

    _STRATEGY_CONFIDENCE=86
    return 0
}

strategy_extract () {
    local text="$1"
    local result="" line key val

    while IFS= read -r line; do
        # Only "field<TAB>value" data lines carry a tab.
        [[ "$line" == *$'\t'* ]] || continue
        # Skip section banners and the "# decode-dimms version" comment banner
        # (but keep real fields like "# of bytes written to SDRAM EEPROM").
        [[ "$line" == "# decode-dimms"* || "$line" == *"==="* ]] && continue

        key="${line%%$'\t'*}"
        val="${line#*$'\t'}"
        key="$(_dimms_key "$key")"
        [[ -z "$key" ]] && continue
        val="$(_dimms_val "$val")"
        [[ -z "$val" ]] && continue
        result+="entry1.${key} ${val}"$'\n'
    done <<< "$text"

    result+="total_entries 1"$'\n'
    printf '%s' "$result"
}
