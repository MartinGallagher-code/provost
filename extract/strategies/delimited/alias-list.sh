#!/bin/bash
## Name: alias-list
## Description: Shell `alias name='command'` listings — name/command columns, quotes and the `alias ` keyword stripped
## Version: 1.0
## Priority: 14
## Sample: samples/alias-list/basic.txt

# `alias ll='ls -alF'` is an assignment whose key carries a constant `alias `
# keyword and whose value is a (usually single-quoted) command. aligned-columns
# would shred the command on its internal spaces (`ls`/`-alF` in separate
# columns) and keep the redundant `alias` token as column A; equals would keep
# the `alias_` prefix glued to the name. Neither is what the value is: a name
# mapped to a command string. This owns the shape and emits exactly that.

# True only when EVERY non-empty line is `alias <name>=<value>` — a listing, not
# prose that happens to contain the word "alias".
_al_is_alias_list () {
    local text="$1" line seen=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" ]] && continue
        # Leading whitespace tolerated (some shells indent), then `alias `.
        local s="$line"
        while [[ "$s" == " "* || "$s" == $'\t'* ]]; do s="${s#?}"; done
        [[ "$s" == "alias "* ]] || return 1
        local rest="${s#alias }"
        # Must be `name=value` with a non-empty name that looks like an
        # identifier (shell alias names: letters, digits, _, -, ., and the
        # handful of punctuation aliases like `..`).
        [[ "$rest" == *"="* ]] || return 1
        local name="${rest%%=*}"
        [[ -n "$name" ]] || return 1
        [[ "$name" == *" "* ]] && return 1   # a space in the name = not an alias def
        seen=$((seen + 1))
    done <<< "$text"
    [[ $seen -ge 1 ]]
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    _al_is_alias_list "$text" || return 1
    _STRATEGY_CONFIDENCE=90
    return 0
}

# Strip one layer of matching outer quotes from $1 -> _AL_UNQUOTE
_al_unquote () {
    local v="$1"
    if [[ ${#v} -ge 2 ]]; then
        local a="${v:0:1}" b="${v: -1}"
        if [[ ( "$a" == "'" && "$b" == "'" ) || ( "$a" == '"' && "$b" == '"' ) ]]; then
            v="${v:1:${#v}-2}"
        fi
    fi
    _AL_UNQUOTE="$v"
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" ]] && continue
        local s="$line"
        while [[ "$s" == " "* || "$s" == $'\t'* ]]; do s="${s#?}"; done
        [[ "$s" == "alias "* ]] || continue
        local rest="${s#alias }"
        [[ "$rest" == *"="* ]] || continue
        local name="${rest%%=*}" cmd="${rest#*=}"
        [[ -n "$name" ]] || continue
        _al_unquote "$cmd"; cmd="$_AL_UNQUOTE"
        entry=$((entry + 1))
        result+="entry${entry}.name ${name}"$'\n'
        [[ -n "$cmd" ]] && result+="entry${entry}.command ${cmd}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
