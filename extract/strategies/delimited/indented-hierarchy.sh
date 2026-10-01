#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: indented-hierarchy
## Description: Indentation-based hierarchical data, flattened with dot notation
## Version: 1.0
## Priority: 50
## Sample: samples/indented-hierarchy/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=80

    # Reject JSON-like input
    _is_json "$1" && return 1

    # Must have lines with increasing indentation (2+ space-indented lines)
    local indented_count=0
    _fr_lines "$text"
    for _line in "${_FR_LINES[@]}"; do
        if [[ "$_line" == "  "* ]]; then
            indented_count=$((indented_count + 1))
        fi
    done
    [[ $indented_count -lt 2 ]] && return 1

    # Must have a non-indented line followed by indented lines
    [[ "${text:0:1}" != " " ]] || return 1

    # Must contain colons
    [[ "$text" == *":"* ]] || return 1

    # A `|` in either of the first two lines is a TABLE header with piped
    # group separators (/proc/net/dev's `Inter-|  Receive | Transmit`), not a
    # hierarchy. Before the |-in-key fragment guards this shape crashed the
    # strategy mid-extract, and the crash was accidentally protective — the
    # decline makes it deliberate, so the aligned-table parsers claim it.
    local _ihd_seen=0 _ihd_l
    _fr_lines "$text"
    for _ihd_l in "${_FR_LINES[@]}"; do
        [[ "${_ihd_l}" != *[![:space:]]* ]] && continue
        [[ "$_ihd_l" == *"|"* ]] && return 1
        _ihd_seen=$((_ihd_seen + 1))
        [[ $_ihd_seen -ge 2 ]] && break
    done

    return 0
}

_strat_ih_get_indent () {
    local line="$1"
    local stripped="$line"
    # Count leading spaces
    local count=0
    while [[ "$stripped" == " "* ]]; do
        stripped="${stripped# }"
        count=$((count + 1))
    done
    echo $count
}

strategy_extract () {
    local text="$1"
    local result=""

    # Build arrays of path components at each indentation level
    # path_keys[0]="System_Information", path_keys[1]="BIOS_Information", etc.
    # We use indexed arrays
    local path_keys=""  # pipe-delimited: "level:key|level:key|..."
    local prev_indent=0

    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ -z "$line" ]] && continue

        local indent
        indent=$(_strat_ih_get_indent "$line")

        # Strip leading whitespace
        local trimmed="$line"
        while [[ "$trimmed" == " "* ]]; do trimmed="${trimmed# }"; done

        [[ -z "$trimmed" ]] && continue

        # A candidate key containing a literal `|` is not a hierarchy key —
        # it is table chrome (/proc/net/dev's `Inter-|  Receive  | Transmit`
        # group header). The `|` also shatters the |-delimited path list, so
        # before the fragment guards below this shape CRASHED the strategy,
        # and the crash was accidentally protective: with it fixed, the
        # strategy "succeeded" here with garbage. Skip such lines outright.
        if [[ "${trimmed%%:*}" == *"|"* ]]; then
            continue
        fi

        # Check if this is a key: value line or a bare heading
        if [[ "$trimmed" == *":"* ]]; then
            local key="${trimmed%%:*}"
            local value="${trimmed#*:}"
            # Trim leading spaces from value
            while [[ "$value" == " "* ]]; do value="${value# }"; done

            # Trim key
            while [[ "$key" == " "* ]]; do key="${key# }"; done
            while [[ "$key" == *" " ]]; do key="${key% }"; done
            key="${key// /_}"
            # Trim value; spaces inside the value are preserved (the engine keeps
            # everything after the first space as the value).
            while [[ "$value" == *" " ]]; do value="${value% }"; done

            if [[ -n "$value" ]]; then
                # This is a key: value line -- emit with full path
                # Build path from path_keys for current indent level
                local path=""
                # Parse pipe-delimited entries
                local old_ifs="$IFS"
                IFS='|'
                local entries
                { _fr_tok "$path_keys"; entries=("${_FR_TOK[@]}"); }
                IFS="$old_ifs"
                local e
                for e in "${entries[@]}"; do
                    [[ -z "$e" ]] && continue
                    local elevel="${e%%:*}"
                    local ekey="${e#*:}"
                    # Same |-in-key guard as the two pruning loops below.
                    [[ "$elevel" == *[!0-9]* ]] && continue
                    if [[ $elevel -lt $indent ]]; then
                        if [[ -n "$path" ]]; then
                            path+="."
                        fi
                        path+="$ekey"
                    fi
                done
                if [[ -n "$path" ]]; then
                    result+="${path}.${key} ${value}"$'\n'
                else
                    result+="${key} ${value}"$'\n'
                fi
            else
                # Bare heading with colon but no value (e.g., "Section:")
                # Remove entries at this level or deeper
                local new_path_keys=""
                local old_ifs="$IFS"
                IFS='|'
                local entries
                { _fr_tok "$path_keys"; entries=("${_FR_TOK[@]}"); }
                IFS="$old_ifs"
                local e
                for e in "${entries[@]}"; do
                    [[ -z "$e" ]] && continue
                    local elevel="${e%%:*}"
                    # A key containing a literal `|` shatters the |-delimited
                    # path list into fragments with no `indent:` prefix (java's
                    # nonProxyHosts=a|b|c did exactly this); a non-numeric
                    # "level" in an arithmetic test is an unbound-variable
                    # crash under set -u, so drop such fragments.
                    [[ "$elevel" == *[!0-9]* ]] && continue
                    if [[ $elevel -lt $indent ]]; then
                        if [[ -n "$new_path_keys" ]]; then
                            new_path_keys+="|"
                        fi
                        new_path_keys+="$e"
                    fi
                done
                if [[ -n "$new_path_keys" ]]; then
                    path_keys="${new_path_keys}|${indent}:${key}"
                else
                    path_keys="${indent}:${key}"
                fi
            fi
        else
            # Bare heading without colon
            local heading="$trimmed"
            while [[ "$heading" == " "* ]]; do heading="${heading# }"; done
            while [[ "$heading" == *" " ]]; do heading="${heading% }"; done
            heading="${heading// /_}"

            # Remove entries at this level or deeper
            local new_path_keys=""
            local old_ifs="$IFS"
            IFS='|'
            local entries
            { _fr_tok "$path_keys"; entries=("${_FR_TOK[@]}"); }
            IFS="$old_ifs"
            local e
            for e in "${entries[@]}"; do
                [[ -z "$e" ]] && continue
                local elevel="${e%%:*}"
                # Same |-in-key guard as above.
                [[ "$elevel" == *[!0-9]* ]] && continue
                if [[ $elevel -lt $indent ]]; then
                    if [[ -n "$new_path_keys" ]]; then
                        new_path_keys+="|"
                    fi
                    new_path_keys+="$e"
                fi
            done
            if [[ -n "$new_path_keys" ]]; then
                path_keys="${new_path_keys}|${indent}:${heading}"
            else
                path_keys="${indent}:${heading}"
            fi
        fi

        prev_indent=$indent
    done

    echo "$result"
}
