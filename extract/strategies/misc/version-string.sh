#!/bin/bash
## Name: version-string
## Description: Program version output (node -v, java -version, cmake --version, …)
## Version: 1.0
## Priority: 28
## Sample: samples/version-string/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0

    # Never treat JSON as a version banner.
    _is_json "$text" && return 1

    # Scan for the first non-blank line and count non-blank lines.
    local first="" nb=0 line trimmed
    while IFS= read -r line; do
        trimmed="${line//[[:space:]]/}"
        [[ -z "$trimmed" ]] && continue
        nb=$((nb + 1))
        [[ -z "$first" ]] && first="$line"
    done <<< "$text"

    # Empty input, or too many lines to be a version banner (a data table).
    [[ $nb -eq 0 ]] && return 1
    [[ $nb -le 4 ]] || return 1

    # A real version banner is a short line ("v20.10.0", "cmake version 3.27.4",
    # 'openjdk version "17.0.9" 2023-10-17'). Reject the tab-separated,
    # many-token headers of tools like mpstat/sar ("Linux 6.1.0 (host)\t… \t_x86_64_\t…")
    # whose kernel version would otherwise read as a program version.
    [[ "$first" == *$'\t'* ]] && return 1
    local _vt; _vt=(); read -ra _vt <<< "$first"
    [[ ${#_vt[@]} -le 4 ]] || return 1

    # The FIRST non-blank line must carry a semantic version token:
    # [0-9]+.[0-9]+(.[0-9]+)? optionally prefixed by a 'v'. Being specific here
    # keeps this from stealing tables, whose header rows have no version number.
    if [[ "$first" =~ v?[0-9]+\.[0-9]+(\.[0-9]+)? ]]; then
        _STRATEGY_CONFIDENCE=82
        return 0
    fi

    return 1
}

strategy_extract () {
    local text="$1"
    local result=""

    # First non-blank line is the version banner.
    local first="" line trimmed
    while IFS= read -r line; do
        trimmed="${line//[[:space:]]/}"
        [[ -z "$trimmed" ]] && continue
        first="$line"
        break
    done <<< "$text"

    # First version-number token, with any leading 'v' stripped.
    local version=""
    if [[ "$first" =~ v?([0-9]+\.[0-9]+(\.[0-9]+)?) ]]; then
        version="${BASH_REMATCH[1]}"
    fi

    # Product = first whitespace-delimited word of the first line
    # ("node -> v20.10.0", "openjdk", "cmake").
    local product="${first%%[[:space:]]*}"

    # Raw = the whole first line, spaces collapsed to underscores so the value
    # stays a single token in the key/value stream.
    local raw="$first"
    raw="${raw//	/ }"
    raw="${raw// /_}"

    # One record; version plus product and raw give the melt >= 2 columns.
    result+="entry1.version ${version}"$'\n'
    result+="entry1.product ${product}"$'\n'
    result+="entry1.raw ${raw}"$'\n'
    result+="total_entries 1"$'\n'

    echo "$result"
}
