#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: equals
## Description: Extract field=value pairs from equals-delimited data
## Version: 1.2
## Priority: 65
## Confidence-Max: 75
## Sample: samples/equals/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    # CONFIDENCE REFLECTS EVIDENCE (extract/README.md "Confidence rubric").
    # A block where (nearly) EVERY non-blank line is a tight `KEY=VALUE` with a
    # sane key — env/printenv, systemctl show, git config --list, locale, .env
    # files — is the format itself: format-specific tier (75). Pins
    # (`name==1.2.3`) and signed env-diff lines count as valid too. Needs >=2
    # lines so a single stray assignment in free text stays weak.
    # Anything weaker scores 50..55, scaled by the share of lines that are
    # assignments in ANY form the detector accepts (tight, pin, signed, or
    # space-padded `key = value` — sysctl, postconf): a lone `=` in four lines
    # of prose scores 51, a whole `key = value` file 55. An `=` can sit
    # anywhere in a line, so it is weaker evidence than a line-LEADING
    # `label:` (colons, 55..60, wins a tie on priority); it still ties or
    # beats the catch-alls (text-lines 50, line-records <= 55 — equals wins
    # both ties on priority) and stays below a real table (aligned-columns
    # >= 60). It
    # used to be a flat 35 — under provost's filing threshold — but under
    # confidence ranking a sub-50 score ranks below text-lines, which then
    # claims (and files) the input anyway.
    local _cf_line _cf_nb=0 _cf_ok=0 _cf_any=0
    if (( ${#text} > _FR_BIG_BYTES )); then
        # BIG input: both loops below in one awk pass (see _FR_BIG_BYTES).
        # The {0,63}-bounded keys are checked by length — mawk-safe, no
        # interval expressions. Prints "<non-blank> <kv-lines> <any-form
        # lines> <any-hit>".
        local _cf_hit=0
        read -r _cf_nb _cf_ok _cf_any _cf_hit < <(cat <<< "$text" | awk '
            function keyok(t, re,    i, k) {
                i = index(t, "="); if (!i) return 0
                k = substr(t, 1, i - 1)
                if (k !~ re || length(k) > 64) return 0
                return substr(t, i + 1, 1) != "="
            }
            {
                # the four line forms the detection loop accepts
                if ($0 ~ /^[A-Za-z][A-Za-z0-9_. -]*=[^=]/ \
                    || $0 ~ /^[A-Za-z0-9_.-]+==[^= \t\n\v\f\r]+$/ \
                    || $0 ~ /^[+-][A-Za-z][A-Za-z0-9_.]*=[^=]/ \
                    || $0 ~ /^[A-Za-z][A-Za-z0-9_().: -]* = [^=]/) { hit = 1; nany++ }
                if ($0 !~ /[^ \t\n\v\f\r]/) next
                nb++
                t = $0; ok = keyok(t, "^[A-Za-z_][A-Za-z0-9_.-]*$")
                if (!ok && t ~ /^export[ \t\n\v\f\r]+/) {
                    sub(/^export[ \t\n\v\f\r]+/, "", t)
                    ok = keyok(t, "^[A-Za-z_][A-Za-z0-9_.-]*$")
                }
                if (!ok && $0 ~ /^[A-Za-z0-9_.-]+==[^= \t\n\v\f\r]+$/) ok = 1
                if (!ok && $0 ~ /^[+-]/) ok = keyok(substr($0, 2), "^[A-Za-z_][A-Za-z0-9_.]*$")
                if (ok) nok++
            }
            END { printf "%d %d %d %d\n", nb, nok, nany, hit }')
        [[ $_cf_nb -gt 0 ]] && _STRATEGY_CONFIDENCE=$(( 50 + _cf_any * 5 / _cf_nb ))
        if [[ $_cf_nb -ge 2 && $(( _cf_ok * 100 )) -ge $(( _cf_nb * 90 )) ]]; then
            _STRATEGY_CONFIDENCE=75
            _STRATEGY_CONFIDENCE_REASON="${_cf_ok}/${_cf_nb} lines are KEY=VALUE"
        fi
        [[ $_cf_hit -eq 1 ]]
        return
    fi
    local _cf_kv='^(export[[:space:]]+)?[A-Za-z_][A-Za-z0-9_.-]{0,63}=([^=]|$)'
    local _cf_pin='^[A-Za-z0-9_.-]+==[^=[:space:]]+$'
    local _cf_sig='^[+-][A-Za-z_][A-Za-z0-9_.]{0,63}=([^=]|$)'
    # The four line forms the detection loop below accepts.
    local _cf_a1='^[A-Za-z][A-Za-z0-9_.\ -]*=[^=]' _cf_a2='^[+-][A-Za-z][A-Za-z0-9_.]*=[^=]'
    local _cf_a3='^[A-Za-z][A-Za-z0-9_().:\ -]*\ =\ [^=]'
    while IFS= read -r _cf_line; do
        [[ -z "${_cf_line//[[:space:]]/}" ]] && continue
        _cf_nb=$((_cf_nb + 1))
        if [[ "$_cf_line" =~ $_cf_kv || "$_cf_line" =~ $_cf_pin || "$_cf_line" =~ $_cf_sig ]]; then
            _cf_ok=$((_cf_ok + 1))
        fi
        if [[ "$_cf_line" =~ $_cf_a1 || "$_cf_line" =~ $_cf_pin || "$_cf_line" =~ $_cf_a2 \
              || "$_cf_line" =~ $_cf_a3 ]]; then
            _cf_any=$((_cf_any + 1))
        fi
    done <<< "$text"
    [[ $_cf_nb -gt 0 ]] && _STRATEGY_CONFIDENCE=$(( 50 + _cf_any * 5 / _cf_nb ))
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

# _strat_equals_extract_awk TEXT — strategy_extract for a BIG input in awk
# passes, byte-identical: the pin / cfg block modes, and the general loop with
# clean_text's date / paren protection and restore_text_values folded in per
# line. Returns 3 (nothing printed) when a line needs bash-only semantics — a
# paren span holding a glob / `&` byte (clean_text substitutes it as a
# PATTERN) or an over-long non-ASCII key (${#key} counts characters) — and
# the caller runs the bash loops instead.
_strat_equals_extract_awk () {
    local _m _o
    _m="$(cat <<< "$1" | awk '
        $0 !~ /[^ \t\n\v\f\r]/ { next }
        {
            nb++
            if ($0 ~ /^[A-Za-z0-9_.-]+==[^= \t\n\v\f\r]+$/) pin++
            if ($0 ~ /^[A-Za-z_][^ \t\n\v\f\r=]*(=[^ \t\n\v\f\r]*)?$/) {
                tight++
                if (index($0, "=")) haseq = 1; else bare++
            }
        }
        END {
            if (nb >= 2 && pin == nb) print "pin"
            else if (nb >= 2 && tight == nb && haseq && bare >= 1) print "cfg"
            else print "kv"
        }')"
    if [[ "$_m" == pin ]]; then
        cat <<< "$1" | awk '
            $0 !~ /[^ \t\n\v\f\r]/ { next }
            { e++; i = index($0, "==")
              printf "entry%d.package %s\nentry%d.version %s\n", e, substr($0, 1, i - 1), e, substr($0, i + 2) }
            END { if (e > 0) printf "total_entries %d\n", e }'
        return 0
    fi
    if [[ "$_m" == cfg ]]; then
        cat <<< "$1" | awk '
            $0 !~ /[^ \t\n\v\f\r]/ { next }
            { e++; i = index($0, "=")
              if (i) { k = substr($0, 1, i - 1); v = substr($0, i + 1) } else { k = $0; v = "true" }
              printf "entry%d.key %s\nentry%d.value %s\n", e, k, e, v }
            END { if (e > 0) printf "total_entries %d\n", e }'
        return 0
    fi
    _o="$(cat <<< "$1" | awk '
        BEGIN { SP = sprintf("%c", 30); CO = sprintf("%c", 31) }
        {
            line = $0
            # clean_text: protect " Mon DD HH:MM:SS YYYY" dates and "(… " spans
            if (index(line, ":")) {
                while (match(line, / [A-Za-z][A-Za-z][A-Za-z] [0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9] [0-9][0-9][0-9][0-9]/)) {
                    m = substr(line, RSTART, RLENGTH)
                    r = " " substr(m, 2, 3) SP substr(m, 6, 2) SP substr(m, 9, 2) CO substr(m, 12, 2) CO substr(m, 15, 2) SP substr(m, 18, 4)
                    line = substr(line, 1, RSTART - 1) r substr(line, RSTART + RLENGTH)
                }
            }
            if (index(line, "(")) {
                while (match(line, /[(][^) ]*[ ]/)) {
                    m = substr(line, RSTART, RLENGTH)
                    if (m ~ /[][*?\\&+@!]/) { bail = 1; exit 3 }
                    line = substr(line, 1, RSTART - 1) substr(m, 1, length(m) - 1) SP substr(line, RSTART + RLENGTH)
                }
            }
            if (line == "" || !index(line, "=")) next
            if (index(line, "==") || index(line, "+=") || index(line, "!=")) next
            s = line
            sub(/^ +/, "", s)
            if (substr(s, 1, 2) == "* ") s = substr(s, 3)
            i = index(s, "="); key = substr(s, 1, i - 1); val = substr(s, i + 1)
            if (key == "") next
            if (length(key) > 50) { if (key ~ /[^ -~]/) { bail = 1; exit 3 }; next }
            if (key ~ /^[0-9]/) next
            gsub(/ /, "_", key); sub(/^_/, "", key); sub(/_$/, "", key)
            sub(/^ +/, "", val); sub(/ +$/, "", val)
            if (val == "") val = "\"\""
            # restore_text_values: sentinels -> "_" in the name, back to
            # space / colon in the value
            gsub(SP, "_", key); gsub(CO, "_", key)
            gsub(SP, " ", val); gsub(CO, ":", val)
            print key " " val
        }')" || return 3
    printf '%s\n' "$_o"
    return 0
}

strategy_extract () {
    local text="$1"
    if (( ${#text} > _FR_BIG_BYTES )); then
        local _eqx_rc=0
        _strat_equals_extract_awk "$text" || _eqx_rc=$?
        [[ $_eqx_rc -eq 3 ]] || return $_eqx_rc
    fi

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
