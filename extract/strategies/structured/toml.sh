#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: toml
## Description: Extract key/value pairs from TOML format with section and array table support
## Version: 1.1
## Priority: 15
## Sample: samples/toml/basic.toml

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=85

    # Must NOT look like JSON
    local first_nonblank=""
    while IFS= read -r _line; do
        [[ -z "$_line" ]] && continue
        local _trimmed="$_line"
        while [[ "$_trimmed" == " "* || "$_trimmed" == "	"* ]]; do _trimmed="${_trimmed#?}"; done
        [[ -z "$_trimmed" ]] && continue
        first_nonblank="$_trimmed"
        break
    done <<< "$text"
    case "$first_nonblank" in
        '{'*|'['*) ;;
    esac

    # Check for actual JSON start
    case "$first_nonblank" in
        '{'*) return 1 ;;
    esac

    # 1. [[array]] table headers
    if [[ "$text" == *$'\n'"[["* || "$text" == "[["* ]]; then
        _strat_toml_grammar "$text"; return
    fi

    # 2. [dotted.section] headers
    if [[ "$text" =~ (^|$'\n')\[[a-zA-Z][a-zA-Z0-9_-]*\. ]]; then
        _strat_toml_grammar "$text"; return
    fi

    # 3. key = "quoted_value" pattern (TOML uses = with spaces, not :)
    if [[ "$text" =~ (^|$'\n')[a-zA-Z][a-zA-Z0-9_-]*[\ ]*=[\ ]*\" ]]; then
        # Also must have [section] to distinguish from env-vars / equals
        if [[ "$text" == *$'\n'"["* || "$text" == "["* ]]; then
            _strat_toml_grammar "$text"; return
        fi
        # Or [[array]] tables
        if [[ "$text" == *"[["* ]]; then
            _strat_toml_grammar "$text"; return
        fi
        # Accept if we have key = "value" at top level AND [section] somewhere
        local section_count=0
        _fr_lines "$text"
        for _line in "${_FR_LINES[@]}"; do
            [[ "$_line" == "["* ]] && section_count=$((section_count + 1))
        done
        _line=""
        [[ $section_count -ge 1 ]] && { _strat_toml_grammar "$text"; return; }
    fi

    return 1
}

# _strat_toml_grammar TEXT — the TOML LINE GRAMMAR must hold for (nearly)
# every line. The signatures above are single-line clues (one `[a.b]`
# header, one `key = "v"`), and toml is exempt from the engine's coverage
# hold (it is a document grammar), so it checks itself: a line is TOML when
# it is blank, a `#` comment, a `[table]` / `[[array]]` header STANDING ALONE
# (a trailing comment allowed), a `key = value` assignment (bare, quoted or
# dotted key, any non-empty value), or a continuation inside a multi-line
# string or array. A `[key] value` listing (`composer config --list`: a
# `Set X=1` banner line over `[repositories.x.url] https://…` rows) and prose
# break almost every line. Accept when at most 10% of the counted lines
# break the grammar (widened by _FR_SLACK on the detection sample). Not
# applied when the strategy is pinned (`-s toml`).
_strat_toml_grammar () {
    # (pinned with `--strategy toml`, the caller has decided: read what parses)
    [[ "${_OPT_strategy:-}" == toml ]] && return 0
    local _tg_l _tg_t _tg_v _tg_ok=0 _tg_bad=0 _tg_arr=0 _tg_mls="" _tg_s _tg_o _tg_c
    local _tg_q="'"
    local _tg_k="([A-Za-z0-9_-]+|\"[^\"]*\"|${_tg_q}[^${_tg_q}]*${_tg_q})"
    local _tg_key="${_tg_k}([[:space:]]*\\.[[:space:]]*${_tg_k})*"
    local _tg_hdr="^\\[[[:space:]]*${_tg_key}[[:space:]]*\\][[:space:]]*(#.*)?$"
    local _tg_ahdr="^\\[\\[[[:space:]]*${_tg_key}[[:space:]]*\\]\\][[:space:]]*(#.*)?$"
    local _tg_kv="^${_tg_key}[[:space:]]*=[[:space:]]*(.*)$"
    local _tg_dq="\"[^\"]*\"" _tg_sq="${_tg_q}[^${_tg_q}]*${_tg_q}"
    _fr_lines "$1"
    for _tg_l in "${_FR_LINES[@]}"; do
        if [[ -n "$_tg_mls" ]]; then
            _tg_ok=$((_tg_ok + 1))
            [[ "$_tg_l" == *"$_tg_mls"* ]] && _tg_mls=""
            continue
        fi
        _tg_t="${_tg_l#"${_tg_l%%[![:space:]]*}"}"
        [[ -z "$_tg_t" || "$_tg_t" == "#"* ]] && continue
        if [[ $_tg_arr -gt 0 ]]; then
            _tg_v="$_tg_t"
        elif [[ "$_tg_t" =~ $_tg_ahdr || "$_tg_t" =~ $_tg_hdr ]]; then
            _tg_ok=$((_tg_ok + 1)); continue
        elif [[ "$_tg_t" =~ $_tg_kv ]]; then
            _tg_v="${BASH_REMATCH[${#BASH_REMATCH[@]}-1]}"
            _tg_v="${_tg_v%"${_tg_v##*[![:space:]]}"}"
            [[ -n "$_tg_v" ]] || { _tg_bad=$((_tg_bad + 1)); continue; }
            # a multi-line basic / literal string opens here
            _tg_s="${_tg_v:0:3}"
            if [[ "$_tg_s" == '"""' || "$_tg_s" == "${_tg_q}${_tg_q}${_tg_q}" ]]; then
                [[ "${_tg_v:3}" == *"$_tg_s"* ]] || _tg_mls="$_tg_s"
                _tg_ok=$((_tg_ok + 1)); continue
            fi
            [[ "$_tg_v" == "["* ]] || { _tg_ok=$((_tg_ok + 1)); continue; }
        else
            _tg_bad=$((_tg_bad + 1)); continue
        fi
        # an array value or its continuation: bracket depth outside strings
        _tg_ok=$((_tg_ok + 1))
        _tg_s="$_tg_v"
        while [[ "$_tg_s" =~ $_tg_dq ]]; do _tg_s="${_tg_s/"${BASH_REMATCH[0]}"/}"; done
        while [[ "$_tg_s" =~ $_tg_sq ]]; do _tg_s="${_tg_s/"${BASH_REMATCH[0]}"/}"; done
        _tg_s="${_tg_s%%#*}"
        _tg_o="${_tg_s//[!\[]/}"; _tg_c="${_tg_s//[!\]]/}"
        _tg_arr=$((_tg_arr + ${#_tg_o} - ${#_tg_c}))
        [[ $_tg_arr -lt 0 ]] && _tg_arr=0
    done
    _tg_l=""
    [[ $((_tg_ok + _tg_bad)) -gt 0 ]] || return 1
    [[ $(( _tg_bad * 100 )) -le $(( (_tg_ok + _tg_bad) * (10 + ${_FR_SLACK:-0}) )) ]]
}

strategy_extract () {
    local text="$1"

    local result=""
    local current_section=""
    # Track array table counts using pipe-delimited "name:count" pairs
    local array_table_counts=""

    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        # Skip empty lines
        [[ -z "$line" ]] && continue

        # Skip comment lines
        case "$line" in
            '#'*) continue ;;
        esac

        # Check for array table header [[name]]
        if [[ "$line" == "[["* ]]; then
            local array_name="${line#\[\[}"
            array_name="${array_name%%\]\]*}"
            # Trim whitespace
            while [[ "$array_name" == " "* || "$array_name" == "	"* ]]; do array_name="${array_name#?}"; done
            while [[ "$array_name" == *" " || "$array_name" == *"	" ]]; do array_name="${array_name%?}"; done

            # Get and increment the counter for this array table
            local count
            count=$(_strat_toml_get_array_count "$array_name")
            _strat_toml_set_array_count "$array_name" $((count + 1))

            current_section="${array_name}.${count}"
            continue
        fi

        # Check for section header [name] or [dotted.name]
        if [[ "$line" =~ ^\[[a-zA-Z] ]]; then
            current_section="${line#\[}"
            current_section="${current_section%%\]*}"
            # Trim whitespace
            while [[ "$current_section" == " "* || "$current_section" == "	"* ]]; do current_section="${current_section#?}"; done
            while [[ "$current_section" == *" " || "$current_section" == *"	" ]]; do current_section="${current_section%?}"; done
            continue
        fi

        # Check for key = value lines
        if [[ "$line" == *"="* ]]; then
            local key value

            # Extract key (before first =)
            key="${line%%=*}"
            # Trim whitespace from key
            while [[ "$key" == " "* || "$key" == "	"* ]]; do key="${key#?}"; done
            while [[ "$key" == *" " || "$key" == *"	" ]]; do key="${key%?}"; done

            # Extract value (after first =)
            value="${line#*=}"
            # Trim leading whitespace
            while [[ "$value" == " "* || "$value" == "	"* ]]; do value="${value#?}"; done

            # Skip if key is empty
            [[ -z "$key" ]] && continue

            # Strip quotes from string values
            case "$value" in
                '"'*) value="${value#\"}"; value="${value%\"}" ;;
                "'"*) value="${value#\'}"; value="${value%\'}" ;;
            esac
            # Trim trailing whitespace
            while [[ "$value" == *" " || "$value" == *"	" ]]; do value="${value%?}"; done

            # Skip if value is empty
            [[ -z "$value" ]] && continue

            # Replace spaces in key and value with underscores
            key="${key// /_}"

            # Prefix with section if we have one
            if [[ -n "$current_section" ]]; then
                result+="${current_section}.${key} ${value}"$'\n'
            else
                result+="${key} ${value}"$'\n'
            fi
        fi
    done

    echo "$result"
}

# Helper: get array table count for a given name
_strat_toml_get_array_count () {
    local name="$1"
    local IFS_OLD="$IFS"
    IFS="|"
    for entry in $array_table_counts; do
        local entry_name entry_count
        entry_name="${entry%%:*}"
        entry_count="${entry#*:}"
        if [[ "$entry_name" == "$name" ]]; then
            IFS="$IFS_OLD"
            echo "$entry_count"
            return
        fi
    done
    IFS="$IFS_OLD"
    echo "0"
}

# Helper: set array table count for a given name
_strat_toml_set_array_count () {
    local name="$1"
    local new_count="$2"
    local new_counts=""
    local found=0
    local IFS_OLD="$IFS"
    IFS="|"
    for entry in $array_table_counts; do
        local entry_name
        entry_name="${entry%%:*}"
        if [[ "$entry_name" == "$name" ]]; then
            entry="${name}:${new_count}"
            found=1
        fi
        if [[ -z "$new_counts" ]]; then
            new_counts="$entry"
        else
            new_counts="${new_counts}|${entry}"
        fi
    done
    IFS="$IFS_OLD"
    if [[ $found -eq 0 ]]; then
        if [[ -z "$new_counts" ]]; then
            new_counts="${name}:${new_count}"
        else
            new_counts="${new_counts}|${name}:${new_count}"
        fi
    fi
    array_table_counts="$new_counts"
}
