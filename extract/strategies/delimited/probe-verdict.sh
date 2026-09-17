#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: probe-verdict
## Description: chkrootkit-style `Checking \`name'... verdict` probe lines -> name/result rows
## Version: 1.0
## Priority: 37
## Sample: samples/probe-verdict/basic.txt

# Probe reports print one line per check: a constant lead word, the probed
# target (often `backquoted'), a dot-leader run glued to the target, then the
# verdict:
#
#   Checking `ifconfig'... not infected
#   Checking `sshd'... not infected
#   Checking `lkm'... nothing detected
#
# aligned-columns split the verdict across two columns and kept the quoted,
# dotted target as data. The reviewer: "the spacing dots should be deleted;
# the value after the spacing dots should be a single column." The constant
# lead is chrome (same treatment checking-groups gives promtool), the quotes
# are chrome, and the verdict stays whole:
#
#   name      result
#   ifconfig  not infected
#   lkm       nothing detected
#
# Gates: >=3 non-blank lines, EVERY line matches, the lead word is IDENTICAL
# on every line (borg's Keeping/Pruning mix stays out), and the `...` run is
# GLUED to the target token (cargo test's spaced `name ... ok` stays out —
# that's a table, not a dot-leader).

_pv_re="^([A-Za-z]+) (.+)\.\.\.[[:space:]]+(.+)$"

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    local line lead="" n=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        [[ "$line" =~ $_pv_re ]] || return 1
        # Dots glued to the target: the captured target must not end in space.
        [[ "${BASH_REMATCH[2]}" == *" " ]] && return 1
        if [[ -z "$lead" ]]; then lead="${BASH_REMATCH[1]}"
        elif [[ "${BASH_REMATCH[1]}" != "$lead" ]]; then return 1; fi
        n=$((n + 1))
    done <<< "$text"
    [[ $n -ge 3 ]] || return 1
    _STRATEGY_CONFIDENCE=80
    return 0
}

strategy_extract () {
    local text="$1"
    local line result="" entry=0 name
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        [[ "$line" =~ $_pv_re ]] || continue
        name="${BASH_REMATCH[2]}"
        # Strip `backquote' quoting chrome.
        name="${name#\`}"
        name="${name%\'}"
        entry=$((entry + 1))
        result+="entry${entry}.name ${name}"$'\n'
        result+="entry${entry}.result ${BASH_REMATCH[3]}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
