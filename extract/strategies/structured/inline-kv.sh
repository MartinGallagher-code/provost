#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

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

# Gauge-line unwrap: when EVERY non-blank line is wrapped in one outer `[…]`
# (aria2c's `[#f1a2b3 512MiB/1.4GiB(36%) CN:8 …]`), the brackets are display
# chrome — strip them so the inner fields parse. Guarded away from JSON: an
# inner starting `"`/`{`/`[` or containing no space is data, not a gauge.
_ikv_body () {
    local text="$1" _l all=1 inner
    while IFS= read -r _l; do
        [[ "${_l}" != *[![:space:]]* ]] && continue
        if [[ "$_l" =~ ^\[(.+)\]$ ]]; then
            inner="${BASH_REMATCH[1]}"
            [[ "$inner" == *" "* ]] || { all=0; break; }
            case "$inner" in '"'*|'{'*|'['*) all=0 ;; esac
            [[ $all -eq 0 ]] && break
        else
            all=0; break
        fi
    done <<< "$text"
    if [[ $all -eq 1 ]]; then
        _fr_lines "$text"
        for _l in "${_FR_LINES[@]}"; do
            if [[ "$_l" =~ ^\[(.+)\]$ ]]; then printf '%s\n' "${BASH_REMATCH[1]}"
            else printf '%s\n' "$_l"; fi
        done
        _l=""
    else
        printf '%s\n' "$text"
    fi
}

# _ikv_body_v TEXT — `$(_ikv_body TEXT)` in _IKV_BODY without the fork. The
# common case (no gauge unwrap) is TEXT minus trailing newlines — exactly what
# the command substitution captured; the rare unwrap case keeps the original.
_ikv_body_v () {
    local text="$1" _l all=1 inner
    _fr_lines "$text"
    for _l in "${_FR_LINES[@]}"; do
        [[ "${_l}" != *[![:space:]]* ]] && continue
        if [[ "$_l" =~ ^\[(.+)\]$ ]]; then
            inner="${BASH_REMATCH[1]}"
            [[ "$inner" == *" "* ]] || { all=0; break; }
            case "$inner" in '"'*|'{'*|'['*) all=0 ;; esac
            [[ $all -eq 0 ]] && break
        else
            all=0; break
        fi
    done
    if [[ $all -eq 1 ]]; then
        _IKV_BODY="$(_ikv_body "$text")"
    else
        _IKV_BODY="${text%"${text##*[!$'\n']}"}"
    fi
}

# Is a token a strict COLON pair (`CN:8`, `DL:12MiB`, `model:Pixel_8`)?
# Exactly one colon, alpha-led label, value with no colon/slash-start — so
# timestamps (06:00:12), MACs (3c:84:…), URLs (http://…) and ratios never
# qualify.
_ikv_colon_tok () {
    [[ "$1" =~ ^[A-Za-z][A-Za-z0-9_-]*:[^:/[:space:]][^:]*$ ]]
}

