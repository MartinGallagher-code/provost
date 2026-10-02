#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Interactive field selection for provost-extract
##
## TUI-based field picker with keyboard navigation.
## Dependencies: _helpers.sh (strip_strat_prefix)
################################################################################

# Return the Nth value (0-indexed) from a newline-delimited string.
# Result in _NTH_RESULT (no subshell needed).
_interactive_get_nth () {
    local list="$1" n="$2" i=0
    while IFS= read -r val; do
        if [[ $i -eq $n ]]; then _NTH_RESULT="$val"; return; fi
        i=$((i + 1))
    done <<< "$list"
    _NTH_RESULT="0"
}

# Toggle the Nth value in a newline-delimited "0"/"1" string.
# Result in _TOGGLE_RESULT (no subshell needed).
_interactive_toggle_nth () {
    local list="$1" n="$2" i=0
    _TOGGLE_RESULT=""
    while IFS= read -r val; do
        if [[ $i -eq $n ]]; then
            if [[ "$val" == "1" ]]; then val="0"; else val="1"; fi
        fi
        _TOGGLE_RESULT+="$val"$'\n'
        i=$((i + 1))
    done <<< "$list"
    _TOGGLE_RESULT="${_TOGGLE_RESULT%$'\n'}"
}

# Set all values in a newline-delimited string to a given value.
# Result in _SETALL_RESULT (no subshell needed).
_interactive_set_all () {
    local count="$1" val="$2" i
    _SETALL_RESULT=""
    for ((i=0; i<count; i++)); do
        _SETALL_RESULT+="$val"$'\n'
    done
    _SETALL_RESULT="${_SETALL_RESULT%$'\n'}"
}

# Interactive field selector. Sets _SELECTED_FIELDS (comma-separated field numbers).
_interactive_select () {
    local input="$1"

    # Build parallel arrays of field names (newline-delimited)
    local field_count=0
    local field_names=""
    local selected=""

    while IFS= read -r _iline; do
        [[ -z "$_iline" ]] && continue
        strip_strat_prefix "$_iline"
        local _fname="${_STRIPPED_LINE%% *}"
        field_names+="$_fname"$'\n'
        selected+="1"$'\n'
        field_count=$((field_count + 1))
    done <<< "$input"

    field_names="${field_names%$'\n'}"
    selected="${selected%$'\n'}"

    if [[ $field_count -eq 0 ]]; then
        _SELECTED_FIELDS=""
        return
    fi

    # Check for TTY -- if not a terminal, warn and select all
    if ! [ -e /dev/tty ]; then
        _log_warn "--interactive ignored: not a terminal (selecting all fields)"
        _SELECTED_FIELDS=""
        local _j
        for ((_j=1; _j<=field_count; _j++)); do
            if [[ -n "$_SELECTED_FIELDS" ]]; then _SELECTED_FIELDS+=","; fi
            _SELECTED_FIELDS+="$_j"
        done
        return
    fi

    local cursor=0
    local done_flag=0

    # Save terminal state
    local _saved_stty
    _saved_stty=$(stty -g </dev/tty 2>/dev/null)
    stty -echo -icanon min 1 </dev/tty 2>/dev/null

    while [[ $done_flag -eq 0 ]]; do
        # Render
        {
            printf '\033[H\033[2J'
            printf 'Select fields (SPACE=toggle, a=all, n=none, ENTER=confirm, q=cancel):\n\n'
            local _i=0
            while IFS= read -r _fn; do
                _interactive_get_nth "$selected" "$_i"
                local _sel="$_NTH_RESULT"
                local _marker="[ ]"
                if [[ "$_sel" == "1" ]]; then _marker="[x]"; fi
                local _cursor_marker="  "
                if [[ $_i -eq $cursor ]]; then _cursor_marker="> "; fi
                printf '%s%s %2d  %s\n' "$_cursor_marker" "$_marker" "$((_i + 1))" "$_fn"
                _i=$((_i + 1))
            done <<< "$field_names"
            printf '\n'
        } >/dev/tty

        # Read key from /dev/tty
        local key=""
        IFS= read -rsn1 key </dev/tty

        case "$key" in
            $'\x1b')
                # Escape sequence -- read CSI
                local _seq="" _code=""
                # Use stty timeout for escape sequence bytes
                stty min 0 time 1 </dev/tty 2>/dev/null
                IFS= read -rsn1 _seq </dev/tty 2>/dev/null || true
                if [[ "$_seq" == "[" ]]; then
                    IFS= read -rsn1 _code </dev/tty 2>/dev/null || true
                    case "$_code" in
                        A) if [[ $cursor -gt 0 ]]; then cursor=$((cursor - 1)); fi ;;
                        B) if [[ $cursor -lt $((field_count - 1)) ]]; then cursor=$((cursor + 1)); fi ;;
                    esac
                fi
                # Restore blocking read
                stty min 1 time 0 </dev/tty 2>/dev/null
                ;;
            ' ')
                _interactive_toggle_nth "$selected" "$cursor"; selected="$_TOGGLE_RESULT"
                ;;
            'a')
                _interactive_set_all "$field_count" "1"; selected="$_SETALL_RESULT"
                ;;
            'n')
                _interactive_set_all "$field_count" "0"; selected="$_SETALL_RESULT"
                ;;
            ''|$'\n')
                done_flag=1
                ;;
            'q')
                stty "$_saved_stty" </dev/tty 2>/dev/null
                printf '\033[H\033[2J' >/dev/tty
                exit 1
                ;;
        esac
    done

    # Restore terminal
    stty "$_saved_stty" </dev/tty 2>/dev/null
    printf '\033[H\033[2J' >/dev/tty

    # Build comma-separated field numbers for selected items
    _SELECTED_FIELDS=""
    local _j=0
    while IFS= read -r _sval; do
        if [[ "$_sval" == "1" ]]; then
            if [[ -n "$_SELECTED_FIELDS" ]]; then _SELECTED_FIELDS+=","; fi
            _SELECTED_FIELDS+="$((_j + 1))"
        fi
        _j=$((_j + 1))
    done <<< "$selected"
}
