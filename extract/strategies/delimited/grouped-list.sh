#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: grouped-list
## Description: Single-token group labels over indented single-token members (asdf list: tool over its versions)
## Version: 1.0
## Priority: 49
## Sample: samples/grouped-list/basic.txt

# asdf and similar version managers print each tool as an unindented label with
# its installed versions indented beneath, the active one flagged `*`:
#
#   nodejs
#    *20.14.0
#     22.4.1
#   python
#     3.11.9
#    *3.12.4
#
# A flat line list (line-records) loses the tool→version grouping and keeps the
# `*` glued to the version. The tidy shape carries the label down: one row per
# member — `group`, `value`, and a `current` flag when the `*` marks it.

# Leading-space count of $1 -> _GL_IND
_gl_indent () {
    local l="$1" i=0
    while [[ "${l:$i:1}" == ' ' || "${l:$i:1}" == $'\t' ]]; do i=$((i + 1)); done
    _GL_IND=$i
}

# A member line: indented, and its content (after an optional `*` marker) is a
# SINGLE token. Sets _GL_VAL / _GL_CUR. A group label: unindented single token.
_gl_classify () {   # $1 = raw line -> _GL_KIND (G|M|X), _GL_VAL, _GL_CUR
    local l="$1"
    _GL_KIND=X; _GL_VAL=""; _GL_CUR=""
    [[ -z "${l//[[:space:]]/}" ]] && return
    _gl_indent "$l"
    local body="${l#"${l%%[![:space:]]*}"}"    # lstrip
    body="${body%"${body##*[![:space:]]}"}"    # rstrip
    if [[ $_GL_IND -eq 0 ]]; then
        # unindented label: a single bare token, no `*`, and NOT a colon-
        # suffixed section header (`inputs:` telegraf) — that's a kv/list group,
        # not a version-manager tool label.
        [[ "$body" == *[[:space:]]* ]] && return
        [[ "$body" == "*"* ]] && return
        [[ "$body" == *: ]] && return
        _GL_VAL="$body"; _GL_KIND=G
    else
        local cur=""
        if [[ "$body" == "*"* ]]; then cur="*"; body="${body#\*}"; fi
        body="${body#"${body%%[![:space:]]*}"}"
        [[ "$body" == *[[:space:]]* ]] && return   # multi-token → not a bare version
        [[ -z "$body" ]] && return
        # A member must look like a VERSION: single token, carries an ASCII
        # digit, and holds no `:` — so a colon kv leaf (nodetool gossipinfo's
        # `generation:1718…`) and a word-only tree node (CJK hierarchy) stay
        # with indented-hierarchy / the flat list, not here.
        [[ "$body" == *:* ]] && return
        [[ "$body" =~ [0-9] ]] || return
        _GL_VAL="$body"; _GL_CUR="$cur"; _GL_KIND=M
    fi
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    local line groups=0 members=0 last_was_group=0 bad=0 any=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        any=1
        _gl_classify "$line"
        case "$_GL_KIND" in
            G) groups=$((groups + 1)); last_was_group=1 ;;
            M) members=$((members + 1)); last_was_group=0 ;;
            X) bad=1; break ;;
        esac
    done <<< "$text"
    # Every non-blank line must classify (no stragglers), with >=2 groups and
    # >=1 member per group on average — the asdf signature, nothing looser.
    [[ $bad -eq 1 || $any -eq 0 ]] && return 1
    [[ $groups -ge 2 && $members -ge $groups ]] || return 1
    _STRATEGY_CONFIDENCE=78
    return 0
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 group="" line
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        _gl_classify "$line"
        case "$_GL_KIND" in
            G) group="$_GL_VAL" ;;
            M)
                [[ -z "$group" ]] && continue
                entry=$((entry + 1))
                result+="entry${entry}.group ${group}"$'\n'
                result+="entry${entry}.value ${_GL_VAL}"$'\n'
                [[ -n "$_GL_CUR" ]] && result+="entry${entry}.current true"$'\n'
                ;;
        esac
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
