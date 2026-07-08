#!/bin/bash
## Name: aws-s3-ls
## Description: Extract objects and prefixes from `aws s3 ls` listings
## Version: 1.0
## Priority: 20
## Sample: samples/aws-s3-ls/basic.txt

# `aws s3 ls s3://bucket/` prints one line per object as
#   YYYY-MM-DD HH:MM:SS  <size> <key>
# and one line per common prefix (subdir) as
#                            PRE dir/

_awss3_is_object () {
    [[ "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}[[:space:]]+[0-9]+[[:space:]]+.+$ ]]
}

_awss3_is_prefix () {
    [[ "$1" =~ ^[[:space:]]*PRE[[:space:]]+.+$ ]]
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    local line _hits=0
    while IFS= read -r line; do
        if _awss3_is_object "$line" || _awss3_is_prefix "$line"; then
            _hits=$((_hits + 1))
        fi
    done <<< "$text"
    # Require at least two object/prefix rows. A single "DATE TIME <num> …" line
    # is coincidental (e.g. a `7z`/archive listing's summary row "… 100352 42218
    # 6 files"), and firing on it hijacks a real columnar table.
    if [[ $_hits -ge 2 ]]; then
        _STRATEGY_CONFIDENCE=88
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0
    local line
    while IFS= read -r line; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        if _awss3_is_object "$line"; then
            read -ra _a <<< "$line"
            local date="${_a[0]}" time="${_a[1]}" size="${_a[2]}"
            local name=""
            local i
            for ((i=3; i<${#_a[@]}; i++)); do
                [[ -n "$name" ]] && name+=" "
                name+="${_a[$i]}"
            done
            entry=$((entry + 1))
            result+="entry${entry}.date ${date}"$'\n'
            result+="entry${entry}.time ${time}"$'\n'
            result+="entry${entry}.size ${size}"$'\n'
            result+="entry${entry}.name ${name}"$'\n'
        elif _awss3_is_prefix "$line"; then
            local dir="${line#*PRE }"
            dir="${dir#"${dir%%[![:space:]]*}"}"
            entry=$((entry + 1))
            result+="entry${entry}.type prefix"$'\n'
            result+="entry${entry}.name ${dir}"$'\n'
        fi
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
