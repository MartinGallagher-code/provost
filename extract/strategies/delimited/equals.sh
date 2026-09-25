#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: equals
## Description: Extract field=value pairs from equals-delimited data
## Version: 1.2
## Priority: 65
## Sample: samples/equals/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=35
    # CONFIDENCE REFLECTS EVIDENCE. A lone `=` somewhere in prose is weak
    # evidence (35, below provost's default filing threshold of 50); a block
    # where (nearly) EVERY non-blank line is a tight `KEY=VALUE` with a sane
    # key — env/printenv, systemctl show, git config --list, locale, .env files
    # — is the format itself, and must be able to file (75). Pins
    # (`name==1.2.3`) and signed env-diff lines count as valid too. Needs >=2
    # lines so a single stray assignment in free text stays weak. Only the
    # confidence changes here — WHICH strategy wins is decided by priority, so
    # this cannot take an input away from a higher-priority strategy.
    local _cf_line _cf_nb=0 _cf_ok=0
    local _cf_kv='^(export[[:space:]]+)?[A-Za-z_][A-Za-z0-9_.-]{0,63}=([^=]|$)'
    local _cf_pin='^[A-Za-z0-9_.-]+==[^=[:space:]]+$'
    local _cf_sig='^[+-][A-Za-z_][A-Za-z0-9_.]{0,63}=([^=]|$)'
    while IFS= read -r _cf_line; do
        [[ -z "${_cf_line//[[:space:]]/}" ]] && continue
        _cf_nb=$((_cf_nb + 1))
        if [[ "$_cf_line" =~ $_cf_kv || "$_cf_line" =~ $_cf_pin || "$_cf_line" =~ $_cf_sig ]]; then
            _cf_ok=$((_cf_ok + 1))
        fi
    done <<< "$text"
    if [[ $_cf_nb -ge 2 && $(( _cf_ok * 100 )) -ge $(( _cf_nb * 90 )) ]]; then
        _STRATEGY_CONFIDENCE=75
        _STRATEGY_CONFIDENCE_REASON="${_cf_ok}/${_cf_nb} lines are KEY=VALUE"
    fi
    # Apply if input contains lines with equals signs that look like assignments
    # Skip lines that look like code (==, +=, !=)
    # Use while-read so ^ anchors match per-line (not start of entire string)
    local _det_line
    while IFS= read -r _det_line; do
        # Tight assignment: `KEY=value` (env vars, systemctl show, `git config
        # --list`'s dotted keys `user.name=…`). The key allows `.` so dotted
        # config keys match.
        [[ "$_det_line" =~ ^[A-Za-z][A-Za-z0-9_.\ -]*=[^=] ]] && return 0
        # Version pins: `name==1.2.3` (pip freeze, rye list). `==` is normally
        # the comparison guard's territory, but a PIN is `==` used as a kv
        # delimiter; the uniform-block test in strategy_extract keeps real
        # code comparisons out.
        [[ "$_det_line" =~ ^[A-Za-z0-9_.-]+==[^=[:space:]]+$ ]] && return 0
        # Signed assignment: `+KEY=value` / `-KEY=value` — env-diff style
        # (direnv, `env -0 | comm`) marks additions and removals with one
        # leading sign. The sign is DATA (it says which side changed) so it
        # stays on the key. Exactly one sign then a tight sign-free key, so
        # `--flag=value` option help and `+ x = 1` patch hunks stay out.
        [[ "$_det_line" =~ ^[+-][A-Za-z][A-Za-z0-9_.]*=[^=] ]] && return 0
        # Space-padded assignment with a rich key: `KEY(ctx) = value`,
        # `KEY(env: X) = value` (ansible-config dump). Requires ` = ` so it does
        # not fire on prose that merely contains a lone '='.
        [[ "$_det_line" =~ ^[A-Za-z][A-Za-z0-9_().:\ -]*\ =\ [^=] ]] && return 0
    done <<< "$text"
    return 1
}

