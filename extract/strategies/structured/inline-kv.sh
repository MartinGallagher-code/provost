#!/bin/bash
## Name: inline-kv
## Description: Space-separated key=value pairs on a line (id, KEY=v KEY=v ...)
## Version: 1.0
## Priority: 30
## Sample: samples/inline-kv/id.txt

# Every non-blank line is a record of >=2 space-separated `key=value` tokens —
# e.g. `id` output (`uid=1000(alice) gid=1000(alice) groups=…`). Tidied to one
# row per line with a column per key.

# Tokenize one line into _IKV_TOKS, QUOTE-AWARE: a `"` or `'` opens a protected
# span (spaces inside don't split) only when it starts the token or directly
# follows `=` — the value-start-only rule the csv/quoted-fields parsers use, so
# a mid-word apostrophe (`don't`) or inch mark stays literal. Without this,
# logfmt (`msg="request done, 200 OK"`) and quoted k=v dumps (`k1="a b"`) shred
# into word fragments and the kv-majority gate below wrongly declines them.
_ikv_split () {
    local line="$1"
    local tok="" i c q="" prev="" n=${#line}
    _IKV_TOKS=()
    for ((i = 0; i < n; i++)); do
        c="${line:$i:1}"
        if [[ -n "$q" ]]; then
            tok+="$c"
            [[ "$c" == "$q" ]] && q=""
        elif [[ "$c" == '"' || "$c" == "'" ]]; then
            if [[ -z "$tok" || "$prev" == "=" ]]; then q="$c"; fi
            tok+="$c"
        elif [[ "$c" == ' ' || "$c" == '	' ]]; then
            [[ -n "$tok" ]] && _IKV_TOKS+=("$tok")
            tok=""
        else
            tok+="$c"
        fi
        prev="$c"
    done
    [[ -n "$tok" ]] && _IKV_TOKS+=("$tok")
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0

    local nonblank=0 kvlines=0 _l
    while IFS= read -r _l; do
        [[ -z "${_l//[[:space:]]/}" ]] && continue
        nonblank=$((nonblank + 1))
        local toks; toks=()
        _ikv_split "$_l"; toks=("${_IKV_TOKS[@]}")
        local n=${#toks[@]} kv=0 t
        for t in "${toks[@]}"; do [[ "$t" =~ ^[A-Za-z_][A-Za-z0-9_-]*=.+ ]] && kv=$((kv + 1)); done
        # A leading `label:` token (blkid's `/dev/sda1:`) is the record's NAME,
        # not a failed pair — don't let it count against the kv majority.
        [[ $n -ge 2 && "${toks[0]}" == *: && ! "${toks[0]}" == *=* ]] && n=$((n - 1))
        [[ $n -ge 2 && $kv -ge 2 && $(( kv * 100 / n )) -ge 60 ]] && kvlines=$((kvlines + 1))
        [[ $nonblank -ge 40 ]] && break
    done <<< "$text"

    # Every non-blank line must be inline-kv (so we don't claim prose that
    # happens to contain one `a=b`).
    [[ $nonblank -ge 1 && $kvlines -eq $nonblank ]] || return 1
    _STRATEGY_CONFIDENCE=80
    return 0
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 _l
    while IFS= read -r _l; do
        [[ -z "${_l//[[:space:]]/}" ]] && continue
        local toks; toks=()
        _ikv_split "$_l"; toks=("${_IKV_TOKS[@]}")
        entry=$((entry + 1))
        # A leading `label:` token names the record (blkid's `/dev/sda1:`) —
        # emit it as a `name` column so the device/label isn't dropped.
        if [[ "${toks[0]:-}" == *: && ! "${toks[0]:-}" == *=* ]]; then
            local _nm="${toks[0]%:}"
            [[ -n "$_nm" ]] && result+="entry${entry}.name ${_nm}"$'\n'
            toks=("${toks[@]:1}")
        fi
        local t
        for t in "${toks[@]}"; do
            [[ "$t" =~ ^([A-Za-z_][A-Za-z0-9_-]*)=(.*)$ ]] || continue
            local k="${BASH_REMATCH[1]//./_}" v="${BASH_REMATCH[2]}"
            # A value the tokenizer protected as one fully-quoted span carries
            # field-encoding quotes, not data — strip the matching outer pair
            # (`msg="request done, 200 OK"` → `request done, 200 OK`).
            if [[ ${#v} -ge 2 ]]; then
                case "$v" in
                    '"'*'"') v="${v#\"}"; v="${v%\"}" ;;
                    "'"*"'") v="${v#\'}"; v="${v%\'}" ;;
                esac
            fi
            result+="entry${entry}.${k} ${v}"$'\n'
        done
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
