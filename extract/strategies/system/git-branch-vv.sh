#!/bin/bash
## Name: git-branch-vv
## Description: Extract branch rows from `git branch -vv`
## Version: 1.0
## Priority: 9
## Technique: yes
## Sample: samples/git-branch-vv/basic.txt

# `git branch -vv` prints one line per branch:
#   `* main            a1b2c3d [origin/main] Fix null pointer ...`
#   `  hotfix/urgent   7c6b5a4 Refactor session handling`
# Leading `*` marks the current branch, then the branch name, a 7-hex short SHA,
# an optional `[upstream ...]` tracking block, then the commit subject. Emit ONE
# record per branch (name, sha, upstream). Detection keys narrowly on a
# `<name> <7-hex> [` signature so it declines vmstat/dstat/apt-list/dnf-list.

_gbvv_san () { local v="$1"; v="${v//$'\t'/_}"; v="${v// /_}"; printf '%s' "$v"; }

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    # Require at least one canonical branch line: optional `* `, a branch name,
    # a 7-hex short SHA, then a `[upstream]` tracking block.
    local line hit=0
    while IFS= read -r line; do
        if [[ "$line" =~ ^(\*[[:space:]]|[[:space:]][[:space:]])[[:space:]]*[^[:space:]]+[[:space:]]+[0-9a-f]{7}[[:space:]]+\[ ]]; then
            hit=1; break
        fi
    done <<< "$text"
    [[ $hit -eq 1 ]] || return 1
    _STRATEGY_CONFIDENCE=86
    return 0
}

strategy_extract () {
    local text="$1" result="" entry=0 line body name sha rest up
    while IFS= read -r line; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        # Drop the leading current-branch marker.
        body="$line"
        body="${body#\*}"
        body="${body#"${body%%[![:space:]]*}"}"   # ltrim
        name="${body%%[[:space:]]*}"              # branch name
        rest="${body#"$name"}"
        rest="${rest#"${rest%%[![:space:]]*}"}"   # ltrim to SHA
        sha="${rest%%[[:space:]]*}"
        # Require a 7-hex short SHA to accept the row.
        [[ "$sha" =~ ^[0-9a-f]{7}$ ]] || continue
        rest="${rest#"$sha"}"
        rest="${rest#"${rest%%[![:space:]]*}"}"   # ltrim
        up="-"
        if [[ "$rest" == \[* ]]; then
            up="${rest#\[}"; up="${up%%\]*}"      # content inside [...]
        fi
        entry=$((entry + 1))
        result+="entry${entry}.name $(_gbvv_san "$name")"$'\n'
        result+="entry${entry}.sha ${sha}"$'\n'
        result+="entry${entry}.upstream $(_gbvv_san "$up")"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    printf '%s' "$result"
}
