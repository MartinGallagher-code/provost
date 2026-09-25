#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: stat-file
## Description: Extract fields from `stat <file>` output
## Version: 1.0
## Priority: 10
## Sample: samples/stat-file/basic.txt

# `stat` packs several `Key: value` pairs onto each line:
#
#     File: /etc/hostname
#     Size: 3          Blocks: 8          IO Block: 4096   regular file
#   Device: 254,0      Inode: 151336      Links: 1
#   Access: (0644/-rw-r--r--)  Uid: (0/root)  Gid: (0/root)
#   Access: 2026-08-12 20:23:55...   <- SECOND Access key: a timestamp
#
# A generic kv parser splits only the first pair per line, burying Blocks /
# IO Block / Inode / Links / Uid / Gid inside values — and the two different
# `Access:` keys (permission mode vs timestamp) collide. The shape is fixed,
# so parse it as itself: split every pair, name the file-type tail, and
# disambiguate access_mode from access_time by their position.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    if [[ "$text" =~ (^|$'\n')[[:space:]]*File:[[:space:]] ]] \
       && [[ "$text" == *"Size:"*"Blocks:"* ]] \
       && [[ "$text" == *"Inode:"* ]]; then
        _STRATEGY_CONFIDENCE=92
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" line
    while IFS= read -r line; do
        [[ "${line}" != *[![:space:]]* ]] && continue
        local body="${line#"${line%%[![:space:]]*}"}"
        case "$body" in
            "File: "*)
                result+="file ${body#File: }"$'\n' ;;
            "Size: "*)
                # Size: N  Blocks: N  IO Block: N  <file type tail>
                local rest="${body#Size: }"
                local size="${rest%%[[:space:]]*}"
                result+="size ${size}"$'\n'
                if [[ "$rest" == *"Blocks: "* ]]; then
                    local blk="${rest#*Blocks: }"
                    result+="blocks ${blk%%[[:space:]]*}"$'\n'
                fi
                if [[ "$rest" == *"IO Block: "* ]]; then
                    local iob="${rest#*IO Block: }"
                    result+="io_block ${iob%%[[:space:]]*}"$'\n'
                    # everything after the IO Block number is the file type
                    local tail="${iob#*[[:space:]]}"
                    tail="${tail#"${tail%%[![:space:]]*}"}"
                    [[ -n "$tail" && "$tail" != "$iob" ]] && result+="type ${tail}"$'\n'
                fi ;;
            "Device: "*)
                local rest="${body#Device: }"
                result+="device ${rest%%[[:space:]]*}"$'\n'
                if [[ "$rest" == *"Inode: "* ]]; then
                    local ino="${rest#*Inode: }"
                    result+="inode ${ino%%[[:space:]]*}"$'\n'
                fi
                if [[ "$rest" == *"Links: "* ]]; then
                    local lnk="${rest#*Links: }"
                    result+="links ${lnk%%[[:space:]]*}"$'\n'
                fi ;;
            "Access: ("*)
                # the mode line: Access: (0644/-rw-r--r--)  Uid: (...)  Gid: (...)
                local rest="${body#Access: }"
                local mode="${rest%%)*}"
                result+="access_mode ${mode#(}"$'\n'
                if [[ "$rest" == *"Uid: ("* ]]; then
                    local uid="${rest#*Uid: (}"
                    uid="${uid%%)*}"
                    uid="${uid//[[:space:]]/}"
                    result+="uid ${uid}"$'\n'
                fi
                if [[ "$rest" == *"Gid: ("* ]]; then
                    local gid="${rest#*Gid: (}"
                    gid="${gid%%)*}"
                    gid="${gid//[[:space:]]/}"
                    result+="gid ${gid}"$'\n'
                fi ;;
            "Access: "*)
                result+="access_time ${body#Access: }"$'\n' ;;
            "Modify: "*)
                result+="modify_time ${body#Modify: }"$'\n' ;;
            "Change: "*)
                result+="change_time ${body#Change: }"$'\n' ;;
            "Birth: "*)
                result+="birth_time ${body#Birth: }"$'\n' ;;
            *)
                # keep anything unrecognised rather than dropping it
                result+="info ${body}"$'\n' ;;
        esac
    done <<< "$text"
    echo "$result"
}
