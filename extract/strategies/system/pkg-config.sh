#!/bin/bash
## Name: pkg-config
## Description: Extract packages from `pkg-config --list-all` output
## Version: 1.0
## Priority: 21
## Sample: samples/pkg-config/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1

    # Decline anything with an all-caps column header (`prlimit`'s
    # "RESOURCE DESCRIPTION SOFT HARD UNITS", ps/who/aws headers). `pkg-config
    # --list-all` never prints a header — its first line is a package — so a
    # multi-token ALL-CAPS first line means this is a real table for
    # aligned-columns, not a name/description list.
    local _first="" _fl
    while IFS= read -r _fl; do
        [[ -z "${_fl//[[:space:]]/}" ]] && continue
        _first="$_fl"; break
    done <<< "$text"
    if [[ "$_first" =~ ^[[:space:]]*[A-Z][A-Z0-9_]*([[:space:]]+[A-Z][A-Z0-9_()%-]*)+[[:space:]]*$ ]]; then
        return 1
    fi

    # Header smell: a real pkg-config list opens with an entry, so its first
    # line carries the " - " name/description separator. A first line WITHOUT
    # " - " followed by lines WITH it is a headed table (yum/dnf repolist's
    # "repo id  repo name  status") — decline it for aligned-columns.
    if [[ "$_first" != *" - "* && "$text" == *" - "* ]]; then
        return 1
    fi

    # Same smell, Title-Case variant: a first line of 3+ tokens that ALL open
    # with a capital ("Username Port From Latest") is a column header, not a
    # package entry — package names are effectively never Title-Case runs.
    local _htoks=() _ht _allcap=1
    read -ra _htoks <<< "$_first"
    if [[ ${#_htoks[@]} -ge 3 ]]; then
        for _ht in "${_htoks[@]}"; do
            [[ "$_ht" =~ ^[A-Z] ]] || { _allcap=0; break; }
        done
        [[ $_allcap -eq 1 ]] && return 1
    fi

    # Distinctive: every line is "<package-name>   <prose description>".
    # A package name starts with a letter and is a single token; the remainder
    # is a free-text description (contains an alphabetic word). Reject anything
    # that looks like a sized/percentage table (df) or an arrow map (ldconfig).
    local lines=0 line _cc=() _t _colon=0
    while IFS= read -r line; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        # No size/percentage tables, no "=>" maps, no parenthesised version lists.
        [[ "$line" == *"%"* || "$line" == *"=>"* ]] && return 1
        local name="${line%%[[:space:]]*}"
        # Package name: starts with a letter, package-ish characters only.
        [[ "$name" =~ ^[A-Za-z][A-Za-z0-9._+-]*$ ]] || return 1
        local rest="${line#"$name"}"
        rest="${rest#"${rest%%[![:space:]]*}"}"
        # Description must be present and contain a real word (2+ letters).
        [[ -n "$rest" && "$rest" =~ [A-Za-z][A-Za-z] ]] || return 1
        # A ` : `-aligned "Label : value" line is a colon key/value block
        # (chage -l, some status dumps) — colon-fields/colons own those, not a
        # pkg-config name/description list (whose descriptions use ` - `, not ` : `).
        [[ "$line" == *" : "* ]] && _colon=$((_colon + 1))
        _t=(); read -ra _t <<< "$line"; _cc+=("${#_t[@]}")
        lines=$((lines + 1))
    done <<< "$text"
    # Mostly colon key/value lines -> decline (let a colon parser split them).
    [[ $lines -ge 2 && $(( _colon * 100 / lines )) -ge 60 ]] && return 1
    # A consistent multi-column table (dominant modal column count >=3) is a real
    # aligned table for aligned-columns (az/aws/dnf/chage/es-cat listings), not a
    # pkg-config name/description list — whose description length (and so column
    # count) varies line to line. Decline it so aligned-columns wins instead of
    # cramming every trailing field into `description`.
    if [[ $lines -ge 2 ]]; then
        local _m=0 _best=0 _a _b _k
        for _a in "${_cc[@]}"; do
            _k=0; for _b in "${_cc[@]}"; do [[ "$_b" -eq "$_a" ]] && _k=$((_k + 1)); done
            [[ $_k -gt $_best ]] && { _best=$_k; _m=$_a; }
        done
        [[ $_m -ge 3 && $(( _best * 100 / lines )) -ge 60 ]] && return 1
        _STRATEGY_CONFIDENCE=88
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0
    local line
    while IFS= read -r line; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        local name="${line%%[[:space:]]*}"
        local desc="${line#"$name"}"
        desc="${desc#"${desc%%[![:space:]]*}"}"
        [[ -z "$name" ]] && continue
        entry=$((entry + 1))
        result+="entry${entry}.name ${name}"$'\n'
        result+="entry${entry}.description ${desc}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
