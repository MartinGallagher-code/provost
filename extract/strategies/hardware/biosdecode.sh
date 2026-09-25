#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: biosdecode
## Description: `biosdecode` entry-point structures -> section/key/value rows
## Version: 2.0
## Priority: 26
## Sample: samples/biosdecode/basic.txt

# `biosdecode` prints one block per entry-point structure: a flush-left
# `<Name> present.` header followed by TAB-indented `Some Label <value>` detail
# lines. There is no colon separator, so generic key/value parsers cannot find
# the fields.
#
# v2.0 emits every block, as one row per detail line with the block it came
# from in a `section` column. v1.0 lifted only the SMBIOS block into a single
# wide record and silently dropped BIOS32 / PNP BIOS / ACPI — the reviewer's
# "lost a large chunk". Long form is also the honest shape here: the blocks
# share no columns with each other, so a wide record would be mostly holes.

# Where does the label end and the value begin? There is no separator, so it is
# decided by what the value LOOKS like — the first token that is a hex address,
# a bare number, a quoted string, or the start of a `Not Supported` style
# verdict. Everything before it is the label, everything from it on is the
# value (`3084 bytes` keeps its unit; v1.0 kept only `3084`).
_bios_split () {
    _BIOS_KEY=""; _BIOS_VAL=""
    local -a t=(); { _fr_tok "$1"; t=("${_FR_TOK[@]}"); }
    local i n=${#t[@]} tok
    for ((i = 0; i < n; i++)); do
        tok="${t[$i]}"
        if [[ "$tok" =~ ^0x[0-9A-Fa-f] || "$tok" =~ ^[0-9]+$ || "$tok" == \"*  \
              || ( "$tok" == "Not" && $((i + 1)) -lt $n ) ]]; then
            [[ $i -eq 0 ]] && return 1       # no label at all — not a detail line
            _BIOS_KEY="${t[*]:0:i}"
            _BIOS_VAL="${t[*]:i}"
            _BIOS_VAL="${_BIOS_VAL%\"}"; _BIOS_VAL="${_BIOS_VAL#\"}"
            return 0
        fi
    done
    # No value-shaped token: the whole line is the label with an empty value
    # (`Event Notification` style flags that carry no reading).
    _BIOS_KEY="$1"
    return 0
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
    local result="" line trimmed section="" n=0

    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        trimmed="${line//[[:space:]]/}"
        [[ -z "$trimmed" ]] && continue

        # `# biosdecode 3.3` — the tool's own version, kept rather than dropped.
        if [[ "$line" =~ ^#[[:space:]]*biosdecode[[:space:]]+([0-9][0-9.]*) ]]; then
            n=$((n + 1))
            result+="entry${n}.section biosdecode"$'\n'
            result+="entry${n}.key version"$'\n'
            result+="entry${n}.value ${BASH_REMATCH[1]}"$'\n'
            continue
        fi

        # Flush-left line: a new block header. `SMBIOS 3.2.1 present.` ->
        # section `SMBIOS 3.2.1`. A flush-left line that is not a header still
        # closes the block, so stray trailer text is never filed under it.
        if [[ "$line" != [[:space:]]* ]]; then
            line="${line%.}"
            if [[ "$line" == *" present" ]]; then
                section="${line% present}"
            else
                section=""
            fi
            continue
        fi

        [[ -n "$section" ]] || continue

        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%.}"
        _bios_split "$line" || continue
        [[ -n "$_BIOS_KEY" ]] || continue

        n=$((n + 1))
        result+="entry${n}.section ${section}"$'\n'
        result+="entry${n}.key ${_BIOS_KEY}"$'\n'
        result+="entry${n}.value ${_BIOS_VAL}"$'\n'
    done

    [[ $n -gt 0 ]] || return 1
    result+="total_entries ${n}"$'\n'
    printf '%s' "$result"
}
