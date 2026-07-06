#!/bin/bash
## Name: lsblk
## Description: Extract block device names, sizes, types, and mountpoints from lsblk output
## Version: 2.0
## Priority: 35
## Sample: samples/lsblk/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90
    # Reject JSON
    _is_json "$1" && return 1
    # Look for header with "NAME" and "TYPE" and "SIZE"
    while IFS= read -r line; do
        if [[ "$line" == *"NAME"* && "$line" == *"TYPE"* && "$line" == *"SIZE"* ]]; then
            return 0
        fi
    done <<< "$text"
    return 1
}

# Strip tree-drawing characters from lsblk output lines
_strat_lsblk_strip_tree () {
    local s="$1"
    # Remove common tree characters: box-drawing and ASCII tree markers
    # UTF-8 tree chars: ├─ └─ │ (multi-byte)
    # ASCII fallback: |- `- |
    local changed=1
    while [[ $changed -eq 1 ]]; do
        changed=0
        # Remove leading spaces
        while [[ "$s" == " "* ]]; do s="${s# }"; changed=1; done
        # Remove ASCII tree chars
        case "$s" in
            '|-'*) s="${s#|-}"; changed=1 ;;
            '`-'*) s="${s#\`-}"; changed=1 ;;
            '|'*) s="${s#|}"; changed=1 ;;
            '-'*) s="${s#-}"; changed=1 ;;
        esac
    done
    _LSBLK_STRIPPED="$s"
}