strategy_detect () {
    local text="$1"
    _ikv_body_v "$text"; text="$_IKV_BODY"
    _STRATEGY_CONFIDENCE=0

    local nonblank=0 kvlines=0 clines=0 _l
    local clabels="" cuniform=1
    _fr_lines "$text"
    for _l in "${_FR_LINES[@]}"; do
        [[ "${_l}" != *[![:space:]]* ]] && continue
        nonblank=$((nonblank + 1))
        local toks; toks=()
        _ikv_split "$_l"; toks=("${_IKV_TOKS[@]}")
        local n=${#toks[@]} kv=0 ckv=0 t clab=""
        for t in "${toks[@]}"; do
            [[ "$t" =~ ^[A-Za-z_][A-Za-z0-9_-]*=.+ ]] && kv=$((kv + 1))
            _ikv_colon_tok "$t" && { ckv=$((ckv + 1)); clab+="${t%%:*} "; }
        done
        # A leading `label:` token (blkid's `/dev/sda1:`) is the record's NAME,
        # not a failed pair — don't let it count against the kv majority.
        [[ $n -ge 2 && "${toks[0]}" == *: && ! "${toks[0]}" == *=* ]] && n=$((n - 1))
        [[ $n -ge 2 && $kv -ge 2 && $(( kv * 100 / n )) -ge 60 ]] && kvlines=$((kvlines + 1))
        # COLON flavor: >=2 strict colon pairs and a colon-pair majority.
        # Riskier than `=` (colons appear in free text), so detection also
        # demands the SAME label set on every line (aria2c's CN/DL/ETA,
        # adb's product/model/device) — checked across the loop.
        if [[ $n -ge 2 && $ckv -ge 2 && $(( ckv * 100 / n )) -ge 60 ]]; then
            clines=$((clines + 1))
            [[ -z "$clabels" ]] && clabels="$clab"
            [[ "$clab" != "$clabels" ]] && cuniform=0
        fi
        [[ $nonblank -ge 40 ]] && break
    done

    # Every non-blank line must be inline-kv (so we don't claim prose that
    # happens to contain one `a=b`).
    if [[ $nonblank -ge 1 && $kvlines -eq $nonblank ]]; then
        _STRATEGY_CONFIDENCE=80
        return 0
    fi
    if [[ $nonblank -ge 2 && $clines -eq $nonblank && $cuniform -eq 1 ]]; then
        _STRATEGY_CONFIDENCE=80
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    _ikv_body_v "$text"; text="$_IKV_BODY"
    local result="" entry=0 _l
    _fr_lines "$text"
    for _l in "${_FR_LINES[@]}"; do
        [[ "${_l}" != *[![:space:]]* ]] && continue
        local toks; toks=()
        _ikv_split "$_l"; toks=("${_IKV_TOKS[@]}")
        entry=$((entry + 1))
        # A leading `label:` token names the record (blkid's `/dev/sda1:`) —
        # emit it as a `name` column so the device/label isn't dropped.
        # ansible-recap style spells it as two tokens (`web01 : ok=12 …`).
        if [[ "${toks[0]:-}" == *: && ! "${toks[0]:-}" == *=* ]]; then
            local _nm="${toks[0]%:}"
            [[ -n "$_nm" ]] && result+="entry${entry}.name ${_nm}"$'\n'
            toks=("${toks[@]:1}")
        elif [[ "${toks[1]:-}" == ":" && ! "${toks[0]:-}" == *=* ]]; then
            result+="entry${entry}.name ${toks[0]}"$'\n'
            toks=("${toks[@]:2}")
        fi
        # COLON flavor (aria2c's `#id 512MiB/1.4GiB(36%) CN:8 DL:12MiB ETA:1m14s`):
        # when the line has no `=` pairs but >=2 strict colon pairs, emit the
        # colon pairs as fields and the leading UNLABELED run as positional
        # columns (A, B, …) so the id/progress cells aren't dropped.
        local _has_eq=0 t
        for t in "${toks[@]}"; do
            [[ "$t" =~ ^[A-Za-z_][A-Za-z0-9_-]*=.+ ]] && { _has_eq=1; break; }
        done
        if [[ $_has_eq -eq 0 ]]; then
            local _cn=0
            for t in "${toks[@]}"; do _ikv_colon_tok "$t" && _cn=$((_cn + 1)); done
            if [[ $_cn -ge 2 ]]; then
                local _letters=(A B C D E F G H I J K L M) _li=0
                for t in "${toks[@]}"; do
                    if _ikv_colon_tok "$t"; then
                        result+="entry${entry}.${t%%:*} ${t#*:}"$'\n'
                    else
                        result+="entry${entry}.${_letters[$_li]:-Z} ${t}"$'\n'
                        _li=$((_li + 1))
                    fi
                done
                continue
            fi
        fi
        # An UNLABELED token between the pairs is still the row's data — for
        # `openssl ciphers -v` the two leading tokens are the cipher's NAME
        # and TLS version, i.e. the entire point of the output, and dropping
        # what the pair-harvest didn't match lost them. Same treatment the
        # colon flavor above already gives: positional letter columns.
        local _eletters=(A B C D E F G H I J K L M) _eli=0
        for t in "${toks[@]}"; do
            if [[ ! "$t" =~ ^([A-Za-z_][A-Za-z0-9_-]*)=(.*)$ ]]; then
                result+="entry${entry}.${_eletters[$_eli]:-Z} ${t}"$'\n'
                _eli=$((_eli + 1))
                continue
            fi
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
    done
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
