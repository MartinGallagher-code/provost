#!/bin/bash
## Name: first-colon-kv
## Description: split each line on its FIRST colon — no space required (redis cluster info, rg --count, redis keys) -> key/value rows — hint-routed
## Version: 1.0
## Priority: 40
## Sample: samples/first-colon-kv/basic.txt

# Some outputs are tight `key:value` with no space after the colon, so the
# space-requiring `colons` parser declines them:
#
#   cluster_state:ok            (redis-cli cluster info)
#   src/main.rs:12              (rg --count: path:count)
#   session:8f3a1c             (redis keys: namespace:id)
#   lock:job:4412
#
# The reviewer's standing note on colon-delimited output is "colons are
# delimiters". Splitting on the FIRST colon gives key | value, and a value may
# itself keep later colons (`lock` | `job:4412`, `src/main.rs` | `12`).
#
# HINT-ONLY: a bare `x:y` line is far too common to auto-detect safely, so this
# never fires on its own — it is reached exclusively through a hints.tsv row.

strategy_extract () {
    local text="$1"
    local line result="" entry=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        local s="${line#"${line%%[![:space:]]*}"}"
        s="${s%"${s##*[![:space:]]}"}"
        [[ -z "$s" ]] && continue
        # Every record must carry a colon and a non-empty key before it; a line
        # that doesn't means this isn't a clean key:value list — bail so the
        # hint falls through to auto-detection.
        [[ "$s" != *:* ]] && return 0
        local key="${s%%:*}" val="${s#*:}"
        [[ -z "$key" ]] && return 0
        key="${key%"${key##*[![:space:]]}"}"
        val="${val#"${val%%[![:space:]]*}"}"
        entry=$((entry + 1))
        result+="entry${entry}.key ${key}"$'\n'
        [[ -n "$val" ]] && result+="entry${entry}.value ${val}"$'\n'
    done <<< "$text"
    [[ $entry -ge 2 ]] || return 0
    result+="total_entries ${entry}"$'\n'
    echo "$result"
}

# Auto-detect fires ONLY on the unambiguous `path:integer` list (rg/ugrep
# --count): every non-blank line is a single colon-joined token whose tail is a
# plain integer and nothing else. That strict, whole-line shape excludes the
# many `word:value` outputs (ruff `f.py:12:5: msg`, passwd `root:x:0:…`, ARNs)
# that share only a first colon. Tight `key:value` configs (redis cluster info)
# reach the same extractor through a hints.tsv row instead.
_fck_count_re='^[^[:space:]:]+:[0-9]+$'

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    local line n=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        [[ "$line" =~ $_fck_count_re ]] || return 1
        n=$((n + 1))
    done <<< "$text"
    [[ $n -ge 2 ]] || return 1
    _STRATEGY_CONFIDENCE=75
    return 0
}
