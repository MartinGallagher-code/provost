#!/bin/bash
## Name: ansible-version
## Description: `ansible --version` banner (version + config/path/python key=value block)
## Version: 1.0
## Priority: 26
## Technique: yes
## Sample: samples/ansible-version/basic.txt

# `ansible --version` prints "ansible [core X.Y.Z]" followed by an indented
# "key = value" block (config file, module search path, python version, ...).
# Generic key/value parsers split on the first "=" but mangle the values that
# themselves contain spaces / "=" (search paths, python banner). This pulls the
# whole snapshot into one wide record.

_ansver_key () {
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

_ansver_val () {
    local v="$1"
    v="${v//$'\t'/ }"
    while [[ "$v" == *"  "* ]]; do v="${v//  / }"; done
    v="${v# }"; v="${v% }"
    printf '%s' "$v"
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0

    local first="" line trimmed
    while IFS= read -r line; do
        trimmed="${line//[[:space:]]/}"
        [[ -z "$trimmed" ]] && continue
        first="$line"
        break
    done <<< "$text"

    # Distinctive banner: "ansible [core X.Y.Z]" as the first non-blank line.
    [[ "$first" =~ ^ansible[[:space:]]+\[core[[:space:]] ]] || return 1

    _STRATEGY_CONFIDENCE=86
    return 0
}

strategy_extract () {
    local text="$1"
    local result="" line trimmed first="" key val
    local seen_first=0

    while IFS= read -r line; do
        trimmed="${line//[[:space:]]/}"
        [[ -z "$trimmed" ]] && continue

        if [[ $seen_first -eq 0 ]]; then
            seen_first=1
            first="$line"
            # Pull the core version out of "ansible [core 2.16.3]".
            if [[ "$first" =~ \[core[[:space:]]+([^]]+)\] ]]; then
                result+="entry1.core_version $(_ansver_val "${BASH_REMATCH[1]}")"$'\n'
            fi
            continue
        fi

        # Indented "key = value" lines.
        [[ "$line" == *" = "* ]] || continue
        key="${line%% = *}"
        val="${line#* = }"
        key="$(_ansver_key "$key")"
        [[ -z "$key" ]] && continue
        val="$(_ansver_val "$val")"
        result+="entry1.${key} ${val}"$'\n'
    done <<< "$text"

    result+="total_entries 1"$'\n'
    printf '%s' "$result"
}