strategy_extract () {
    local text="$1"

    # Two uniform-block modes, decided over the RAW text before cleaning:
    #   pins — EVERY non-blank line is `name==version` (pip freeze, rye
    #     list): split on the `==`. A mixed block keeps the comparison guard.
    #   cfg  — every non-blank line is one whitespace-free token, optionally
    #     `key=value` (rustc --print cfg): a BARE token is a boolean flag the
    #     reviewer wants kept as a key — emitted as `key true`. Prose can
    #     never qualify (prose lines contain spaces).
    local _eq_line _eq_nb=0 _eq_pin=0 _eq_tight=0 _eq_haseq=0 _eq_bare=0
    while IFS= read -r _eq_line; do
        [[ -z "${_eq_line//[[:space:]]/}" ]] && continue
        _eq_nb=$((_eq_nb + 1))
        [[ "$_eq_line" =~ ^[A-Za-z0-9_.-]+==[^=[:space:]]+$ ]] && _eq_pin=$((_eq_pin + 1))
        if [[ "$_eq_line" =~ ^[A-Za-z_][^[:space:]=]*(=[^[:space:]]*)?$ ]]; then
            _eq_tight=$((_eq_tight + 1))
            if [[ "$_eq_line" == *=* ]]; then _eq_haseq=1; else _eq_bare=$((_eq_bare + 1)); fi
        fi
    done <<< "$text"
    local pin_mode=0 cfg_mode=0
    [[ $_eq_nb -ge 2 && $_eq_pin -eq $_eq_nb ]] && pin_mode=1
    # cfg LIST requires at least one BARE flag token (rustc's `debug_assertions`
    # with no `=`) — that is the reviewer's "this is key/value" signal, and it
    # is exactly what tells a cfg LIST apart from an env/config SNAPSHOT (env,
    # wpa-cli status), whose keys are all unique and all carry `=`, and which
    # is correctly ONE wide record, not per-key rows.
    [[ $pin_mode -eq 0 && $_eq_nb -ge 2 && $_eq_tight -eq $_eq_nb && $_eq_haseq -eq 1 && $_eq_bare -ge 1 ]] && cfg_mode=1

    if [[ $pin_mode -eq 1 ]]; then
        # A pin LIST is records (one row per package), not one wide snapshot —
        # the reviewer's "simple key/value" means package | version per row.
        local presult="" _pe=0
        while IFS= read -r _eq_line; do
            [[ -z "${_eq_line//[[:space:]]/}" ]] && continue
            _pe=$((_pe + 1))
            presult+="entry${_pe}.package ${_eq_line%%==*}"$'\n'
            presult+="entry${_pe}.version ${_eq_line#*==}"$'\n'
        done <<< "$text"
        [[ $_pe -gt 0 ]] && presult+="total_entries ${_pe}"$'\n'
        echo "$presult"
        return 0
    fi

    # cfg LIST -> key | value records, same reasoning (rustc --print cfg).
    if [[ $cfg_mode -eq 1 ]]; then
        local cresult="" _ce=0 _ck _cv
        while IFS= read -r _eq_line; do
            [[ -z "${_eq_line//[[:space:]]/}" ]] && continue
            _ce=$((_ce + 1))
            if [[ "$_eq_line" == *=* ]]; then _ck="${_eq_line%%=*}"; _cv="${_eq_line#*=}"
            else _ck="$_eq_line"; _cv="true"; fi
            cresult+="entry${_ce}.key ${_ck}"$'\n'
            cresult+="entry${_ce}.value ${_cv}"$'\n'
        done <<< "$text"
        [[ $_ce -gt 0 ]] && cresult+="total_entries ${_ce}"$'\n'
        echo "$cresult"
        return 0
    fi

    # Clean text (dates, parentheses) -- cached by engine after first call
    clean_text "$text"; text="$_CLEAN_TEXT_RESULT"

    local result=""
    while IFS= read -r line; do
        # Skip empty lines
        [[ -z "$line" ]] && continue

        # Must contain = but not == (comparison) or += or !=
        [[ "$line" != *"="* ]] && continue
        [[ "$line" == *"=="* ]] && continue
        [[ "$line" == *"+="* ]] && continue
        [[ "$line" == *"!="* ]] && continue

        # Extract key (before first =) and value (after first =)
        local key value

        # Strip leading spaces and bullet markers
        local _stripped="$line"
        while [[ "$_stripped" == " "* ]]; do _stripped="${_stripped# }"; done
        if [[ "$_stripped" == "* "* ]]; then
            _stripped="${_stripped#\* }"
        fi

        key="${_stripped%%=*}"
        value="${_stripped#*=}"

        # Skip if key is empty or too long
        [[ -z "$key" ]] && continue
        [[ ${#key} -gt 50 ]] && continue

        # Skip lines where key starts with a digit
        [[ "$key" =~ ^[0-9] ]] && continue

        # Clean up key and value
        key="${key// /_}"
        key="${key#_}"
        key="${key%_}"

        while [[ "$value" == " "* ]]; do value="${value# }"; done
        while [[ "$value" == *" " ]]; do value="${value% }"; done

        # An EMPTY value is still a statement: `locale` prints `LANG=` for a
        # variable that is set-but-empty, and dropping the line makes that
        # indistinguishable from the variable not existing at all — the three
        # lines a reader most wants to check were the three that vanished.
        # The field stream cannot hold a valueless line (the melt would read
        # the next line as this one's value), so emptiness is written as `""`,
        # the same spelling `go env` itself uses.
        [[ -z "$value" ]] && value='""'

        result+="${key} ${value}"$'\n'
    done <<< "$text"

    # clean_text protected dates/parenthesised spans with sentinels; put the
    # original spaces and colons back into the values.
    restore_text_values "$result"
    echo "$_RESTORED_TEXT"
}
