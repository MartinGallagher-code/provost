#!/bin/bash
## Name: podman-image-tree
## Description: Extract layer rows from `podman image tree`
## Version: 1.0
## Priority: 9
## Technique: yes
## Sample: samples/podman-image-tree/basic.txt

# `podman image tree` prints an image header (`Image ID:` / `Tags:` / `Size:`),
# an `Image Layers` banner, then one tree-drawn layer line per layer:
#   `├── ID: 2edcec3590a4 Size:  83.9MB`
#   `└── ID: 3f371f9dd50e Size:  1.536kB Top Layer of: [...]`
# Emit ONE record per LAYER line (id + size).

_podtree_san () { local v="$1"; v="${v//$'\t'/_}"; v="${v// /_}"; printf '%s' "$v"; }

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    [[ "$text" == *"Image Layers"* ]] || return 1
    [[ "$text" == *"ID:"*"Size:"* ]] || return 1
    _STRATEGY_CONFIDENCE=86
    return 0
}

strategy_extract () {
    local text="$1" result="" entry=0 line rest id size
    while IFS= read -r line; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        # Only the tree-drawn layer lines carry both `ID:` and `Size:`.
        case "$line" in
            *ID:*Size:*) : ;;
            *) continue ;;
        esac
        # Strip everything up to and including "ID:".
        rest="${line#*ID:}"
        rest="${rest#"${rest%%[![:space:]]*}"}"   # ltrim
        id="${rest%%[[:space:]]*}"                 # first token = layer id
        # Size value follows "Size:".
        size="${line#*Size:}"
        size="${size#"${size%%[![:space:]]*}"}"    # ltrim
        size="${size%%[[:space:]]*}"               # first token = size
        [[ -n "$id" ]] || continue
        entry=$((entry + 1))
        result+="entry${entry}.id ${id}"$'\n'
        result+="entry${entry}.size $(_podtree_san "$size")"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    printf '%s' "$result"
}