strategy_extract () {
    local text="$1"
    local result=""

    # Find column positions from header
    local header_line=""
    while IFS= read -r line; do
        if [[ "$line" == *"NAME"* && "$line" == *"TYPE"* && "$line" == *"SIZE"* ]]; then
            header_line="$line"
            break
        fi
    done <<< "$text"

    [[ -z "$header_line" ]] && return

    # Parse header column names
    read -ra _hdr <<< "$header_line"
    # Find indices for NAME, SIZE, TYPE, MOUNTPOINT/MOUNTPOINTS
    local name_idx=-1 size_idx=-1 type_idx=-1 mount_idx=-1 ro_idx=-1
    local i
    for ((i=0; i<${#_hdr[@]}; i++)); do
        case "${_hdr[$i]}" in
            NAME) name_idx=$i ;;
            SIZE) size_idx=$i ;;
            TYPE) type_idx=$i ;;
            MOUNTPOINT|MOUNTPOINTS) mount_idx=$i ;;
            RO) ro_idx=$i ;;
        esac
    done

    # Parse data lines into per-device arrays (indexed from 1). Emitting indexed
    # row groups (entry<N>.<field>) — with a '.' the tidy melt recognises — lets
    # capture render lsblk as one row per device instead of welding every device
    # into a single wide record. `lsblk` with MOUNTPOINTS prints a device's extra
    # mountpoints on their own indented continuation lines; those are attached to
    # the current device rather than counted as new devices.
    local -a d_name d_size d_type d_mount
    local dev_n=0
    local past_header=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Skip header line
        if [[ "$line" == *"NAME"* && "$line" == *"TYPE"* && "$line" == *"SIZE"* ]]; then
            past_header=1
            continue
        fi
        [[ $past_header -eq 0 ]] && continue

        # Scan past leading whitespace and tree-drawing glyphs (│ ├ └ ─, ASCII
        # | ` - +) to the first significant character — the start of a device
        # name (alphanumeric) or a mountpoint path ('/'). Skipping to the first
        # '/' or alnum is locale-independent: UTF-8 box glyphs are multi-byte,
        # but none of their bytes are alnum or '/', so they are skipped whether
        # bash slices by byte (C locale) or by character (UTF-8 locale).
        local pos=0 firstsig=""
        while [[ $pos -lt ${#line} ]]; do
            case "${line:$pos:1}" in
                [a-zA-Z0-9/]) firstsig="${line:$pos:1}"; break ;;
            esac
            pos=$((pos + 1))
        done
        [[ -z "$firstsig" ]] && continue

        # A line whose first significant char is '/' is a continuation
        # mountpoint (lsblk prints a device's extra MOUNTPOINTS on their own
        # indented lines, sometimes prefixed with the '│' tree bar). Attach it to
        # the current device rather than treating it as a new device.
        if [[ "$firstsig" == "/" && $dev_n -gt 0 ]]; then
            local rest="${line:$pos}"
            local _mp="${rest%%[[:space:]]*}"
            if [[ -n "${d_mount[$dev_n]:-}" ]]; then
                d_mount[$dev_n]="${d_mount[$dev_n]},${_mp}"
            else
                d_mount[$dev_n]="${_mp}"
            fi
            continue
        fi

        # Device row: parse from the first significant character (device name).
        read -ra _arr <<< "${line:$pos}"
        [[ ${#_arr[@]} -lt 1 ]] && continue

        dev_n=$((dev_n + 1))
        local dev_name="" dev_size="" dev_type="" dev_mount=""

        # Typical lsblk columns: NAME MAJ:MIN RM SIZE RO TYPE MOUNTPOINT
        # After tree stripping: sda1 8:1 0 512M 0 part /boot/efi
        # Check if second field looks like MAJ:MIN (N:N).
        if [[ ${#_arr[@]} -ge 2 && "${_arr[1]}" =~ ^[0-9]+:[0-9]+$ ]]; then
            # Standard format: name maj:min rm size ro type [mount]
            dev_name="${_arr[0]}"
            if [[ $size_idx -ge 0 && ${#_arr[@]} -gt 3 ]]; then
                dev_size="${_arr[3]}"
            fi
            if [[ $type_idx -ge 0 && ${#_arr[@]} -gt 5 ]]; then
                dev_type="${_arr[5]}"
            fi
            if [[ $mount_idx -ge 0 && ${#_arr[@]} -gt 6 ]]; then
                dev_mount="${_arr[6]}"
            fi
        else
            # Simplified format or different column set
            dev_name="${_arr[0]}"
            if [[ $name_idx -ge 0 && $size_idx -ge 0 ]]; then
                local si=$((size_idx - name_idx))
                [[ $si -ge 0 && $si -lt ${#_arr[@]} ]] && dev_size="${_arr[$si]}"
            fi
            if [[ $name_idx -ge 0 && $type_idx -ge 0 ]]; then
                local ti=$((type_idx - name_idx))
                [[ $ti -ge 0 && $ti -lt ${#_arr[@]} ]] && dev_type="${_arr[$ti]}"
            fi
            if [[ $name_idx -ge 0 && $mount_idx -ge 0 ]]; then
                local mi=$((mount_idx - name_idx))
                [[ $mi -ge 0 && $mi -lt ${#_arr[@]} ]] && dev_mount="${_arr[$mi]}"
            fi
        fi

        d_name[$dev_n]="$dev_name"
        d_size[$dev_n]="$dev_size"
        d_type[$dev_n]="$dev_type"
        d_mount[$dev_n]="$dev_mount"
    done <<< "$text"

    # Emit indexed row groups so capture's tidy melt renders one row per device.
    local k
    for ((k=1; k<=dev_n; k++)); do
        [[ -n "${d_name[$k]:-}" ]] && result+="entry${k}.name ${d_name[$k]}"$'\n'
        [[ -n "${d_size[$k]:-}" ]] && result+="entry${k}.size ${d_size[$k]}"$'\n'
        [[ -n "${d_type[$k]:-}" ]] && result+="entry${k}.type ${d_type[$k]}"$'\n'
        [[ -n "${d_mount[$k]:-}" ]] && result+="entry${k}.mount ${d_mount[$k]}"$'\n'
    done
    [[ $dev_n -gt 0 ]] && result+="total_entries ${dev_n}"$'\n'

    echo "$result"
}
