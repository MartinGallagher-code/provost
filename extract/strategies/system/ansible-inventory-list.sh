#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: ansible-inventory-list
## Description: Extract hosts from `ansible-inventory --list` JSON (keys under _meta.hostvars)
## Version: 1.0
## Priority: 9
## Sample: samples/ansible-inventory-list/basic.txt

# `ansible-inventory --list` emits a JSON document whose real inventory of hosts
# lives under `_meta.hostvars` (the top-level group keys like "all"/"webservers"
# are groupings, not hosts). Each direct key of `_meta.hostvars` is a managed
# host; each becomes a single-field record.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    # Positively identify the ansible inventory JSON by its distinctive
    # _meta.hostvars structure (do not rely on a JSON guard declining).
    case "$text" in
        '{'*) ;;
        *) return 1 ;;
    esac
    [[ "$text" == *'"_meta"'* ]] || return 1
    [[ "$text" == *'"hostvars"'* ]] || return 1
    _STRATEGY_CONFIDENCE=86
    return 0
}

# Echo the direct child keys of _meta.hostvars, one per line. Tracks brace depth
# so nested hostvar keys (e.g. "ansible_host") are ignored. mawk-safe.
_ansible_inventory_hosts () {
    awk '
    {
        L=$0
        if (capture==1 && d==target) {
            if (match(L, /"[^"]+"[ \t]*:[ \t]*\{[ \t]*$/)) {
                s=substr(L, RSTART, RLENGTH)
                match(s, /"[^"]+"/)
                print substr(s, RSTART+1, RLENGTH-2)
            }
        }
        if (L ~ /"hostvars"[ \t]*:/) { target=d+1; capture=1 }
        o=gsub(/\{/,"x",L); c=gsub(/\}/,"y",L); d=d+o-c
        if (capture==1 && d<target) capture=0
    }'
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 host
    while IFS= read -r host; do
        [[ -z "$host" ]] && continue
        host="${host//[[:space:]]/_}"
        entry=$((entry + 1))
        result+="entry${entry}.hostname ${host}"$'\n'
    done <<< "$(printf '%s\n' "$text" | _ansible_inventory_hosts)"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
