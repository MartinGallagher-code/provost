#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: pkg-config
## Description: Extract packages from `pkg-config --list-all` output
## Version: 1.1
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
    _fr_lines "$text"
    for _fl in "${_FR_LINES[@]}"; do
        [[ "${_fl}" != *[![:space:]]* ]] && continue
        _first="$_fl"; break
    done
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
    { _fr_tok "$_first"; _htoks=("${_FR_TOK[@]}"); }
    if [[ ${#_htoks[@]} -ge 3 ]]; then
        for _ht in "${_htoks[@]}"; do
            [[ "$_ht" =~ ^[A-Z] ]] || { _allcap=0; break; }
        done
        [[ $_allcap -eq 1 ]] && return 1
        # Lowercase variant: 3+ bare identifier tokens ("pool  slots  used_slots",
        # "id  message  status  priority") separated ONLY by column gaps (2+
        # spaces or a tab, never a single space) is a column header. A package
        # entry's prose description always has single-spaced words.
        if [[ "$_first" != *[![:space:]]" "[![:space:]]* ]]; then
            local _allid=1
            for _ht in "${_htoks[@]}"; do
                [[ "$_ht" =~ ^[a-z][A-Za-z0-9_]*$ ]] || { _allid=0; break; }
            done
            [[ $_allid -eq 1 ]] && return 1
        fi
    fi

    # Distinctive: every line is "<package-name>   <prose description>".
    # A package name starts with a letter and is a single token; the remainder
    # is a free-text description (contains an alphabetic word). Reject anything
    # that looks like a sized/percentage table (df) or an arrow map (ldconfig).
    #
    # PV-037: that shape alone is most listings of "a name, then text" — it
    # claimed 60 corpus inputs that are not pkg-config's (`netstat -anp`,
    # `ip -br addr`, `poetry show`, `tox list` ...), each filed as two columns.
    # What `pkg-config --list-all` (and pkgconf's) actually prints is
    # `KEY<padding>Name - Description`: the key padded to one width, so the
    # second field starts in the SAME column on (nearly) every line, and the
    # pc file's Name and Description joined by " - ". The join is required on
    # at least two lines in three (a .pc file may lack a Description). The
    # alignment is required on EVERY line, but for a key too long for the pad
    # (pkgconf pads to 30 columns): its second field starts one space after it.
    # A listing whose first field holds a space ("Nestopia UE   Nintendo - NES")
    # starts its second word out of line, and is declined.
    local lines=0 line _cc=() _t _colon=0 _dash=0 _pcols=() _pklen=()
    local -A _p2col=()
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "${line}" != *[![:space:]]* ]] && continue
        # No size/percentage tables, no "=>" maps, no parenthesised version lists.
        [[ "$line" == *"%"* || "$line" == *"=>"* ]] && return 1
        local name="${line%%[[:space:]]*}"
        # Package name: starts with a letter, package-ish characters only.
        [[ "$name" =~ ^[A-Za-z][A-Za-z0-9._+-]*$ ]] || return 1
        local rest="${line#"$name"}"
        rest="${rest#"${rest%%[![:space:]]*}"}"
        # Description must be present and contain a real word (2+ letters).
        [[ -n "$rest" && "$rest" =~ [A-Za-z][A-Za-z] ]] || return 1
        # the column the second field starts in, and the " - " join
        _p2col[$(( ${#line} - ${#rest} ))]=$(( ${_p2col[$(( ${#line} - ${#rest} ))]:-0} + 1 ))
        _pcols+=($(( ${#line} - ${#rest} ))); _pklen+=("${#name}")
        [[ "$rest" == *[![:space:]]" - "[![:space:]]* ]] && _dash=$((_dash + 1))
        # A ` : `-aligned "Label : value" line is a colon key/value block
        # (chage -l, some status dumps) — colon-fields/colons own those, not a
        # pkg-config name/description list (whose descriptions use ` - `, not ` : `).
        [[ "$line" == *" : "* ]] && _colon=$((_colon + 1))
        _t=(); { _fr_tok "$line"; _t=("${_FR_TOK[@]}"); }; _cc+=("${#_t[@]}")
        lines=$((lines + 1))
    done
    # Mostly colon key/value lines -> decline (let a colon parser split them).
    [[ $lines -ge 2 && $(( _colon * 100 / lines )) -ge $(( 60 + ${_FR_SLACK:-0} )) ]] && return 1
    # A consistent multi-column table (dominant modal column count >=3) is a real
    # aligned table for aligned-columns (az/aws/dnf/chage/es-cat listings), not a
    # pkg-config name/description list — whose description length (and so column
    # count) varies line to line. Decline it so aligned-columns wins instead of
    # cramming every trailing field into `description`.
    if [[ $lines -ge 2 ]]; then
        local _m=0 _best=0 _pc _pcmax=0 _pcol=0 _pi
        (( _dash * 3 >= lines * 2 )) || return 1
        for _pc in "${!_p2col[@]}"; do
            (( _p2col[$_pc] > _pcmax )) && { _pcmax=${_p2col[$_pc]}; _pcol=$_pc; }
        done
        (( _pcmax * 3 >= lines * 2 )) || return 1
        for (( _pi = 0; _pi < ${#_pcols[@]}; _pi++ )); do
            (( _pcols[_pi] == _pcol )) && continue
            (( _pklen[_pi] >= _pcol - 1 && _pcols[_pi] == _pklen[_pi] + 1 )) || return 1
        done
        _fr_modal ${_cc[@]+"${_cc[@]}"}; _m=$_FR_MODE; _best=$_FR_MODE_N
        [[ $_m -ge 3 && $(( _best * 100 / lines )) -ge $(( 60 + ${_FR_SLACK:-0} )) ]] && return 1
        # 79: a shape heuristic, not a tool-unique literal — it yields to any
        # format-specific generic parser (80) that also claims the input.
        _STRATEGY_CONFIDENCE=79
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0
    local line
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "${line}" != *[![:space:]]* ]] && continue
        local name="${line%%[[:space:]]*}"
        local desc="${line#"$name"}"
        desc="${desc#"${desc%%[![:space:]]*}"}"
        [[ -z "$name" ]] && continue
        entry=$((entry + 1))
        result+="entry${entry}.name ${name}"$'\n'
        result+="entry${entry}.description ${desc}"$'\n'
    done
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
