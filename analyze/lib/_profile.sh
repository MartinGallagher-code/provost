#!/bin/bash
################################################################################
## Profile management for envoy-analyze
##
## Save and load analysis selection profiles.
##
## Reads:  (function arguments only — name + dir)
## Writes: (none — file I/O to profile directory)
################################################################################

load_profile () {
    local name="$1"
    local dir="$2"
    local file="$dir/$name.profile"
    [[ -f "$file" ]] || err "Profile not found: $file"
    cat "$file"
}

save_profile () {
    local name="$1"
    local dir="$2"
    local list="$3"
    if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        err "Invalid profile name: '$name' (use only alphanumeric, hyphens, underscores)"
    fi
    if ! mkdir -p "$dir" 2>/dev/null; then
        err "Cannot create profile directory: $dir"
    fi
    if ! echo "$list" > "$dir/$name.profile"; then
        err "Cannot write profile: $dir/$name.profile"
    fi
}
