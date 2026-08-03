#!/bin/bash
## Name: repeated-lead-records
## Description: Every line opens with the SAME token (keepalived's VRRP_Instance(VI_1), bluetoothctl's Device) -> label/value records
## Version: 1.0
## Priority: 38
## Sample: samples/repeated-lead-records/basic.txt

# Some tools stamp every line with one identical leading token:
#
#   VRRP_Instance(VI_1) Entering MASTER STATE
#   VRRP_Instance(VI_1) setting VIPs.
#
#   Device AA:BB:CC:DD:EE:01 WH-1000XM5
#   Device AA:BB:CC:DD:EE:02 Magic Keyboard
#
# The token is a label, not part of the message — the reviewer's "A and B
# columns". When, additionally, EVERY line's second token is id-shaped
# (bears a digit or colon: a MAC, a PID, an address), that id is its own
# column: `label | id | value` — the reviewer's "should be three columns"
# on bluetoothctl. Second tokens that are ordinary words (`Entering`,
# `setting`) stay in the message.
#

# Split "$1" -> _RLR_LEAD / _RLR_REST. Returns 1 on no-rest.
_rlr_split () {
    local l="$1"
    [[ "$l" =~ ^([^[:space:]]+)\ (.+)$ ]] || return 1
    _RLR_LEAD="${BASH_REMATCH[1]}"
    _RLR_REST="${BASH_REMATCH[2]}"
    [[ -n "${_RLR_REST//[[:space:]]/}" ]] || return 1
    return 0
}

# A repeated first token is COMMON — the first cut of this strategy stole 25
# corpus tools (apt-cache's `Total ...: n` kv, auditctl's flag rows, btrfs
# subvolume-list's `ID 256 gen ...` records, arp's `? (ip) at mac ...`,
# chkrootkit's `Checking ...` lines). Acceptance is now one of two cases:
#   ID case — every line's second token is a STRUCTURED id: charset
#     [0-9A-Fa-f:.%-], bearing a digit AND a ':' or '-' (a MAC, an address).
#     A bare integer does not qualify: that is btrfs's `ID 256 gen ...`
#     record row, not an id column.
#   PROSE case — the lead bears a non-letter (a stamp like
#     `VRRP_Instance(VI_1)`, never a sentence word like `Checking`), and
#     across all lines a MAJORITY of rest-tokens are plain words — messages
#     are prose; record rows are flags, numbers and brackets.
# Plus, in all cases: no line may hold a `: ` pair (kv territory — bazel
# `Build label: 6.4.0`, apt-cache stats).
strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    local line lead="" nb=0 id_ok=1 word_toks=0 all_toks=0
    local _id_re='^[0-9A-Fa-f:.%-]+$'
    local _word_re="^[A-Za-z][A-Za-z.,!?']*$"
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        [[ "$line" == [' 	']* ]] && return 1
        [[ "$line" == *'	'* ]] && return 1
        [[ "$line" == *'  '* ]] && return 1
        [[ "$line" == *': '* ]] && return 1
        _rlr_split "$line" || return 1
        if [[ -z "$lead" ]]; then
            lead="$_RLR_LEAD"
        elif [[ "$_RLR_LEAD" != "$lead" ]]; then
            return 1
        fi
        nb=$((nb + 1))
        local _t2="${_RLR_REST%% *}"
        if [[ "$_t2" == "$_RLR_REST" || ! "$_t2" =~ $_id_re || ! "$_t2" =~ [0-9] || ! "$_t2" =~ [:-] ]]; then
            id_ok=0
        fi
        local _w
        for _w in $_RLR_REST; do
            all_toks=$((all_toks + 1))
            [[ "$_w" =~ $_word_re ]] && word_toks=$((word_toks + 1))
        done
    done <<< "$text"
    [[ $nb -ge 3 ]] || return 1
    if [[ $id_ok -eq 1 ]]; then
        _STRATEGY_CONFIDENCE=80
        return 0
    fi
    # PROSE case: stamp-shaped lead, 3-in-4 plain-word rest. The threshold is
    # 75%, not a bare majority: `host google.com` rows (`name server ns1.…`,
    # 2 words in 3 tokens) sit at 66% and their word-per-column split was
    # already right, while real log messages (keepalived) run >=80%.
    [[ "$lead" =~ [^A-Za-z] ]] || return 1
    # A fully-bracketed lead (`[semantic-release]`) is bracket-log's shape —
    # it strips the brackets and names the columns; stealing it would keep
    # the brackets as data.
    [[ "$lead" == \[*\] ]] && return 1
    [[ $all_toks -gt 0 && $(( word_toks * 4 )) -ge $(( all_toks * 3 )) ]] || return 1
    _STRATEGY_CONFIDENCE=80
    return 0
}

strategy_extract () {
    local text="$1"
    local line result="" entry=0

    # Promote the second token to its own `id` column only when EVERY line's
    # second token is a structured id (same test as detection's ID case) —
    # all-or-nothing so a file never mixes 2- and 3-column rows.
    local with_id=1
    local _id_re='^[0-9A-Fa-f:.%-]+$'
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        _rlr_split "$line" || continue
        local _tok2="${_RLR_REST%% *}"
        [[ "$_tok2" == "$_RLR_REST" ]] && { with_id=0; break; }  # no 3rd part
        if [[ ! "$_tok2" =~ $_id_re || ! "$_tok2" =~ [0-9] || ! "$_tok2" =~ [:-] ]]; then
            with_id=0; break
        fi
    done <<< "$text"

    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        _rlr_split "$line" || continue
        entry=$((entry + 1))
        result+="entry${entry}.label ${_RLR_LEAD}"$'\n'
        if [[ $with_id -eq 1 ]]; then
            result+="entry${entry}.id ${_RLR_REST%% *}"$'\n'
            result+="entry${entry}.value ${_RLR_REST#* }"$'\n'
        else
            result+="entry${entry}.value ${_RLR_REST}"$'\n'
        fi
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
