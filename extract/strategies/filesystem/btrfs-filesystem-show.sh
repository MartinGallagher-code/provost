#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: btrfs-filesystem-show
## Description: Extract per-device rows from `btrfs filesystem show` output
## Version: 1.1
## Priority: 27
## Sample: samples/btrfs-filesystem-show/basic.txt

# Each filesystem is a `Label: 'x'  uuid: …` header, a `Total devices N FS
# bytes used …` summary, then one `devid … path /dev/…` row per device.
#
# v1.0 emitted only the devid rows, so a two-filesystem capture came out as
# three anonymous device rows with no way to tell which filesystem each
# belonged to, and the label, uuid, device count and used-bytes were dropped
# entirely — the reviewer's "lost data". v1.1 carries the header down onto
# every device row, which is what makes the rows tidy: without it the table
# has no key.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    _is_json "$text" && return 1
    # `btrfs filesystem show` is distinctive: `Label:` + `uuid:` headers, a
    # `Total devices N FS bytes used ...` line, and `devid ... path /dev/...` rows.
    local has_label=0 has_total=0 has_devid=0
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "$line" == "Label:"* && "$line" == *"uuid:"* ]] && has_label=1
        [[ "$line" == *"Total devices"* && "$line" == *"FS bytes used"* ]] && has_total=1
        [[ "$line" == *"devid"* && "$line" == *"path "* ]] && has_devid=1
    done
    if [[ $has_label -eq 1 && $has_total -eq 1 && $has_devid -eq 1 ]]; then
        _STRATEGY_CONFIDENCE=88
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local entry=0
    local label="" uuid="" total_devices="" fs_used=""
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        # `Label: 'data'  uuid: 3f8a…` opens a filesystem: remember it so the
        # device rows below can carry it.
        if [[ "$line" == "Label:"* && "$line" == *"uuid:"* ]]; then
            label="${line#*Label:}"; label="${label%%uuid:*}"
            label="${label#"${label%%[![:space:]]*}"}"
            label="${label%"${label##*[![:space:]]}"}"
            label="${label#\'}"; label="${label%\'}"
            uuid="${line#*uuid:}"
            uuid="${uuid#"${uuid%%[![:space:]]*}"}"
            uuid="${uuid%%[[:space:]]*}"
            total_devices=""; fs_used=""
            continue
        fi
        # `Total devices 2 FS bytes used 412.83GiB` — the filesystem's own
        # summary, previously dropped.
        if [[ "$line" == *"Total devices"* && "$line" == *"FS bytes used"* ]]; then
            total_devices="${line#*Total devices}"
            total_devices="${total_devices#"${total_devices%%[![:space:]]*}"}"
            total_devices="${total_devices%%[[:space:]]*}"
            fs_used="${line#*FS bytes used}"
            fs_used="${fs_used#"${fs_used%%[![:space:]]*}"}"
            fs_used="${fs_used%%[[:space:]]*}"
            continue
        fi

        # Device rows look like: devid  1 size 931.51GiB used 420.00GiB path /dev/sda1
        [[ "$line" == *"devid"* && "$line" == *"path "* ]] || continue

        { _fr_tok "$line"; f=("${_FR_TOK[@]}"); }
        # Pull each field by position relative to its keyword.
        local devid="" size="" used="" path=""
        local i
        for ((i = 0; i < ${#f[@]}; i++)); do
            case "${f[$i]}" in
                devid) devid="${f[$((i + 1))]}" ;;
                size)  size="${f[$((i + 1))]}" ;;
                used)  used="${f[$((i + 1))]}" ;;
                path)  path="${f[$((i + 1))]}" ;;
            esac
        done
        [[ -n "$devid" && -n "$path" ]] || continue

        entry=$((entry + 1))
        result+="entry${entry}.label ${label}"$'\n'
        result+="entry${entry}.uuid ${uuid}"$'\n'
        result+="entry${entry}.total_devices ${total_devices}"$'\n'
        result+="entry${entry}.fs_bytes_used ${fs_used}"$'\n'
        result+="entry${entry}.devid ${devid}"$'\n'
        result+="entry${entry}.size ${size}"$'\n'
        result+="entry${entry}.used ${used}"$'\n'
        result+="entry${entry}.path ${path}"$'\n'
    done
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
