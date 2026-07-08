#!/bin/bash
## Name: git-worktree-list-porcelain
## Description: Extract worktrees from `git worktree list --porcelain`
## Version: 1.0
## Priority: 22
## Technique: yes
## Sample: samples/git-worktree-list-porcelain/basic.txt

# Porcelain output is blank-line-separated blocks:
#   worktree /home/user/glean
#   HEAD a1b2c3d4...
#   branch refs/heads/main     (or `detached`)
# One record per worktree block.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    local line has_wt=0 has_head=0
    while IFS= read -r line; do
        [[ "$line" == "worktree "* ]] && has_wt=1
        [[ "$line" =~ ^HEAD[[:space:]][0-9a-f]+ ]] && has_head=1
    done <<< "$text"
    if [[ $has_wt -eq 1 && $has_head -eq 1 ]]; then
        _STRATEGY_CONFIDENCE=86
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line
    local wt="" head="" branch="" have=0

    _flush () {
        [[ $have -eq 1 ]] || return 0
        local w="${wt//$'\t'/_}"
        local h="${head}"
        local b="${branch}"
        entry=$((entry + 1))
        result+="entry${entry}.worktree ${w}"$'\n'
        result+="entry${entry}.head ${h}"$'\n'
        result+="entry${entry}.branch ${b}"$'\n'
        wt=""; head=""; branch=""; have=0
    }

    while IFS= read -r line; do
        case "$line" in
            "worktree "*)
                _flush
                wt="${line#worktree }"; have=1 ;;
            "HEAD "*)
                head="${line#HEAD }" ;;
            "branch "*)
                branch="${line#branch }"
                branch="${branch#refs/heads/}" ;;
            "detached")
                branch="detached" ;;
        esac
    done <<< "$text"
    _flush
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
