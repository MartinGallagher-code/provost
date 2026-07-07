#!/bin/bash
## Name: biosdecode
## Description: `biosdecode` SMBIOS entry-point block (address/length/counts snapshot)
## Version: 1.0
## Priority: 26
## Technique: yes
## Sample: samples/biosdecode/basic.txt

# `biosdecode` prints entry-point structures ("SMBIOS x.y present." followed by
# indented "Some Label <value>" detail lines). There is no colon separator, so
# generic key/value parsers cannot find the fields. This lifts the SMBIOS
# entry-point block into one wide record: the value is the first numeric / hex
# token on each indented line, the label is the words before it.

_bios_key () {
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

    # Distinctive: the "# biosdecode <ver>" banner or the SMBIOS present line
    # together with a "Structure Table" detail line.
    [[ "$text" == *"# biosdecode "* ]] || \
        { [[ "$text" == *"SMBIOS "*" present."* ]] && [[ "$text" == *"Structure Table "* ]]; } || return 1

    _STRATEGY_CONFIDENCE=86
    return 0
}

strategy_extract () {
    local text="$1"
    local result="" line trimmed in_block=0 key val tok
    local -a toks

    while IFS= read -r line; do
        trimmed="${line//[[:space:]]/}"
        [[ -z "$trimmed" ]] && continue

        # SMBIOS entry-point header: capture the version, start the block.
        if [[ "$line" =~ ^SMBIOS[[:space:]]+([0-9][0-9.]*)[[:space:]]+present ]]; then
            result+="entry1.smbios_version ${BASH_REMATCH[1]}"$'\n'
            in_block=1
            continue
        fi

        # A non-indented, non-blank line ends the SMBIOS block.
        if [[ "$line" != [[:space:]]* ]]; then
            [[ $in_block -eq 1 ]] && break
            continue
        fi

        [[ $in_block -eq 1 ]] || continue

        # Indented detail line: "Label words 0x1234." — strip trailing period,
        # split at the first numeric/hex token.
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%.}"
        toks=(); read -ra toks <<< "$line"
        key=""; val=""
        for tok in "${toks[@]}"; do
            if [[ "$tok" =~ ^0x[0-9A-Fa-f]+$ || "$tok" =~ ^[0-9]+$ ]]; then
                val="$tok"
                break
            fi
            [[ -n "$key" ]] && key+=" "
            key+="$tok"
        done
        [[ -z "$val" ]] && continue
        key="$(_bios_key "$key")"
        [[ -z "$key" ]] && continue
        result+="entry1.${key} ${val}"$'\n'
    done <<< "$text"

    result+="total_entries 1"$'\n'
    printf '%s' "$result"
}
