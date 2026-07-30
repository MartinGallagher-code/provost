#!/bin/bash
## Name: dot-leader-kv
## Description: `label: ......... value` / `label ........: value` reports where dot leaders separate key from value
## Version: 1.1
## Priority: 15
## Sample: samples/dot-leader-kv/basic.txt
## Sample: samples/dot-leader-kv/leader-before-colon.txt

# Reports like artillery / some benchmark summaries align a value to the right
# with a run of dot leaders: `http.codes.200: ............ 120488`. The dots are
# a delimiter, not data. block-records / colons mangle these (the leaders end up
# glued to the value, or the row is split on the dots). This owns the shape:
# key before the colon, value after the dot run, one row per metric.
#
# The leaders sit on either side of the colon depending on the tool. gpg --card-status
# and hashcat --status pad the *key* out to a fixed width instead, putting the dots
# before the colon: `Reader ...........: Yubico`. Same shape, same delimiter, so both
# orderings are handled here. In a block of that second kind the padding is only
# sometimes dots -- `Signature counter : 42` lines up with spaces -- so once the
# block is recognised, colon-separated lines without leaders are taken too, rather
# than dropping those rows.

# A dot-leader line, in either ordering:
#   A  `label: ....... value`   -- colon first, leaders before the value
#   B  `label .......: value`   -- leaders pad the key, colon last
# Sets _DL_KEY / _DL_VAL on success, and _DL_FORM to A or B.
_dl_match () {
    local line="$1"
    local _re_a='^[[:space:]]*([^:]+):[[:space:]]*\.\.\.+[[:space:]]*(.+)$'
    local _re_b='^[[:space:]]*([^:]*[^.:[:space:]])[[:space:]]*\.+[[:space:]]*:[[:space:]]*(.+)$'
    if [[ "$line" =~ $_re_a ]]; then
        _DL_FORM=A
    elif [[ "$line" =~ $_re_b ]]; then
        _DL_FORM=B
    else
        return 1
    fi
    _DL_KEY="${BASH_REMATCH[1]}"
    _DL_VAL="${BASH_REMATCH[2]}"
    # Trim trailing whitespace from the value.
    while [[ "$_DL_VAL" == *" " ]]; do _DL_VAL="${_DL_VAL% }"; done
    # A value that is itself only dots is not a value.
    [[ "$_DL_VAL" =~ ^\.*$ ]] && return 1
    return 0
}

# A plain `label: value` line. Only used to pick up the unpadded stragglers in a
# block already recognised as form B -- never on its own, or this would swallow
# every colon-bearing line in the corpus.
_dl_match_plain () {
    local line="$1"
    local _re='^[[:space:]]*([^:]*[^.:[:space:]])[[:space:]]*:[[:space:]]+(.+)$'
    [[ "$line" =~ $_re ]] || return 1
    _DL_KEY="${BASH_REMATCH[1]}"
    _DL_VAL="${BASH_REMATCH[2]}"
    while [[ "$_DL_VAL" == *" " ]]; do _DL_VAL="${_DL_VAL% }"; done
    [[ "$_DL_VAL" =~ ^\.*$ ]] && return 1
    return 0
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    local line hits=0 form_b=0
    local -A seen_keys=()
    local repeated=0 key
    while IFS= read -r line || [[ -n "$line" ]]; do
        _dl_match "$line" || continue
        hits=$((hits + 1))
        [[ "$_DL_FORM" == B ]] && form_b=1
        key="$_DL_KEY"
        while [[ "$key" == *"." || "$key" == *" " ]]; do key="${key%[. ]}"; done
        [[ -n "${seen_keys[$key]:-}" ]] && repeated=1
        seen_keys[$key]=1
    done <<< "$text"
    [[ $hits -ge 3 ]] || return 1
    # A key that repeats means these are grouped records, not one flat key/value
    # list -- hashcat --benchmark repeats `Speed.#1` / `Hashmode` once per hash
    # mode, and a record parser keeps that grouping where flattening would lose
    # it. Only form B can reach such blocks, so leave them to the record parsers.
    [[ $form_b -eq 1 && $repeated -eq 1 ]] && return 1
    _STRATEGY_CONFIDENCE=86
    return 0
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line

    # Does this block use form B? If so its unpadded `label: value` lines are
    # part of the same aligned block and are kept.
    local form_b=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        if _dl_match "$line" && [[ "$_DL_FORM" == B ]]; then form_b=1; break; fi
    done <<< "$text"

    while IFS= read -r line || [[ -n "$line" ]]; do
        if ! _dl_match "$line"; then
            [[ $form_b -eq 1 ]] || continue
            _dl_match_plain "$line" || continue
        fi
        local key="$_DL_KEY"
        # Form B pads the key out with dots; they are delimiter, not name.
        while [[ "$key" == *"." ]]; do key="${key%.}"; done
        # Trim trailing space off the key too.
        while [[ "$key" == *" " ]]; do key="${key% }"; done
        entry=$((entry + 1))
        result+="entry${entry}.key ${key}"$'\n'
        result+="entry${entry}.value ${_DL_VAL}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
