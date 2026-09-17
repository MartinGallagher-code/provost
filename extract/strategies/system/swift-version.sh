#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: swift-version
## Description: Extract version fields from `swift --version` banner
## Version: 1.0
## Priority: 20
## Sample: samples/swift-version/basic.txt

# `swift --version` prints "Apple Swift version 5.9.2 (swiftlang-... clang-...)"
# and a "Target: <triple>" line. One wide key/value record: product, version,
# swiftlang, clang, target.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    if [[ "$text" == *"Swift version"* && "$text" == *"Target:"* ]]; then
        _STRATEGY_CONFIDENCE=86
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" ver="" slang="" clang="" target=""
    if [[ "$text" =~ Swift[[:space:]]version[[:space:]]([0-9][0-9A-Za-z.+-]*) ]]; then
        ver="${BASH_REMATCH[1]}"
    fi
    if [[ "$text" =~ swiftlang-([0-9][0-9A-Za-z.+-]*) ]]; then
        slang="${BASH_REMATCH[1]}"
    fi
    if [[ "$text" =~ clang-([0-9][0-9A-Za-z.+-]*) ]]; then
        clang="${BASH_REMATCH[1]}"
    fi
    if [[ "$text" =~ Target:[[:space:]]*([^[:space:]]+) ]]; then
        target="${BASH_REMATCH[1]}"
    fi
    result+="entry1.product Swift"$'\n'
    result+="entry1.version ${ver}"$'\n'
    result+="entry1.swiftlang ${slang}"$'\n'
    result+="entry1.clang ${clang}"$'\n'
    result+="entry1.target ${target}"$'\n'
    result+="total_entries 1"$'\n'
    echo "$result"
}
