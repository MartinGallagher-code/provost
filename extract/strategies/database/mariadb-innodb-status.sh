#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: mariadb-innodb-status
## Description: Extract stable InnoDB metrics from SHOW ENGINE INNODB STATUS
## Version: 1.0
## Priority: 9
## Sample: samples/mariadb-innodb-status/basic.txt

# `SHOW ENGINE INNODB STATUS` prints sectioned free-form text with labelled
# numbers (`History list length 42`, `OS WAIT ARRAY INFO: reservation count N`,
# `Trx id counter N`, ...). Pull the stable labelled metrics into ONE wide
# record (`entry1.<metric> value`) — every number on the background-thread,
# semaphore and transaction lines, so the parse covers its input (a summary
# of six fields out of a 22-line report tripped the engine's truncation
# guard and lost to text-lines).

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    [[ "$text" == *"INNODB MONITOR OUTPUT"* ]] || return 1
    [[ "$text" == *"TRANSACTIONS"* ]] || return 1
    [[ "$text" == *"History list length"* ]] || return 1
    _STRATEGY_CONFIDENCE=95
    return 0
}

strategy_extract () {
    local text="$1" result="" line fields=0

    _emit () { # $1=field  $2=value
        [[ -n "$2" ]] || return 0
        result+="entry1.$1 $2"$'\n'
        fields=$((fields + 1))
    }

    local _re
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        case "$line" in
            "History list length "*)
                _emit history_list_length "${line##* }" ;;
            *"reservation count "*)
                _emit reservation_count "${line##* }" ;;
            *"signal count "*)
                _emit signal_count "${line##* }" ;;
            "Trx id counter "*)
                _emit trx_id_counter "${line##* }" ;;
            "Buffer pool size "*|"Free buffers "*|"Database pages "*|"Modified db pages "*|"Log sequence number "*|"Log flushed up to "*|"Last checkpoint at "*)
                local _k="${line% *}"; _k="${_k// /_}"; _k="$(printf '%s' "$_k" | tr 'A-Z' 'a-z')"
                _emit "$_k" "${line##* }" ;;
        esac
        # `Per second averages calculated from the last N seconds`
        _re='^Per second averages calculated from the last ([0-9]+) seconds'
        [[ "$line" =~ $_re ]] && _emit averages_window_seconds "${BASH_REMATCH[1]}"
        # `srv_master_thread loops: A srv_active, B srv_shutdown, C srv_idle`
        _re='^srv_master_thread loops: ([0-9]+) srv_active, ([0-9]+) srv_shutdown, ([0-9]+) srv_idle'
        if [[ "$line" =~ $_re ]]; then
            _emit srv_active "${BASH_REMATCH[1]}"
            _emit srv_shutdown "${BASH_REMATCH[2]}"
            _emit srv_idle "${BASH_REMATCH[3]}"
        fi
        _re='^srv_master_thread log flush and writes: ([0-9]+)'
        [[ "$line" =~ $_re ]] && _emit log_flush_and_writes "${BASH_REMATCH[1]}"
        # `RW-shared spins A, rounds B, OS waits C` (and RW-excl, RW-sx)
        _re='^RW-(shared|excl|sx) spins ([0-9]+), rounds ([0-9]+), OS waits ([0-9]+)'
        if [[ "$line" =~ $_re ]]; then
            _emit "rw_${BASH_REMATCH[1]}_spins" "${BASH_REMATCH[2]}"
            _emit "rw_${BASH_REMATCH[1]}_rounds" "${BASH_REMATCH[3]}"
            _emit "rw_${BASH_REMATCH[1]}_os_waits" "${BASH_REMATCH[4]}"
        fi
        # `Purge done for trx's n:o < N undo n:o < M state: S`
        _re="^Purge done for trx's n:o < ([0-9]+) undo n:o < ([0-9]+)( state: ([A-Za-z_ ]+))?"
        if [[ "$line" =~ $_re ]]; then
            _emit purge_trx_no "${BASH_REMATCH[1]}"
            _emit purge_undo_no "${BASH_REMATCH[2]}"
            _emit purge_state "${BASH_REMATCH[4]}"
        fi
    done

    [[ $fields -gt 0 ]] && result+="total_entries 1"$'\n'
    printf '%s' "$result"
}
