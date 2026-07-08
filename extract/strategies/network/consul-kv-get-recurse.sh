#!/bin/bash
## Name: consul-kv-get-recurse
## Description: Extract key/value pairs from `consul kv get -recurse`
## Version: 1.0
## Priority: 20
## Technique: yes
## Sample: samples/consul-kv-get-recurse/basic.txt

# `consul kv get -recurse <prefix>` prints one "path/key:value" line per entry.
# This is a key/value snapshot: emit a single wide record `entry1.<key> value`
# for every pair (path separators sanitised to underscores), then
# total_entries 1.

_ck_san () { local v="$1"; v="${v//$'\t'/_}"; printf '%s' "$v"; }

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    # Signature: every non-empty line is "<a>/<b>...:<value>" (slash-pathed key,
    # colon separator). Require at least two such lines and no line without them.
    # A consul line is `<slash/path>:<single-token-value>` — a '/' appears BEFORE
    # the first ':', and the value has no space, no '=', no further ':'. Excludes
    # /etc/passwd (`root:x:0:...` — colon before slash), blkid (`/dev/sda1: UUID=..`
    # — spaces/'=' in value), and tar listings.
    local line ok=0 n=0 key val
    while IFS= read -r line; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        n=$((n + 1))
        key="${line%%:*}"; val="${line#*:}"
        [[ "$key" == */* ]] || return 1
        [[ "$val" == *:* || "$val" == *" "* || "$val" == *"="* ]] && return 1
        ok=$((ok + 1))
    done <<< "$text"
    [[ $n -ge 2 && $ok -eq $n ]] || return 1
    _STRATEGY_CONFIDENCE=86
    return 0
}

strategy_extract () {
    local text="$1" result="" n=0 line key val
    while IFS= read -r line; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        [[ "$line" == *":"* ]] || continue
        key="${line%%:*}"
        val="${line#*:}"
        key="${key//[[:space:]]/_}"
        key="${key//\//_}"
        key="${key//./_}"
        [[ -n "$key" ]] || continue
        n=$((n + 1))
        result+="entry1.${key} $(_ck_san "$val")"$'\n'
    done <<< "$text"
    [[ $n -gt 0 ]] && result+="total_entries 1"$'\n'
    echo "$result"
}
