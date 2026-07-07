#!/bin/bash
## Name: mariadb-innodb-status
## Description: Extract stable InnoDB metrics from SHOW ENGINE INNODB STATUS
## Version: 1.0
## Priority: 9
## Technique: yes
## Sample: samples/mariadb-innodb-status/basic.txt

# `SHOW ENGINE INNODB STATUS` prints sectioned free-form text with labelled
# numbers (`History list length 42`, `OS WAIT ARRAY INFO: reservation count N`,
# `Trx id counter N`, ...). Pull a set of stable labelled metrics into ONE wide
# record (`entry1.<metric> value`).

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    [[ "$text" == *"INNODB MONITOR OUTPUT"* ]] || return 1
    [[ "$text" == *"TRANSACTIONS"* ]] || return 1
    [[ "$text" == *"History list length"* ]] || return 1
    _STRATEGY_CONFIDENCE=86
    return 0
}

strategy_extract () {
    local text="$1" result="" line fields=0

    _emit () { # $1=field  $2=value
        [[ -n "$2" ]] || return 0
        result+="entry1.$1 $2"$'\n'
        fields=$((fields + 1))
    }

    while IFS= read -r line; do
        case "$line" in
            "History list length "*)
                _emit history_list_length "${line##* }" ;;
            *"reservation count "*)
                _emit reservation_count "${line##* }" ;;
            *"signal count "*)
                _emit signal_count "${line##* }" ;;
            "Trx id counter "*)
                _emit trx_id_counter "${line##* }" ;;
        esac
        # `RW-shared spins A, rounds B, OS waits C`
        if [[ "$line" =~ ^RW-shared[[:space:]]spins[[:space:]][0-9]+,[[:space:]]rounds[[:space:]]([0-9]+) ]]; then
            _emit rw_shared_rounds "${BASH_REMATCH[1]}"
        fi
        if [[ "$line" =~ ^RW-excl[[:space:]]spins[[:space:]][0-9]+,[[:space:]]rounds[[:space:]]([0-9]+) ]]; then
            _emit rw_excl_rounds "${BASH_REMATCH[1]}"
        fi
    done <<< "$text"

    [[ $fields -gt 0 ]] && result+="total_entries 1"$'\n'
    printf '%s' "$result"
}
