#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: diffstat
## Description: diffstat blocks (path | N +++--- per file, files-changed summary) — git diff/stash/show --stat
## Version: 1.0
## Priority: 12
## Sample: samples/diffstat/basic.txt

# The diffstat format every git --stat variant (and diffstat(1)) prints:
#
#    src/app.py | 12 ++++++------
#    README.md  |  4 ++++
#    4 files changed, 40 insertions(+), 6 deletions(-)
#
# One record per file line; the summary line becomes scalar fields the melt
# repeats onto every row. A log that carries commit headers (git log --stat)
# belongs to git-log-stat, not here — inputs with `commit <sha>` lines are
# declined.

_diffstat_file_line () {
    # " path | 12 ++++----"  /  " img.png | Bin 0 -> 4096 bytes"
    [[ "$1" =~ ^[[:space:]]*([^|[:space:]][^|]*[^|[:space:]])[[:space:]]*\|[[:space:]]*([0-9]+|Bin[^|]*)([[:space:]]+[+-]+)?[[:space:]]*$ ]]
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    local line hits=0
    while IFS= read -r line; do
        [[ "$line" =~ ^commit[[:space:]][0-9a-f]{7,} ]] && return 1
        _diffstat_file_line "$line" && hits=$((hits + 1))
    done <<< "$text"
    if [[ $hits -ge 2 && "$text" == *" changed"* ]]; then
        _STRATEGY_CONFIDENCE=88
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1" result="" line entry=0 summary=""
    local file changes graph
    while IFS= read -r line; do
        if _diffstat_file_line "$line"; then
            file="${BASH_REMATCH[1]}"
            changes="${BASH_REMATCH[2]}"
            graph="${BASH_REMATCH[3]}"
            graph="${graph#"${graph%%[![:space:]]*}"}"
            entry=$((entry + 1))
            result+="entry${entry}.file ${file}"$'\n'
            result+="entry${entry}.changes ${changes// /_}"$'\n'
            [[ -n "$graph" ]] && result+="entry${entry}.graph ${graph}"$'\n'
            continue
        fi
        # " 4 files changed, 40 insertions(+), 6 deletions(-)"
        if [[ "$line" =~ ([0-9]+)[[:space:]]+files?\ changed ]]; then
            summary+="files_changed ${BASH_REMATCH[1]}"$'\n'
            [[ "$line" =~ ([0-9]+)[[:space:]]+insertions?\(\+\) ]] && summary+="insertions ${BASH_REMATCH[1]}"$'\n'
            [[ "$line" =~ ([0-9]+)[[:space:]]+deletions?\(-\) ]] && summary+="deletions ${BASH_REMATCH[1]}"$'\n'
        fi
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="${summary}total_entries ${entry}"$'\n'
    printf '%s' "$result"
}
