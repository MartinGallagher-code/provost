#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: aligned-columns
## Description: Extract fields from whitespace-aligned columnar output (ps, df, mount, etc.)
## Version: 3.1
## Priority: 55
## Confidence-Max: 69
## Sample: samples/aligned-columns/basic.txt

# Count a line's 2-space-gap segments — the columns a fixed-width header defines
# (a multi-word cell like "Best Rate MB/s" is ONE segment; only a >=2-space gap
# starts a new one).
_ac_seg () {
    _ac_seg_v "$1"
    printf '%s' "$_AC_SEG"
}

# _ac_seg_v LINE — _ac_seg's count in the global _AC_SEG, fork-free and without
# a per-character loop (`${l:i:1}` rescans the string from the start in a
# multibyte locale, so the scan was quadratic per line). After the leading
# whitespace trim the line starts on a non-space; a segment ends only at a run
# of >=2 SPACES (tabs and single spaces stay inside a cell), and a trailing run
# starts no new segment — so the count is 1 + the number of interior >=2-space
# runs. Lines carrying the \001 marker byte take the reference scan.
_ac_seg_v () {
    local l="$1" t u
    l="${l#"${l%%[![:space:]]*}"}"
    if [[ -z "$l" ]]; then _AC_SEG=0; return 0; fi
    if [[ "$l" == *$'\001'* ]]; then _ac_seg_scan "$l"; return 0; fi
    l="${l%"${l##*[! ]}"}"                  # trailing spaces start no segment
    t="${l//  /$'\001'}"                    # each space PAIR -> one marker
    t="${t//$'\001' /$'\001'}"              # an odd run's leftover space
    while [[ "$t" == *$'\001\001'* ]]; do t="${t//$'\001\001'/$'\001'}"; done
    u="${t//[!$'\001']/}"
    _AC_SEG=$(( ${#u} + 1 ))
}

# Reference character scan (the original _ac_seg body); sets _AC_SEG.
_ac_seg_scan () {
    local l="$1" n=0 i=0 L
    l="${l#"${l%%[![:space:]]*}"}"; L=${#l}
    while (( i < L )); do
        while (( i < L )) && [[ "${l:i:1}" == " " ]]; do ((i++)); done
        (( i >= L )) && break
        ((n++))
        while (( i < L )) && ! { [[ "${l:i:1}" == " " ]] && [[ "${l:i+1:1}" == " " ]]; }; do ((i++)); done
    done
    _AC_SEG=$n
}

# Is the token a value (number/size/%/time/version — anything starting with a
# digit)? A header label never does.
_ac_is_value () { [[ "$1" =~ ^[0-9] ]]; }

# _ac_stream_lines STREAM — _FR_LINES holds the lines a `while IFS= read -r l`
# loop reads from a stream carrying exactly STREAM: newline-terminated lines
# only (a final unterminated segment is never iterated), and none at all for
# an empty stream. Lets a helper's output be captured in one bulk read instead
# of consumed byte-by-byte from a pipe.
_ac_stream_lines () {
    if [[ "$1" != *$'\n'* ]]; then
        _FR_LINES=(); _FR_LINES_OK=0
        return 0
    fi
    _fr_lines "${1%$'\n'*}"
}

# ---------------------------------------------------------------------------
# VALUE-SPACE ENCODING — the ONE place this strategy decides how a value's
# inner spaces are written: tokens a row carries beyond the last header
# column are absorbed into that column, joined by this string (a space: values
# keep their spaces). Both emitters — the awk fast path (_ac_emit_rows) and the
# bash phrase-merge loop in strategy_extract — use it.
_AC_VALUE_JOIN=" "
# ---------------------------------------------------------------------------

# _ac_emit_rows HEADERS_TAB_JOINED < rows — the tokenized emitter's fast path:
# for each row (1 row = 1 entry) split on runs of space/tab (bash's default
# IFS; rows are single lines), emit `entry<N>.<header_i> <token_i>` for every
# column the row reaches, the last column absorbing any surplus tokens joined
# by _AC_VALUE_JOIN. Byte-for-byte the output of the bash emission loop in
# strategy_extract when no phrase merge applies. mawk-safe.
_ac_emit_rows () {
    # (strings go in through ENVIRON: `awk -v` would expand backslash escapes)
    _AC_HDRS="$1" _AC_VJOIN="$_AC_VALUE_JOIN" awk '
    BEGIN { nh = split(ENVIRON["_AC_HDRS"], H, "\t"); vjoin = ENVIRON["_AC_VJOIN"] }
    {
        line = $0
        sub(/^[ \t]+/, "", line); sub(/[ \t]+$/, "", line)
        n = split(line, t, /[ \t]+/)
        entry++
        for (i = 1; i <= nh && i <= n; i++) {
            v = t[i]
            if (i == nh) for (j = nh + 1; j <= n; j++) v = v vjoin t[j]
            printf "entry%d.%s %s\n", entry, H[i], v
        }
    }'
}

# _ac_join_tab CELL… — the cells TAB-joined in _AC_JOINED; the fork-free form
# of `$(IFS=$'\t'; printf '%s' "${arr[*]}")` (cells never hold a newline).
_ac_join_tab () {
    local IFS=$'\t'
    _AC_JOINED="$*"
}

# Echo the block with leading preamble removed: an `ls -l` "total <n>" line, or
# short banner/preamble lines with <2 columns (e.g. `apt list`'s "Listing…"),
# but only when a real (>=2 column) table follows.
_ac_body () {
    _ac_body_v "$1"
    printf '%s' "$_AC_BODY"
}

# _ac_body_v TEXT — _ac_body's result in the global _AC_BODY, exactly as
# `$(_ac_body TEXT)` captured it (trailing newlines stripped). A pure function
# of TEXT, memoised: detect + shape + extract used to recompute it five times
# per input, each in a forked subshell.
# TWO slots: on a big input detection alternates between the bounded sample
# and the full text (the sample screen, then the full-text confirm — twice,
# since the extract phase re-runs detect), and a single slot recomputed the
# full text's body each time (~2 s per 10 MB). A length check first spares the
# string compare (~0.3 s per 10 MB) when the keys plainly differ.
# (Initialised only once: the loader re-sources this file between the detect
# and extract phases, and a plain assignment here wiped the memo each time.
# The key is the full text, so a memo outliving one input is still exact.)
: "${_AC_BODY_KEY=}" "${_AC_BODY_OK:=0}" "${_AC_BODY=}"
: "${_AC_BODY_KEY2=}" "${_AC_BODY2=}" "${_AC_BODY_OK2:=0}"
_ac_body_v () {
    if [[ $_AC_BODY_OK -eq 1 ]] && (( ${#1} == ${#_AC_BODY_KEY} )) && [[ "$1" == "$_AC_BODY_KEY" ]]; then return 0; fi
    local _out
    if [[ $_AC_BODY_OK2 -eq 1 ]] && (( ${#1} == ${#_AC_BODY_KEY2} )) && [[ "$1" == "$_AC_BODY_KEY2" ]]; then
        # hit in the second slot: swap it to the front
        _out="$_AC_BODY"; _AC_BODY="$_AC_BODY2"; _AC_BODY2="$_out"
        _out="$_AC_BODY_KEY"; _AC_BODY_KEY="$_AC_BODY_KEY2"; _AC_BODY_KEY2="$_out"
        return 0
    fi
    if [[ $_AC_BODY_OK -eq 1 ]]; then
        _AC_BODY_KEY2="$_AC_BODY_KEY"; _AC_BODY2="$_AC_BODY"; _AC_BODY_OK2=1
    fi
    _ac_body_compute "$1"
    if (( ${#_AC_BODY_RAW} > _FR_BIG_BYTES )); then
        # (count the trailing newlines from the end instead of the
        # `${x##*[!$'\n']}` suffix scan, which walks the whole big string)
        local _tn=0
        while (( _tn < ${#_AC_BODY_RAW} )) && [[ "${_AC_BODY_RAW: -$((_tn + 1)):1}" == $'\n' ]]; do
            _tn=$((_tn + 1))
        done
        _AC_BODY="${_AC_BODY_RAW:0:$(( ${#_AC_BODY_RAW} - _tn ))}"
    else
    _out="$_AC_BODY_RAW"
    _AC_BODY="${_out%"${_out##*[!$'\n']}"}"
    fi
    _AC_BODY_KEY="$1"
    _AC_BODY_OK=1
}

# The _ac_body computation proper; leaves its printed form in _AC_BODY_RAW.
_ac_body_compute () {
    local text="$1" _l _tk out="" started=0 has_table=0

    # AUDIT-REPORT chrome (aureport family): `====` rule lines are never
    # data; a 1-2 token line DIRECTLY ABOVE a rule is the report title; a
    # single `# label label …` line among the first lines is the real
    # header wearing a comment marker — strip the marker. Sequentially
    # numbered `N.` first tokens on every data row are row numbers (the
    # melt's `n` column already carries that) — strip them.
    if [[ "$text" == *$'\n'====* ]]; then
        local _ar_lines=() _ar_i
        _fr_lines "$text"; _ar_lines=("${_FR_LINES[@]}")
        # drop rules + the title above the first rule
        local _ar_out=() _ar_hash=-1 _ar_hashes=0
        for ((_ar_i = 0; _ar_i < ${#_ar_lines[@]}; _ar_i++)); do
            _l="${_ar_lines[$_ar_i]}"
            if [[ "$_l" =~ ^[[:space:]]*={4,}[[:space:]]*$ ]]; then
                # title directly above the FIRST rule (<=2 tokens, no colon)
                if [[ ${#_ar_out[@]} -ge 1 ]]; then
                    local _ar_last="${_ar_out[$(( ${#_ar_out[@]} - 1 ))]}"
                    local _ar_lt=(); _fr_tok "$_ar_last"; _ar_lt=("${_FR_TOK[@]}")
                    [[ ${#_ar_lt[@]} -le 2 && ! "$_ar_last" == *:* && "$_ar_last" =~ ^[A-Z] ]] && unset '_ar_out[$(( ${#_ar_out[@]} - 1 ))]'
                    _ar_out=("${_ar_out[@]}")
                fi
                continue
            fi
            [[ "$_l" == "# "* ]] && { _ar_hashes=$((_ar_hashes + 1)); _ar_hash=${#_ar_out[@]}; }
            _ar_out+=("$_l")
        done
        # exactly one `# …` line within the first 3 kept lines → header
        if [[ $_ar_hashes -eq 1 && $_ar_hash -ge 0 && $_ar_hash -le 2 ]]; then
            _ar_out[$_ar_hash]="${_ar_out[$_ar_hash]#\# }"
        fi
        # sequential `N.` first tokens on every line after the header
        local _ar_seq=1 _ar_want=1 _ar_started=0
        for ((_ar_i = _ar_hash >= 0 ? _ar_hash + 1 : 1; _ar_i < ${#_ar_out[@]}; _ar_i++)); do
            [[ "${_ar_out[$_ar_i]}" != *[![:space:]]* ]] && continue
            _fr_tok "${_ar_out[$_ar_i]}"; _tk=("${_FR_TOK[@]}")
            [[ "${_tk[0]:-}" == "${_ar_want}." ]] || { _ar_seq=0; break; }
            _ar_want=$((_ar_want + 1)); _ar_started=1
        done
        if [[ $_ar_seq -eq 1 && $_ar_started -eq 1 && $_ar_want -ge 3 ]]; then
            for ((_ar_i = _ar_hash >= 0 ? _ar_hash + 1 : 1; _ar_i < ${#_ar_out[@]}; _ar_i++)); do
                [[ "${_ar_out[$_ar_i]}" != *[![:space:]]* ]] && continue
                local _ar_rest="${_ar_out[$_ar_i]#*.}"
                _ar_rest="${_ar_rest# }"
                _ar_out[$_ar_i]="$_ar_rest"
            done
        fi
        text="$(printf '%s\n' "${_ar_out[@]}")"
    fi

    # SHELL LINE CONTINUATION: a row ending in ` \` continues on the next,
    # INDENTED line (crontab's wrapped command) — one logical row, so the
    # continuation is joined back (single space) instead of becoming a
    # bogus row of its own. Gated on the literal ` \<newline><blank>`.
    if [[ "$text" == *$' \\\n '* || "$text" == *$' \\\n\t'* ]]; then
        _fr_lines "$text"
        local _lj_out=() _lj_l _lj_i _lj_n=${#_FR_LINES[@]}
        for ((_lj_i = 0; _lj_i < _lj_n; _lj_i++)); do
            _lj_l="${_FR_LINES[$_lj_i]}"
            while [[ "$_lj_l" == *" \\" && $((_lj_i + 1)) -lt $_lj_n \
                     && "${_FR_LINES[$((_lj_i + 1))]}" == [[:space:]]*[![:space:]]* ]]; do
                _lj_i=$((_lj_i + 1))
                local _lj_c="${_FR_LINES[$_lj_i]}"
                _lj_c="${_lj_c#"${_lj_c%%[![:space:]]*}"}"
                _lj_l="${_lj_l% \\} ${_lj_c}"
            done
            _lj_out+=("$_lj_l")
        done
        printf -v text '%s\n' "${_lj_out[@]}"
        text="${text%$'\n'}"
    fi

    # PAGE BANNERS: a paginated report re-prints its title (`Sales Report
    # Page 2`) above each page's header. A line ending `Page <n>`, followed
    # by a blank line, whose digit-normalised form occurs >= 2 times is page
    # chrome — dropped, so the repeated header below it is the ordinary
    # header-repeat the table loop already removes. Gated on `Page `.
    if [[ "$text" == *"Page "[0-9]* ]]; then
        _fr_lines "$text"
        local _pb_n=${#_FR_LINES[@]} _pb_i _pb_l _pb_k
        local -A _pb_cnt=()
        for ((_pb_i = 0; _pb_i < _pb_n; _pb_i++)); do
            _pb_l="${_FR_LINES[$_pb_i]}"
            [[ "$_pb_l" =~ [Pp]age[[:space:]]+[0-9]+[[:space:]]*$ ]] || continue
            _pb_k="${_pb_l//[0-9]/#}"
            _pb_cnt[$_pb_k]=$(( ${_pb_cnt[$_pb_k]:-0} + 1 ))
        done
        if [[ ${#_pb_cnt[@]} -gt 0 ]]; then
            local _pb_out=() _pb_drop=0
            for ((_pb_i = 0; _pb_i < _pb_n; _pb_i++)); do
                _pb_l="${_FR_LINES[$_pb_i]}"
                if [[ "$_pb_l" =~ [Pp]age[[:space:]]+[0-9]+[[:space:]]*$ ]]; then
                    _pb_k="${_pb_l//[0-9]/#}"
                    if [[ ${_pb_cnt[$_pb_k]} -ge 2 && $((_pb_i + 1)) -lt $_pb_n \
                          && "${_FR_LINES[$((_pb_i + 1))]}" != *[![:space:]]* ]]; then
                        _pb_drop=1; continue
                    fi
                fi
                _pb_out+=("$_pb_l")
            done
            if [[ $_pb_drop -eq 1 ]]; then
                printf -v text '%s\n' "${_pb_out[@]}"
                text="${text%$'\n'}"
            fi
        fi
    fi

    # WRAPPED LAST CELL (tokenized tables too): a line holding ONE token,
    # indented to at least the start of the header's second-to-last label
    # (>= 8 columns in, header of >= 3 labels), is the previous row's last cell wrapped onto its own line
    # (lsof's `(ESTABLISHED)` under NAME) — the positional path's wrapped-cell
    # rule, for tables that never reach it. Joined back with a space.
    _fr_lines "$text"
    local _wl_n=${#_FR_LINES[@]} _wl_i _wl_h=-1 _wl_off=0
    for ((_wl_i = 0; _wl_i < _wl_n; _wl_i++)); do
        [[ "${_FR_LINES[$_wl_i]}" == *[![:space:]]* ]] && { _wl_h=$_wl_i; break; }
    done
    if [[ $_wl_h -ge 0 ]]; then
        # (offset = start of the header's second-to-last label: a lone token
        # past every column but the last two can only be the last cell)
        local _wl_hd="${_FR_LINES[$_wl_h]}"
        _wl_hd="${_wl_hd%"${_wl_hd##*[![:space:]]}"}"
        local _wl_pre="${_wl_hd%[[:space:]]*}"
        _wl_pre="${_wl_pre%"${_wl_pre##*[![:space:]]}"}"
        local _wl_p2="${_wl_pre##*[[:space:]]}"
        _wl_off=$(( ${#_wl_pre} - ${#_wl_p2} ))
        _fr_tok "$_wl_hd"
        [[ ${#_FR_TOK[@]} -ge 3 ]] || _wl_off=0
    fi
    if [[ $_wl_off -ge 8 ]]; then
        local _wl_hit=0 _wl_l _wl_ind
        for ((_wl_i = _wl_h + 2; _wl_i < _wl_n; _wl_i++)); do
            _wl_l="${_FR_LINES[$_wl_i]}"
            [[ "$_wl_l" == [[:space:]]*[![:space:]]* ]] || continue
            _wl_ind="${_wl_l%%[![:space:]]*}"
            [[ ${#_wl_ind} -ge $_wl_off && "${_wl_l#"$_wl_ind"}" != *[[:space:]]* ]] && { _wl_hit=1; break; }
        done
        if [[ $_wl_hit -eq 1 ]]; then
            local _wl_out=()
            for ((_wl_i = 0; _wl_i < _wl_n; _wl_i++)); do
                _wl_l="${_FR_LINES[$_wl_i]}"
                _wl_ind="${_wl_l%%[![:space:]]*}"
                if [[ $_wl_i -gt $((_wl_h + 1)) && ${#_wl_out[@]} -gt 0 && "$_wl_l" == [[:space:]]*[![:space:]]* \
                      && ${#_wl_ind} -ge $_wl_off && "${_wl_l#"$_wl_ind"}" != *[[:space:]]* \
                      && "${_wl_out[$(( ${#_wl_out[@]} - 1 ))]}" == *[![:space:]]* ]]; then
                    _wl_out[$(( ${#_wl_out[@]} - 1 ))]+=" ${_wl_l#"$_wl_ind"}"
                    continue
                fi
                _wl_out+=("$_wl_l")
            done
            printf -v text '%s\n' "${_wl_out[@]}"
            text="${text%$'\n'}"
        fi
    fi

    # LEADING CHROME BLOCK: a short block (<= 12 lines) of banner / log /
    # ASCII-art lines, a blank line, then the table as the LAST block —
    # `[INFO] Compiled 214 modules` build chatter, a figlet logo — is not
    # part of the table. Dropped only when the final block is unmistakably
    # one: a >= 3-segment all-label header (2+-space columns, no value
    # token) over >= 2 rows that all keep that segment count, and no
    # preamble line that carries letters/digits shares the count (art made
    # only of punctuation is ignored). Size-independent: it inspects the
    # first 13 lines plus one pass for a later blank line.
    _fr_lines "$text"
    local _lcb_n=${#_FR_LINES[@]} _lcb_b=-1 _lcb_i _lcb_pre=0
    for ((_lcb_i = 0; _lcb_i < _lcb_n && _lcb_i <= 13; _lcb_i++)); do
        if [[ "${_FR_LINES[$_lcb_i]}" != *[![:space:]]* ]]; then
            [[ $_lcb_pre -ge 1 ]] && { _lcb_b=$_lcb_i; break; }
        else
            _lcb_pre=$((_lcb_pre + 1))
        fi
    done
    if [[ $_lcb_b -ge 1 && $_lcb_pre -le 12 ]]; then
        local _lcb_t=() _lcb_ok=1 _lcb_l _lcb_trail=0
        for ((_lcb_i = _lcb_b + 1; _lcb_i < _lcb_n; _lcb_i++)); do
            _lcb_l="${_FR_LINES[$_lcb_i]}"
            if [[ "${_lcb_l}" != *[![:space:]]* ]]; then
                [[ ${#_lcb_t[@]} -gt 0 ]] && _lcb_trail=1
                continue
            fi
            [[ $_lcb_trail -eq 1 ]] && { _lcb_ok=0; break; }   # not the last block
            _lcb_t+=("$_lcb_l")
        done
        [[ ${#_lcb_t[@]} -ge 3 ]] || _lcb_ok=0
        local _lcb_hs=0 _lcb_x
        if [[ $_lcb_ok -eq 1 ]]; then
            _ac_seg_v "${_lcb_t[0]}"; _lcb_hs=$_AC_SEG
            [[ $_lcb_hs -ge 3 ]] || _lcb_ok=0
            _fr_tok "${_lcb_t[0]}"
            for _lcb_x in "${_FR_TOK[@]}"; do
                if _ac_is_value "$_lcb_x" || [[ ! "$_lcb_x" =~ [A-Za-z] ]]; then _lcb_ok=0; break; fi
            done
        fi
        if [[ $_lcb_ok -eq 1 ]]; then
            for ((_lcb_i = 1; _lcb_i < ${#_lcb_t[@]} && _lcb_i <= 40; _lcb_i++)); do
                _ac_seg_v "${_lcb_t[$_lcb_i]}"
                [[ $_AC_SEG -eq $_lcb_hs ]] || { _lcb_ok=0; break; }
            done
        fi
        if [[ $_lcb_ok -eq 1 ]]; then
            for ((_lcb_i = 0; _lcb_i < _lcb_b; _lcb_i++)); do
                _lcb_l="${_FR_LINES[$_lcb_i]}"
                [[ "$_lcb_l" == *[A-Za-z0-9]* ]] || continue
                _ac_seg_v "$_lcb_l"
                [[ $_AC_SEG -eq $_lcb_hs ]] && { _lcb_ok=0; break; }
            done
        fi
        if [[ $_lcb_ok -eq 1 ]]; then
            printf -v text '%s\n' "${_lcb_t[@]}"
            text="${text%$'\n'}"
        fi
    fi

    _fr_lines "$text"
    local _fri196; for ((_fri196 = 0; _fri196 < ${#_FR_LINES[@]}; _fri196++)); do _l="${_FR_LINES[$_fri196]}"
        [[ "${_l}" != *[![:space:]]* ]] && continue
        _fr_tok "$_l"; _tk=("${_FR_TOK[@]}")
        [[ ${#_tk[@]} -ge 2 ]] && { has_table=1; break; }
    done

    # The modal (most common) token count of the block — used to spot leading
    # banner lines that are much wider than the table that follows (`w`'s
    # load-average line, numastat's title). Only lines wider by >=3 tokens are
    # banners; a leading line with FEWER tokens can be a group-header row
    # (vmstat) and must stay.
    local _modal=0
    if [[ $has_table -eq 1 ]]; then
        local _mc=() _mn=0
        local _fri210; for ((_fri210 = 0; _fri210 < ${#_FR_LINES[@]}; _fri210++)); do _l="${_FR_LINES[$_fri210]}"
            [[ "${_l}" != *[![:space:]]* ]] && continue
            _fr_tok "$_l"; _tk=("${_FR_TOK[@]}")
            _mc+=("${#_tk[@]}"); _mn=$((_mn + 1)); [[ $_mn -ge 40 ]] && break
        done
        local _a _b _k _best=0
        for _a in "${_mc[@]}"; do
            _k=0; for _b in "${_mc[@]}"; do [[ "$_b" -eq "$_a" ]] && _k=$((_k + 1)); done
            [[ $_k -gt $_best ]] && { _best=$_k; _modal=$_a; }
        done
        # A banner is only recognisable against a real consensus: most of the
        # block (>=65%) must share the modal count, or a wide first line is
        # just one more ragged row (samtools flagstat), not chrome.
        [[ $_best -lt 2 || $(( _best * 100 / _mn )) -lt 65 ]] && _modal=0
    fi

    # A section title — the FIRST line, ending with `:`, set off by a blank
    # line before the table ("Current machine states:", `vagrant status`) —
    # is chrome, not data. Identified by lookahead here, dropped in the loop.
    local _title="" _prev="" _seenfirst=0
    if [[ $has_table -eq 1 ]]; then
        local _fri231; for ((_fri231 = 0; _fri231 < ${#_FR_LINES[@]}; _fri231++)); do _l="${_FR_LINES[$_fri231]}"
            if [[ $_seenfirst -eq 0 ]]; then
                [[ "${_l}" != *[![:space:]]* ]] && continue
                _seenfirst=1; _prev="$_l"; continue
            fi
            [[ "${_l}" != *[![:space:]]* && "$_prev" =~ :[[:space:]]*$ ]] && _title="$_prev"
            # ...or directly above a >= 3-column (2+-space segment) header,
            # when the title itself is ONE segment (`Group "default" (2
            # parallel):` over pueue's `id  status  command  start`).
            if [[ -z "$_title" && "$_prev" =~ :[[:space:]]*$ ]]; then
                local _tt_ps _tt_hs
                _ac_seg_v "$_prev"; _tt_ps=$_AC_SEG
                _ac_seg_v "$_l"; _tt_hs=$_AC_SEG
                [[ $_tt_ps -eq 1 && $_tt_hs -ge 3 && "$_l" != *:[[:space:]]* ]] && _title="$_prev"
            fi
            # ...or a one-segment `Label: value` context line directly above
            # such a header (gluster's `Brick: node1:/bricks/brick1` over its
            # `%-latency  Avg-latency …` table) — a caption, not a row.
            if [[ -z "$_title" && "$_prev" =~ ^[A-Za-z][A-Za-z0-9_\ -]*:[[:space:]]+[^[:space:]]+[[:space:]]*$ ]]; then
                local _tt_ps2 _tt_hs2
                _ac_seg_v "$_prev"; _tt_ps2=$_AC_SEG
                _ac_seg_v "$_l"; _tt_hs2=$_AC_SEG
                [[ $_tt_ps2 -eq 1 && $_tt_hs2 -ge 3 && "$_l" != *:[[:space:]]* && "$_l" != *[0-9][[:space:]]* ]] && _title="$_prev"
            fi
            break
        done
    fi

    # A title banner in front of a FIXED-WIDTH table (STREAM's "STREAM version
    # 5.10", blender's "Blender 4.2.0 Benchmark", kdiskmark's "KDiskMark 3.1.4")
    # — a leading single-column line (seg<2) or decorated rule, followed by an
    # ALL-LABEL header over NUMERIC data. Both the all-label header and the
    # numeric data are required so this never eats a real header that happens to
    # be single-segment ("Installed Packages" over version rows — dnf-list) or a
    # word-data list ("web  running (virtualbox)" — vagrant).
    local _fwbanner=""
    if [[ $has_table -eq 1 ]]; then
        local _fl=() _fx
        local _fri251; for ((_fri251 = 0; _fri251 < ${#_FR_LINES[@]}; _fri251++)); do _fx="${_FR_LINES[$_fri251]}"
            [[ "${_fx}" != *[![:space:]]* ]] && continue
            [[ "$_fx" =~ ^[[:space:]]*[=-]+([[:space:]]+[=-]+)*[[:space:]]*$ ]] && continue
            _fl+=("$_fx"); [[ ${#_fl[@]} -ge 3 ]] && break
        done
        if [[ ${#_fl[@]} -ge 3 ]]; then
            local _b0="${_fl[0]}" _h1="${_fl[1]}" _d2="${_fl[2]}"
            local _b0seg; _ac_seg_v "$_b0"; _b0seg="$_AC_SEG"
            if [[ ( $_b0seg -lt 2 || "$_b0" == *-----* ) && ! "$_b0" =~ ^[[:space:]]*[{[\<] ]]; then
                # header all-label AND genuinely multi-COLUMN (>=2 two-space
                # segments)? A kv line ("Revision a1b2c3d4", "Author: Name") has
                # one segment and must never count as a fixed-width header.
                local _hlab=1 _ht; _ht=(); _fr_tok "$_h1"; _ht=("${_FR_TOK[@]}")
                [[ ${#_ht[@]} -ge 2 ]] || _hlab=0
                _ac_seg_v "$_h1"
                [[ "$_AC_SEG" -ge 2 ]] || _hlab=0
                # every header token must be a real label: contains a letter and
                # is not a value ("========================" in mpirun's decorated
                # "==== JOB MAP ====" row is neither).
                local _t
                for _t in "${_ht[@]}"; do
                    if _ac_is_value "$_t" || [[ ! "$_t" =~ [A-Za-z] ]]; then _hlab=0; break; fi
                done
                # data numeric?
                local _dnum=0 _dt; _dt=(); _fr_tok "$_d2"; _dt=("${_FR_TOK[@]}")
                for _t in "${_dt[@]}"; do _ac_is_value "$_t" && { _dnum=1; break; }; done
                # header and first data row must start at the SAME column — else
                # the header has no column for a data-row label ("Read (MB/s)"
                # indented over unindented "SEQ1M Q8T1 …" — kdiskmark's headerless
                # first column), which positional assignment can only garble.
                local _hind="${_h1%%[![:space:]]*}" _dind="${_d2%%[![:space:]]*}"
                [[ $_hlab -eq 1 && $_dnum -eq 1 && ${#_hind} -eq ${#_dind} ]] && _fwbanner="$_b0"
            fi
        fi
    fi

    # A leading `#`-comment block (conda list, opam list) mixes prose banners with
    # a commented column header. Collect the candidates and, at the first data
    # line, prefer the one whose token count matches the data row and whose
    # tokens are unique (nvidia-smi dmon's `# gpu sm mem …` over its units row
    # `# Idx % % …`); otherwise keep the last (conda's header is last).
    local held=() banner_budget=2
    # Kept lines accumulate in an ARRAY and are joined once at the end: a
    # per-line `out+=` re-copies the whole string each time (quadratic).
    local _outl=()
    # BIG block: once `started` is set, a line's only fate is the rule-drop
    # test below — so the loop stops there and ONE awk pass applies that test
    # to the rest (same lines kept, same order).
    # (Indexed, not `for _l in "${_FR_LINES[@]}"`: that expands the whole
    # array up front even when the loop stops early. The one _fr_lines call
    # inside — the banner check — passes this same text, so _FR_LINES stays.)
    local _acb_big=0 _acb_n _acb_i _acx_o="" _acb_tail="" _acb_owns=0
    (( ${#text} > _FR_BIG_BYTES )) && _acb_big=1
    _acb_n=${#_FR_LINES[@]}
    # COMMENTED FILE: a block that OPENS with a `#` line uses `#` for
    # comments, so an interior `# prose` line between rows (crontab's
    # `# every 15 minutes`, a routes dump's `# vpn tunnel`) is annotation,
    # not a row — dropped once the table has started. Only `# …` / a bare
    # `#` qualify: `##`/`###` section banners carry structure and stay.
    local _acb_cmt=0
    for ((_acb_i = 0; _acb_i < _acb_n; _acb_i++)); do
        _l="${_FR_LINES[$_acb_i]}"
        [[ "${_l}" != *[![:space:]]* ]] && continue
        [[ "$_l" == "#"* ]] && _acb_cmt=1
        break
    done
    for ((_acb_i = 0; _acb_i < _acb_n; _acb_i++)); do
        _l="${_FR_LINES[$_acb_i]}"
        [[ $_acb_big -eq 1 && $started -eq 1 ]] && break
        # Drop a pure separator rule up top so a LEADING rule (STREAM /
        # pytest-benchmark bracket their header in rules) doesn't flip `started`
        # and get mistaken for the first table line.
        [[ "$_l" =~ ^[[:space:]]*[=-]+([[:space:]]+[=-]+)*[[:space:]]*$ ]] && continue
        [[ $started -eq 1 && $_acb_cmt -eq 1 && ( "$_l" == "# "* || "$_l" == "#" ) ]] && continue
        if [[ $started -eq 0 && "${_l}" == *[![:space:]]* ]]; then
            _fr_tok "$_l"; _tk=("${_FR_TOK[@]}")
            [[ "$_l" =~ ^[[:space:]]*total[[:space:]]+[0-9]+[[:space:]]*$ ]] && continue
            [[ -n "$_fwbanner" && "$_l" == "$_fwbanner" ]] && { _fwbanner=""; continue; }
            [[ -n "$_title" && "$_l" == "$_title" ]] && { _title=""; continue; }
            if [[ "$_l" =~ ^[[:space:]]*# ]]; then
                # Strip the leading `#` (and one following space) — a candidate header.
                local _h="${_l#"${_l%%[!#[:space:]]*}"}"
                [[ "${_h}" == *[![:space:]]* ]] && held+=("$_h")
                continue
            fi
            # A short word-like preamble line (e.g. `apt list`'s "Listing…") before
            # a real table — but NOT a `{`/`[`/`<` structural line (JSON/XML), which
            # must keep aligned-columns from matching those formats.
            [[ $has_table -eq 1 && ${#_tk[@]} -lt 2 && "$_l" =~ ^[[:space:]]*[A-Za-z] ]] && continue
            # A leading progress line — any token ending in an ellipsis
            # ("Listing... Done") — is chrome before the table, not data.
            [[ $has_table -eq 1 && "$_l" =~ \.\.\.([[:space:]]|$) && ${#_tk[@]} -le 3 ]] && continue
            # A leading banner line much WIDER than the table (>=3 tokens over
            # the modal count): drop it (max 2 such lines). Chrome carries
            # numbers (`w`'s uptime/load line, numastat's PID title), so the
            # line must hold a VALUE token — a wide all-label header row
            # (kubectl get pv) never does. Chrome is also not: a `label :
            # value` line (in `chage -l` a wide pair is data), a line ending
            # in a period (prose data — poetry's root-package row), or a line
            # OPENING WITH THE SAME TOKEN as a table row (telegraf's log
            # stream — same-shaped lines are the table itself).
            if [[ $banner_budget -gt 0 && $_modal -ge 2 && ${#_tk[@]} -ge $((_modal + 3)) \
                  && "$_l" =~ ^[[:space:]]*[A-Za-z0-9] && ! "$_l" =~ \.[[:space:]]*$ \
                  && ! "$_l" =~ ^[[:space:]]*[A-Za-z][^:=]*:[[:space:]] ]]; then
                local _bt _bv=0 _bsame=0 _bl2 _bt2
                for _bt in "${_tk[@]}"; do
                    [[ "$_bt" =~ ^[0-9]+([.,][0-9]+)*[a-zA-Z%]*$ || "$_bt" =~ ^[0-9]{1,2}:[0-9]{2} \
                       || "$_bt" =~ ^[0-9]+\.[0-9]+\.[0-9]+\. || "$_bt" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2} ]] && { _bv=1; break; }
                done
                if [[ $_bv -eq 1 ]]; then
                    _fr_lines "$text"
                    local _fri349; for ((_fri349 = 0; _fri349 < ${#_FR_LINES[@]}; _fri349++)); do _bl2="${_FR_LINES[$_fri349]}"
                        [[ "${_bl2}" != *[![:space:]]* || "$_bl2" == "$_l" ]] && continue
                        _fr_tok "$_bl2"; _bt2=("${_FR_TOK[@]}")
                        [[ "${_bt2[0]:-}" == "${_tk[0]}" ]] && { _bsame=1; break; }
                    done
                    if [[ $_bsame -eq 0 ]]; then
                        banner_budget=$((banner_budget - 1))
                        continue
                    fi
                fi
            fi
            # First real line: emit the best held commented header (if any) —
            # but only a candidate whose token count fits the data (exact, or
            # one under for a trailing multi-word label). A lone `# <path>`
            # provenance comment (ansible-galaxy) fits nothing and is dropped.
            # The first real line is ITSELF a label header (>= 3 tokens, every
            # token carries a letter and none is a `label:`, no digit anywhere) — then a held `# …`
            # line is a provenance/prose banner (`# generated by mkroutes
            # 2026-07-11`, `# repo index (mirror sync)`), not the header.
            local _fhdr=0
            if [[ ${#held[@]} -gt 0 && ${#_tk[@]} -ge 3 && "$_l" != *[0-9]* ]]; then
                _fhdr=1
                local _ft
                for _ft in "${_tk[@]}"; do [[ "$_ft" =~ [A-Za-z] && "$_ft" != *: ]] || { _fhdr=0; break; }; done
            fi
            if [[ ${#held[@]} -gt 0 && $_fhdr -eq 0 ]]; then
                local _pick="" _c _ct _u _t2
                for _c in "${held[@]}"; do
                    _fr_tok "$_c"; _ct=("${_FR_TOK[@]}")
                    [[ ${#_ct[@]} -ne ${#_tk[@]} ]] && continue
                    _u=1; local -A _seen_tok=()
                    for _t2 in "${_ct[@]}"; do [[ -n "${_seen_tok[$_t2]:-}" ]] && { _u=0; break; }; _seen_tok[$_t2]=1; done
                    [[ $_u -eq 1 ]] && { _pick="$_c"; break; }
                done
                # No exact fit among SEVERAL candidates: the header is the
                # widest one that still fits the row (a trailing multi-word
                # cell — crontab's command — makes the row wider), not the
                # last prose comment (`# m h dom mon dow command` over
                # `# backup nightly`). Ties go to the later line.
                if [[ -z "$_pick" && ${#held[@]} -ge 2 ]]; then
                    local _pw=0
                    local _plab _pt
                    for _c in "${held[@]}"; do
                        _fr_tok "$_c"
                        # (label words only: `m h dom mon dow command`, never
                        # prose like `Running 'sched/messaging' benchmark:`)
                        _plab=1
                        for _pt in "${_FR_TOK[@]}"; do
                            [[ "$_pt" =~ ^[A-Za-z][A-Za-z0-9_%/-]*$ ]] || { _plab=0; break; }
                        done
                        [[ $_plab -eq 1 && ${#_FR_TOK[@]} -le ${#_tk[@]} && ${#_FR_TOK[@]} -ge 3 && ${#_FR_TOK[@]} -ge $_pw ]] \
                            && { _pw=${#_FR_TOK[@]}; _pick="$_c"; }
                    done
                fi
                [[ -z "$_pick" ]] && _pick="${held[${#held[@]}-1]}"
                [[ -n "$_pick" ]] && _outl+=("$_pick")
            fi
            started=1
        fi
        _outl+=("$_l")
    done
    if [[ $_acb_big -eq 1 && $_acb_i -lt $_acb_n ]]; then
        # the rest of the lines (index _acb_i on), rule-dropped, as a string
        # of newline-terminated lines — and the trailing-summary-line drop
        # below, decided here when the rest keeps any line (its last kept
        # line is then the block's last line)
        local _acb_prenb=0 _acb_pl _acb_predig=0
        for _acb_pl in "${_outl[@]}"; do
            [[ "$_acb_pl" == *[![:space:]]* ]] && _acb_prenb=$((_acb_prenb + 1))
            [[ "$_acb_pl" =~ ^[[:space:]]*[0-9] ]] && _acb_predig=1
        done
        _acb_tail="$(cat <<< "$text" | awk -v k="$_acb_i" -v pre="${#_outl[@]}" -v prenb="$_acb_prenb" -v predig="$_acb_predig" -v cm="$_acb_cmt" '
            NR <= k { next }
            cm == 1 && (substr($0, 1, 2) == "# " || $0 == "#") { next }
            /^[ \t\n\v\f\r]*[=-]+([ \t\n\v\f\r]+[=-]+)*[ \t\n\v\f\r]*$/ { next }
            { if (have) { print held; if (held ~ /^[ \t\n\v\f\r]*[0-9]/) predig = 1 }
              held = $0; have = 1; nk++; if ($0 ~ /[^ \t\n\v\f\r]/) nb++ }
            END {
                # last byte: 1 when this pass kept a line (it owns the drop), else 0
                if (!have) { printf "0"; exit }
                drop = 0
                if (pre + nk >= 2 && held ~ /^[ \t\n\v\f\r]*[0-9]+[ \t\n\v\f\r]+([A-Za-z]+[ \t\n\v\f\r]+)*(listed|shown|found)\.?[ \t\n\v\f\r]*$/) drop = 1
                # a COUNT footer: `3 requests, 3 succeeded` whose leading
                # number is the row count above it (with or without header)
                if (!drop && !predig && held ~ /^[ \t]*[0-9]+[ \t]+[A-Za-z]/) {
                    t = held; sub(/^[ \t]+/, "", t); nt = split(t, tk, /[ \t]+/)
                    c = tk[1] + 0; tot = prenb + nb
                    if (nt <= 6 && c >= 2 && (c == tot - 1 || c == tot - 2)) drop = 1
                }
                if (!drop) print held
                printf "1"
            }')"
        _acb_owns="${_acb_tail: -1}"
        _acb_tail="${_acb_tail%?}"
    fi

    # Drop a trailing summary line like "4 sessions listed." / "5 loaded units
    # listed." so it isn't counted as a data row. (`body` is the kept lines
    # newline-joined, so its last line is the last kept line and "body has a
    # newline" is "more than one kept line" — read off the array rather than
    # rescanning the joined string.)
    local _acb_k=${#_outl[@]} last=""
    [[ $_acb_k -gt 0 ]] && last="${_outl[$((_acb_k - 1))]}"
    if [[ $_acb_owns -ne 1 && $_acb_k -ge 2 \
          && "$last" =~ ^[[:space:]]*[0-9]+[[:space:]]+([A-Za-z]+[[:space:]]+)*(listed|shown|found)\.?[[:space:]]*$ ]]; then
        unset '_outl[$((_acb_k - 1))]'
    elif [[ $_acb_owns -ne 1 && $_acb_k -ge 2 && "$last" =~ ^[[:space:]]*([0-9]+)[[:space:]]+[A-Za-z] ]]; then
        # A COUNT footer (`3 requests, 3 succeeded`): its leading number is
        # the row count above it (headerless, or under one header row).
        # Only when no OTHER row opens with a digit — a numbered/ID column
        # (`4  snowflake_dwh …`) is data, not a count footer.
        local _cf_c="${BASH_REMATCH[1]}" _cf_nb=0 _cf_l _cf_dig=0 _cf_j
        _fr_tok "$last"
        for ((_cf_j = 0; _cf_j < _acb_k - 1; _cf_j++)); do
            [[ "${_outl[$_cf_j]}" =~ ^[[:space:]]*[0-9] ]] && { _cf_dig=1; break; }
        done
        if [[ $_cf_dig -eq 0 && ${#_FR_TOK[@]} -le 6 && ${#_cf_c} -le 9 ]]; then
            for _cf_l in "${_outl[@]}"; do [[ "$_cf_l" == *[![:space:]]* ]] && _cf_nb=$((_cf_nb + 1)); done
            _cf_c=$((10#$_cf_c))
            if [[ $_cf_c -ge 2 && ( $_cf_c -eq $((_cf_nb - 1)) || $_cf_c -eq $((_cf_nb - 2)) ) ]]; then
                unset '_outl[$((_acb_k - 1))]'
            fi
        fi
    fi
    [[ ${#_outl[@]} -gt 0 ]] && printf -v out '%s\n' "${_outl[@]}"
    out+="$_acb_tail"
    _AC_BODY_RAW="$out"
}

# _ac_tok_spans LINE — byte start / end (exclusive) of each whitespace token
# into _AC_TS / _AC_TE.
_ac_tok_spans () {
    local l="$1" i n=${#1} in=0 c
    _AC_TS=(); _AC_TE=()
    for ((i = 0; i < n; i++)); do
        c="${l:i:1}"
        if [[ "$c" == [[:space:]] ]]; then
            [[ $in -eq 1 ]] && { _AC_TE+=("$i"); in=0; }
        elif [[ $in -eq 0 ]]; then
            _AC_TS+=("$i"); in=1
        fi
    done
    [[ $in -eq 1 ]] && _AC_TE+=("$n")
}

# _ac_sparse_grid TEXT — 0 when TEXT (header + rows) is a SPARSE grid: row 1
# is >= 3 labels each set off by 2+ spaces; every later row (<= 40 checked,
# >= 2 of them) opens at the header's first column and places each further
# token under a DISTINCT later header label (starting inside that label's
# column region — at or after its start, at most one byte past its end), left
# to right; and at least one row leaves a label empty. Missing cells are what make it ragged — the grid is still exact.
_ac_sparse_grid () {
    local _sg_l _sg_i=0 _sg_hs=() _sg_he=() _sg_short=0 _sg_rows=0 _j _k _t _sg_all=()
    # (its own split: callers keep _FR_LINES)
    mapfile -t _sg_all <<< "$1"
    for _sg_l in "${_sg_all[@]}"; do
        [[ "${_sg_l}" != *[![:space:]]* ]] && continue
        _sg_i=$((_sg_i + 1))
        _ac_tok_spans "$_sg_l"
        if [[ $_sg_i -eq 1 ]]; then
            _sg_hs=("${_AC_TS[@]}"); _sg_he=("${_AC_TE[@]}")
            _ac_seg_v "$_sg_l"
            [[ $_AC_SEG -eq ${#_sg_hs[@]} && ${#_sg_hs[@]} -ge 3 ]] || return 1
            continue
        fi
        [[ ${#_AC_TS[@]} -ge 1 && ${#_AC_TS[@]} -le ${#_sg_hs[@]} ]] || return 1
        [[ ${_AC_TS[0]} -eq ${_sg_hs[0]} ]] || return 1
        _k=1
        for ((_j = 1; _j < ${#_AC_TS[@]}; _j++)); do
            _t=${_AC_TS[$_j]}
            # the token must clear the previous column's label
            while [[ $_k -lt ${#_sg_hs[@]} ]] && (( _t > ${_sg_he[$_k]} )); do _k=$((_k + 1)); done
            [[ $_k -lt ${#_sg_hs[@]} ]] || return 1
            (( _t >= ${_sg_hs[$_k]} )) || return 1
            _k=$((_k + 1))
        done
        [[ ${#_AC_TS[@]} -lt ${#_sg_hs[@]} ]] && _sg_short=1
        _sg_rows=$((_sg_rows + 1))
        [[ $_sg_i -ge 41 ]] && break
    done
    [[ $_sg_rows -ge 2 && $_sg_short -eq 1 ]]
}

# Analyse a block as a whitespace-columnar table. Prints "<mode> <ncols>":
#   HDR  n — first non-blank line is a label header (n columns)
#   HDR2 n — two-line header (group row + field row); field row has n columns
#   HL   n — headerless table (synthesise c1..cN); n = modal column count
# Prints nothing (returns 1) if the block isn't a consistent columnar table.
#
# Header vs headerless: a header row is labels; data rows carry more pure-numeric
# tokens (counts, sizes, percentages) than the header. So the block has a header
# when row 2 has more pure-numeric tokens than row 1 — this correctly treats
# `df -T` (whose header label `1K-blocks` merely contains a digit) as having a
# header, while `who`/`mount` (no numeric columns) stay headerless. Headerless
# needs >=3 consistent columns so it can't swallow 2-column key/value input.
_ac_shape () {
    _ac_shape_v "$1" || return 1
    printf '%s\n' "$_AC_SHAPE"
}

# _ac_shape_v TEXT — _ac_shape's verdict in the global _AC_SHAPE ("<mode> <n>")
# with the same return status; no fork. A pure function of TEXT, memoised so
# detect and extract (same input) analyse the block once.
# (Two slots, as _ac_body_v.)
: "${_AC_SHAPE_KEY=}" "${_AC_SHAPE_SLK:=0}" "${_AC_SHAPE_OK:=0}" "${_AC_SHAPE_RC:=1}" "${_AC_SHAPE_MEMO=}"
: "${_AC_SHAPE_KEY2=}" "${_AC_SHAPE_SLK2:=0}" "${_AC_SHAPE_OK2:=0}" "${_AC_SHAPE_RC2:=1}" "${_AC_SHAPE_MEMO2=}"
_ac_shape_v () {
    _AC_SHAPE_FRESH=0
    if [[ $_AC_SHAPE_OK -eq 1 && "${_FR_SLACK:-0}" == "$_AC_SHAPE_SLK" ]] \
       && (( ${#1} == ${#_AC_SHAPE_KEY} )) && [[ "$1" == "$_AC_SHAPE_KEY" ]]; then
        _AC_SHAPE="$_AC_SHAPE_MEMO"
        return $_AC_SHAPE_RC
    fi
    if [[ $_AC_SHAPE_OK2 -eq 1 && "${_FR_SLACK:-0}" == "$_AC_SHAPE_SLK2" ]] \
       && (( ${#1} == ${#_AC_SHAPE_KEY2} )) && [[ "$1" == "$_AC_SHAPE_KEY2" ]]; then
        _AC_SHAPE="$_AC_SHAPE_MEMO2"
        return $_AC_SHAPE_RC2
    fi
    if [[ $_AC_SHAPE_OK -eq 1 ]]; then
        _AC_SHAPE_KEY2="$_AC_SHAPE_KEY"; _AC_SHAPE_SLK2="$_AC_SHAPE_SLK"
        _AC_SHAPE_RC2=$_AC_SHAPE_RC; _AC_SHAPE_MEMO2="$_AC_SHAPE_MEMO"; _AC_SHAPE_OK2=1
    fi
    _AC_SHAPE_OUT=""
    local _rc=0
    # (computed here: _AC_BODY is TEXT's body and _FR_LINES its lines on
    # return — _ac_detect relies on that instead of re-checking both memos)
    _AC_SHAPE_FRESH=1
    _ac_shape_compute "$1" || _rc=$?
    [[ $_rc -ne 0 ]] && _AC_SHAPE_OUT=""
    _AC_SHAPE="$_AC_SHAPE_OUT"
    _AC_SHAPE_MEMO="$_AC_SHAPE_OUT"
    _AC_SHAPE_RC=$_rc
    _AC_SHAPE_KEY="$1"
    _AC_SHAPE_SLK="${_FR_SLACK:-0}"   # (a sample screen's verdict is its own)
    _AC_SHAPE_OK=1
    return $_rc
}

# The _ac_shape analysis proper: sets _AC_SHAPE_OUT and returns 0, or
# returns 1 (not a columnar table).
_ac_shape_compute () {
    local text; _ac_body_v "$1"; text="$_AC_BODY"
    local counts=() dcount=() idx=0 _line first_line=""
    # Track whether this block is dominantly a single-record COLON-KV
    # description (dpkg/apt `Package: foo` / `Status: install ok installed` /
    # `Header: family inet …`) rather than a real table — one field per line,
    # each field a DISTINCT label. That shape belongs to `colons`
    # (priority 60), which already renders it as one clean wide record; if
    # aligned-columns claims it first, row 1's two tokens ("Package:", "vim")
    # become literal COLUMN NAMES and every later field gets stuffed under
    # them, producing garbage. Declining here lets colons pick it up.
    local _kv_lines=0 _kv_dupe=0 _kvm_lines=0 _kvm_dupe=0
    local _kvm_tpl="" _kvm_tpl_same=1
    local -A _kv_seen=() _kvm_seen=()
    local _kvm_re='^[[:space:]]*([A-Za-z][A-Za-z0-9_()-]*([ ][A-Za-z0-9_()-]+)+):([[:space:]]|$)'
    # _FR_LINES now holds the lines of `text` for the rest of this function
    # (nothing below splits another text), so the later `_fr_lines "$text"`
    # calls are skipped: each was a memo hit, but the hit compares the whole
    # text (~0.3 s on 10 MB, seven times).
    _fr_lines "$text"; local _acs_fl=1
    local _fri473; for ((_fri473 = 0; _fri473 < ${#_FR_LINES[@]}; _fri473++)); do _line="${_FR_LINES[$_fri473]}"
        [[ "${_line}" != *[![:space:]]* ]] && continue
        idx=$((idx + 1))
        [[ $idx -eq 1 ]] && first_line="$_line"
        local _tk; _tk=(); _fr_tok "$_line"; _tk=("${_FR_TOK[@]}")
        counts+=("${#_tk[@]}")
        local d=0 t
        for t in "${_tk[@]}"; do [[ "$t" =~ [0-9] ]] && d=$((d + 1)); done
        dcount+=("$d")
        if [[ "${_tk[0]:-}" =~ ^[A-Za-z][A-Za-z0-9_-]*:$ ]]; then
            _kv_lines=$((_kv_lines + 1))
            local _lab="${_tk[0]%:}"
            [[ -n "${_kv_seen[$_lab]:-}" ]] && _kv_dupe=1
            _kv_seen[$_lab]=1
        fi
        # MULTI-WORD colon labels ("Total package names: 88201 (1,764 k)"):
        # single-space tokenization shreds these, so they must go to `colons`.
        # Track the label's digit-TEMPLATE too (digits collapsed to #): when
        # every label is the SAME template ("Bus ### Device ###" — lsusb),
        # the "labels" are really table rows and the veto must not fire.
        if [[ "$_line" =~ $_kvm_re ]]; then
            _kvm_lines=$((_kvm_lines + 1))
            local _mlab="${BASH_REMATCH[1]}"
            [[ -n "${_kvm_seen[$_mlab]:-}" ]] && _kvm_dupe=1
            _kvm_seen[$_mlab]=1
            local _mtpl="${_mlab//[0-9]/#}"
            while [[ "$_mtpl" == *"##"* ]]; do _mtpl="${_mtpl//##/#}"; done
            if [[ -z "$_kvm_tpl" ]]; then _kvm_tpl="$_mtpl"
            elif [[ "$_mtpl" != "$_kvm_tpl" ]]; then _kvm_tpl_same=0
            fi
        fi
        [[ $idx -ge 40 ]] && break
    done
    # Also require ROW 1 ITSELF to be a colon-kv label line. Without this, a
    # real table whose first COLUMN happens to be colon-suffixed labels
    # (/proc/interrupts-style `HI:  TIMER:  NET_TX:  …` per-row counter names
    # under a `CPU0 CPU1 CPU2 CPU3` header) satisfies "distinct label per
    # line, majority of rows" just as well as a genuine kv description does —
    # but there row 1 is the real header (no colon), not a field, so it fails
    # this check and the table stays with aligned-columns where it belongs.
    local _first_tok="${first_line%%[[:space:]]*}"
    if [[ $idx -ge 8 && $_kv_dupe -eq 0 && $((_kv_lines * 2)) -ge $idx \
          && "$_first_tok" =~ ^[A-Za-z][A-Za-z0-9_-]*:$ ]]; then
        return 1
    fi
    # EVERY line a distinct multi-word colon label => a colon-kv description
    # ("Total package names: …"), never a table. The multi-word requirement
    # keeps single-token label columns (/proc/interrupts' `HI:`) out of this
    # veto — those stay with the row-1-label check above. Labels that all
    # share one digit-template ("Bus ### Device ###" — lsusb) are table rows
    # wearing colons, not field names: the veto stands down.
    if [[ $idx -ge 3 && $_kvm_dupe -eq 0 && $_kvm_lines -eq $idx \
          && ! ( $_kvm_tpl_same -eq 1 && "$_kvm_tpl" == *"#"* ) ]]; then
        return 1
    fi
    # MIXED-label colon-kv block. The two vetoes above each have a blind spot
    # the reviewer hit three times in one round: single- and multi-word labels
    # MIXED in one block (`Queue running: 1` + `VRAM: 8201/24564 MiB` —
    # comfyui), blocks SHORTER than 3 multi-word lines (cups-lpstat's two
    # `device for X: uri` lines), and a same-template run broken by one odd
    # label (e2fsck's `Pass N:` ×4 + `/dev/sda2:` — the lsusb exemption stood
    # down on the Pass template alone). This veto takes the union: EVERY line
    # is `label: value` (label single-spaced — no 2+-space run, so a table
    # cell before a later colon never counts — and colon-free), labels are
    # DISTINCT, at least one label holds a space or `/` (pure single-token
    # label columns still belong to the row-1 check), and the labels do NOT
    # all share one digit template (lsusb again). Such a block is `colons`'
    # territory: one field per line, split at the first colon.
    local _mixed_ok=1 _mixed_multi=0 _mx_line _mx_tpl="" _mx_tpl_same=1 _mx_colons=0 _mx_n=0
    local -A _mx_seen=()
    if [[ $idx -ge 2 ]]; then
        [[ $_acs_fl -eq 1 ]] || _fr_lines "$text"
        local _fri545; for ((_fri545 = 0; _fri545 < ${#_FR_LINES[@]}; _fri545++)); do _mx_line="${_FR_LINES[$_fri545]}"
            [[ "${_mx_line}" != *[![:space:]]* ]] && continue
            if [[ ! "$_mx_line" =~ ^[[:space:]]*([^:]+):[[:space:]]+[^[:space:]] ]]; then
                _mixed_ok=0; break
            fi
            local _mxl="${BASH_REMATCH[1]}"
            _mxl="${_mxl#"${_mxl%%[![:space:]]*}"}"
            _mxl="${_mxl%"${_mxl##*[![:space:]]}"}"
            [[ "$_mxl" == *"  "* || -z "$_mxl" ]] && { _mixed_ok=0; break; }
            # A possessive/prose label (`pid 3421's current scheduling
            # policy`) is a sentence wearing a colon, not a field name —
            # chrt/taskset keep their aligned parse.
            [[ "$_mxl" == *"'"* ]] && { _mixed_ok=0; break; }
            [[ -n "${_mx_seen[$_mxl]:-}" ]] && { _mixed_ok=0; break; }
            _mx_seen[$_mxl]=1
            [[ "$_mxl" == *" "* || "$_mxl" == */* ]] && _mixed_multi=1
            _mx_n=$((_mx_n + 1))
            [[ "$_mxl" =~ ^[A-Za-z][A-Za-z0-9_\ -]*$ ]] && _mx_colons=$((_mx_colons + 1))
            local _mxt="${_mxl//[0-9]/#}"
            while [[ "$_mxt" == *"##"* ]]; do _mxt="${_mxt//##/#}"; done
            if [[ -z "$_mx_tpl" ]]; then _mx_tpl="$_mxt"
            elif [[ "$_mxt" != "$_mx_tpl" ]]; then _mx_tpl_same=0
            fi
        done
        # Only defer when `colons` will actually ACCEPT the block (>=40% of
        # labels letter-led simple charset) — else no parser takes it at all.
        if [[ $_mixed_ok -eq 1 && $_mixed_multi -eq 1 && $_mx_n -ge 1 \
              && $(( _mx_colons * 100 / _mx_n )) -ge $(( 40 + ${_FR_SLACK:-0} )) \
              && ! ( $_mx_tpl_same -eq 1 && "$_mx_tpl" == *"#"* ) ]]; then
            return 1
        fi
    fi

    local nlines=${#counts[@]}
    [[ $nlines -lt 2 ]] && return 1
    [[ ${counts[0]} -lt 2 ]] && return 1

    # Two-line header: rows 1-2 are label rows (no digit tokens), the field row has
    # more columns, and numeric data starts on row 3 — vmstat, some sar layouts.
    if [[ $nlines -ge 3 && ${dcount[0]} -eq 0 && ${dcount[1]} -eq 0 \
          && ${dcount[2]} -gt 0 && ${counts[1]} -gt ${counts[0]} ]]; then
        # ...unless rows 1 and 2 share >= 2 distinct words: two records of
        # one shape (`+ aws_instance.web will be created` / `~ … will be
        # updated`) are not a group row over a field row.
        local _r3v=1 _r3t _r3l2="" _r3i=0 _r3n=0
        local -A _r3seen=() _r3cnt=()
        _fr_lines "$text"
        for _r3t in "${_FR_LINES[@]}"; do
            [[ "${_r3t}" != *[![:space:]]* ]] && continue
            _r3i=$((_r3i + 1)); [[ $_r3i -eq 2 ]] && { _r3l2="$_r3t"; break; }
        done
        _fr_tok "$_r3l2"
        for _r3t in "${_FR_TOK[@]}"; do _r3seen[$_r3t]=1; done
        _fr_tok "$first_line"
        for _r3t in "${_FR_TOK[@]}"; do
            [[ "$_r3t" =~ ^[A-Za-z]{2,}$ && -n "${_r3seen[$_r3t]:-}" && -z "${_r3cnt[$_r3t]:-}" ]] \
                && { _r3cnt[$_r3t]=1; _r3n=$((_r3n + 1)); }
        done
        [[ $_r3n -ge 2 ]] && _r3v=0
        if [[ $_r3v -eq 1 ]]; then
            _AC_SHAPE_OUT="HDR2 ${counts[1]}"
            return 0
        fi
    fi
    # Same shape, but the FIELD row's labels carry digits (`p50`, `BW(MB/s)`,
    # `Lat(ms)` — benchmark/spanning-group tables). A digit alone can't demote
    # it: the discriminator is VALUE-shaped tokens (a bare number/time/IP/date).
    # Row 2 must have none while row 3 has at least one.
    if [[ $nlines -ge 3 && ${dcount[0]} -eq 0 && ${dcount[1]} -gt 0 \
          && ${dcount[2]} -gt 0 && ${counts[1]} -gt ${counts[0]} ]]; then
        local _h2v=0 _h3v=0 _h2t _h2i=0 _h2l="" _h3l=""
        [[ $_acs_fl -eq 1 ]] || _fr_lines "$text"
        local _fri597; for ((_fri597 = 0; _fri597 < ${#_FR_LINES[@]}; _fri597++)); do _h2t="${_FR_LINES[$_fri597]}"
            [[ "${_h2t}" != *[![:space:]]* ]] && continue
            _h2i=$((_h2i + 1))
            [[ $_h2i -eq 2 ]] && _h2l="$_h2t"
            [[ $_h2i -eq 3 ]] && { _h3l="$_h2t"; break; }
        done
        local _h2arr=(); _fr_tok "$_h2l"; _h2arr=("${_FR_TOK[@]}")
        for _h2t in "${_h2arr[@]}"; do
            [[ "$_h2t" =~ ^[0-9]+([.,][0-9]+)*[a-zA-Z%]*$ || "$_h2t" =~ ^[0-9]{1,2}:[0-9]{2} \
               || "$_h2t" =~ ^[0-9]+\.[0-9]+\.[0-9]+\. || "$_h2t" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2} ]] && _h2v=$((_h2v + 1))
        done
        local _h3arr=(); _fr_tok "$_h3l"; _h3arr=("${_FR_TOK[@]}")
        for _h2t in "${_h3arr[@]}"; do
            [[ "$_h2t" =~ ^[0-9]+([.,][0-9]+)*[a-zA-Z%]*$ || "$_h2t" =~ ^[0-9]{1,2}:[0-9]{2} \
               || "$_h2t" =~ ^[0-9]+\.[0-9]+\.[0-9]+\. || "$_h2t" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2} ]] && _h3v=$((_h3v + 1))
        done
        # Containment: row 1 must be a real GROUP-LABEL row — every token
        # alphanumeric-bearing (a `==== test session starts ====` banner fails
        # on its `====`), and row 2 a real FIELD row — no lone-punctuation
        # tokens (an ` X : Y   Z : W ` kv line fails on its bare `:`).
        local _h1ok=1 _h1arr=()
        _fr_tok "$first_line"; _h1arr=("${_FR_TOK[@]}")
        for _h2t in "${_h1arr[@]}"; do
            [[ "$_h2t" =~ [A-Za-z0-9] ]] || { _h1ok=0; break; }
        done
        local _h2ok=1
        for _h2t in "${_h2arr[@]}"; do
            [[ "$_h2t" =~ ^[\|#/%+:=-]+$ ]] && { _h2ok=0; break; }
        done
        if [[ $_h1ok -eq 1 && $_h2ok -eq 1 && $_h2v -eq 0 && $_h3v -ge 1 ]]; then
            _AC_SHAPE_OUT="HDR2 ${counts[1]}"
            return 0
        fi
    fi

    # Header detection. Row 1 is a label header when either:
    #   (a) it is an ALL-CAPS label row (systemctl/kubectl/ps — all-text tables), or
    #   (b) it contains no *value* token (a bare number, time, IP or date) while the
    #       data rows are more numeric than it. This treats df-T (header label
    #       `1K-blocks` is not a value) and free-h (unit values `7.8Gi`) as headed,
    #       but keeps log/record blocks headerless (who, mount, ip route, journalctl,
    #       last — whose first line already carries times/IPs/counts).
    # ALL-CAPS needs a letter: a purely numeric first row (`redis-cli --latency
    # -history`'s "1751880000 2") has no lowercase but is data, not a header.
    local caps0=0; [[ ! "$first_line" =~ [a-z] && "$first_line" =~ [A-Z] ]] && caps0=1
    local v0=0 _t _t1arr; _t1arr=(); _fr_tok "$first_line"; _t1arr=("${_FR_TOK[@]}")
    for _t in "${_t1arr[@]}"; do
        # value token = a number, optionally with a trailing unit (8.421s, 942ms,
        # 7.8Gi, 39%), or a time / IP / date. `1K-blocks` is NOT one (the hyphen),
        # so a df-T-style header label stays a header.
        [[ "$_t" =~ ^[0-9]+([.,][0-9]+)*[a-zA-Z%]*$ || "$_t" =~ ^[0-9]{1,2}:[0-9]{2} \
           || "$_t" =~ ^[0-9]+\.[0-9]+\.[0-9]+\. || "$_t" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2} ]] && v0=$((v0 + 1))
    done
    # Row 1 is a header when it is a pure label row (zero digit tokens) over
    # data that carries digits anywhere (az/aws listings — one digit-bearing
    # row is enough); when it is digit-free of VALUE tokens while most data
    # rows carry one (a number, time, IP or date — `multipass list`, whose
    # header label IPv4 merely contains a digit); or — when row 1 itself has
    # digit tokens (`1K-blocks`) — when MOST data rows are more numeric than
    # it. The majority requirements stop a headerless log (`git log
    # --oneline`) from having its first commit promoted just because one
    # later row carries an extra digit token (CVE-2026-1101).
    local moren=0 maxd=0 vrows=0 i
    local _dl _dt _dtk
    i=0
    # (the block text IS $(_ac_body "$1"), so its lines are _fr_lines "$text")
    [[ $_acs_fl -eq 1 ]] || _fr_lines "$text"
    local _fri664; for ((_fri664 = 0; _fri664 < ${#_FR_LINES[@]}; _fri664++)); do _dl="${_FR_LINES[$_fri664]}"
        [[ "${_dl}" != *[![:space:]]* ]] && continue
        i=$((i + 1))
        [[ $i -eq 1 ]] && continue
        _fr_tok "$_dl"; _dtk=("${_FR_TOK[@]}")
        for _dt in "${_dtk[@]}"; do
            # (a ledger amount counts too: `(1,200.00)` / `-850.25`)
            if [[ "$_dt" =~ ^[0-9]+([.,][0-9]+)*[a-zA-Z%]*$ || "$_dt" =~ ^[0-9]{1,2}:[0-9]{2} \
                 || "$_dt" =~ ^[0-9]+\.[0-9]+\.[0-9]+\. || "$_dt" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2} \
                 || "$_dt" =~ ^\([0-9]{1,3}(,[0-9]{3})*(\.[0-9]+)?\)$ ]]; then
                vrows=$((vrows + 1)); break
            fi
        done
        [[ $i -ge 40 ]] && break
    done
    for ((i = 1; i < nlines; i++)); do
        [[ ${dcount[$i]} -gt ${dcount[0]} ]] && moren=$((moren + 1))
        [[ ${dcount[$i]} -gt $maxd ]] && maxd=${dcount[$i]}
    done
    # All promotion paths also demand the row LOOKS like labels: every token
    # carries an alphanumeric (not `----`), none is bracketed (`[Hardware`,
    # `event]` — perf-list data), and none ends in `.` (prose — "…sysfs.").
    # Header labels with `:`/`(`/`#`/`%` (ss's Address:Port, vgs's #PV,
    # kubectl's CPU(cores)) all pass.
    # Bare single-char separators inside a header (`database | user`,
    # `# reqs`, `Total / Used`) are skipped — they are layout, not content.
    # A CJK/hangul header row (名前 年齢 都市) has no [A-Za-z0-9] anywhere, so it
    # could never pass the labelly check. Accept fully-non-ASCII tokens as labels
    # — but ONLY when EVERY non-separator token in the row is fully non-ASCII (a
    # pure CJK label row). A mixed row (⚡️ User toolchain:, + pod › nginx,
    # docker · list …) is a decorated log/record line, not a header.
    local _row_cjk=1
    for _t in "${_t1arr[@]}"; do
        [[ "$_t" =~ ^[\|#/%+-]$ ]] && continue
        [[ "$_t" == *[[:ascii:]]* ]] && { _row_cjk=0; break; }
    done
    # sysstat convention: sar prints the interval TIMESTAMP as the first header
    # token (`07:00:01  CPU  %user %nice …`), which counts as a value token and
    # would veto promotion. Forgive exactly that: row 1's ONLY value-shaped
    # token is a leading bare clock time AND the remaining tokens look like
    # sysstat column labels (at least half are %-prefixed or ALL-CAPS) — a log
    # line that merely starts with a time (`07:00:01 app started`) has
    # lowercase words and stays headerless.
    if [[ $v0 -eq 1 && ${#_t1arr[@]} -ge 4 \
          && "${_t1arr[0]}" =~ ^[0-9]{1,2}:[0-9]{2}(:[0-9]{2})?$ ]]; then
        local _ss_lab=0 _ss_i
        for ((_ss_i = 1; _ss_i < ${#_t1arr[@]}; _ss_i++)); do
            [[ "${_t1arr[$_ss_i]}" == %* ]] && { _ss_lab=$((_ss_lab + 1)); continue; }
            [[ "${_t1arr[$_ss_i]}" =~ ^[A-Z][A-Z0-9/]*$ ]] && _ss_lab=$((_ss_lab + 1))
        done
        [[ $((_ss_lab * 2)) -ge $(( ${#_t1arr[@]} - 1 )) ]] && v0=0
    fi
    # YEAR columns: a report header whose only value tokens are distinct
    # calendar years (`Metric  2023  2024  2025`) over data that never shows a
    # year is a label row — the years ARE the column names.
    if [[ $v0 -ge 2 && ${#_t1arr[@]} -ge 3 && ! "${_t1arr[0]}" =~ ^[0-9] ]]; then
        local _yr_n=0 _yr_t _yr_l _yr_ok=1
        local -A _yr_seen=()
        for _yr_t in "${_t1arr[@]}"; do
            if [[ "$_yr_t" =~ ^(19|20)[0-9]{2}$ ]]; then
                [[ -n "${_yr_seen[$_yr_t]:-}" ]] && _yr_ok=0
                _yr_seen[$_yr_t]=1; _yr_n=$((_yr_n + 1))
            fi
        done
        if [[ $_yr_ok -eq 1 && $_yr_n -eq $v0 ]]; then
            _fr_lines "$text"
            local _yr_i=0
            for _yr_l in "${_FR_LINES[@]}"; do
                [[ "${_yr_l}" != *[![:space:]]* ]] && continue
                _yr_i=$((_yr_i + 1)); [[ $_yr_i -eq 1 ]] && continue
                _fr_tok "$_yr_l"
                for _yr_t in "${_FR_TOK[@]}"; do
                    [[ "$_yr_t" =~ ^(19|20)[0-9]{2}$ ]] && { _yr_ok=0; break 2; }
                done
                [[ $_yr_i -ge 40 ]] && break
            done
            [[ $_yr_ok -eq 1 ]] && v0=0
        fi
    fi
    local labelly=1 _lbl_seen=0 _lbl_ok
    for _t in "${_t1arr[@]}"; do
        [[ "$_t" =~ ^[\|#/%+-]$ ]] && continue
        _lbl_seen=1
        _lbl_ok=0
        [[ "$_t" =~ [A-Za-z0-9] ]] && _lbl_ok=1
        [[ $_row_cjk -eq 1 && "$_t" != *[[:ascii:]]* ]] && _lbl_ok=1
        # (a short WHOLE bracketed token AFTER a label word is a unit —
        # hyperfine's `Mean [ms]`; a leading `[warn]` tag and a bracket SPLIT
        # across tokens, `[Hardware event]`, stay data)
        if [[ $_lbl_seen -eq 1 && "$_t" != "${_t1arr[0]}" && "$_t" =~ ^\[[A-Za-z%/]{1,6}\]$ ]]; then continue; fi
        # (a short ABBREVIATED label before the row's last token — df's
        # German `Verf.`, `No. of calls`, `Compr.` — is a label; a final
        # `word.` closes a sentence and stays prose)
        if [[ "$_t" =~ ^[A-Za-z]{1,6}\.$ && "$_t" != "${_t1arr[$(( ${#_t1arr[@]} - 1 ))]}" ]]; then continue; fi
        [[ $_lbl_ok -eq 1 && ! "$_t" =~ ^\[ && ! "$_t" =~ \]$ && ! "$_t" =~ \.$ ]] || { labelly=0; break; }
    done
    [[ $_lbl_seen -eq 0 ]] && labelly=0
    # PROSE veto: a sentence is not a header. Row 1 shaped `Titleword lower
    # lower …` — first token Titlecase, EVERY other token a pure lowercase
    # word (>=2 of them), no digits anywhere — over data whose modal token
    # count differs from row 1's is a title line ("List of devices attached"),
    # not labels. Real multi-word-label headers keep further Titlecase tokens
    # ("Property Name … Group") and survive; lowercase HEADERS ("username
    # fullname active") fail the Titlecase-first test and survive.
    if [[ $labelly -eq 1 && ${#_t1arr[@]} -ge 3 && "${_t1arr[0]}" =~ ^[A-Z][a-z]+$ ]]; then
        local _pr_low=1 _pr_stop=0 _pr_i
        for ((_pr_i = 1; _pr_i < ${#_t1arr[@]}; _pr_i++)); do
            [[ "${_t1arr[$_pr_i]}" =~ ^[a-z]+$ ]] || { _pr_low=0; break; }
            case "${_t1arr[$_pr_i]}" in
                of|the|to|in|for|with|and|on|at|by|from|is|are) _pr_stop=1 ;;
            esac
        done
        # A sentence carries a function word ("List OF devices attached");
        # a lowercase label row ("Host cpu mem disk net") does not.
        if [[ $_pr_low -eq 1 && $_pr_stop -eq 1 ]]; then
            local _pr_m=0 _pr_b=0 _pr_a _pr_n
            for ((_pr_i = 1; _pr_i < nlines; _pr_i++)); do
                _pr_n=0
                for ((_pr_a = 1; _pr_a < nlines; _pr_a++)); do
                    [[ ${counts[$_pr_a]} -eq ${counts[$_pr_i]} ]] && _pr_n=$((_pr_n + 1))
                done
                [[ $_pr_n -gt $_pr_b ]] && { _pr_b=$_pr_n; _pr_m=${counts[$_pr_i]}; }
            done
            [[ $_pr_m -ne ${counts[0]} ]] && labelly=0
        fi
    fi
    # Labels do not recur as values: when >= 2 DISTINCT word tokens of row 1
    # reappear in row 2 (`+ aws_instance.web will be created` over `~ … will
    # be updated`), row 1 is a record like the others, not a header.
    if [[ $labelly -eq 1 && $caps0 -eq 0 && $nlines -ge 2 ]]; then
        local _ov_l2="" _ov_i=0 _ov_t _ov_u _ov_n=0
        _fr_lines "$text"
        for _ov_t in "${_FR_LINES[@]}"; do
            [[ "${_ov_t}" != *[![:space:]]* ]] && continue
            _ov_i=$((_ov_i + 1)); [[ $_ov_i -eq 2 ]] && { _ov_l2="$_ov_t"; break; }
        done
        local -A _ov_seen=()
        _fr_tok "$_ov_l2"
        for _ov_u in "${_FR_TOK[@]}"; do _ov_seen[$_ov_u]=1; done
        local -A _ov_done=()
        for _ov_t in "${_t1arr[@]}"; do
            [[ "$_ov_t" =~ ^[A-Za-z]{2,}$ && -n "${_ov_seen[$_ov_t]:-}" && -z "${_ov_done[$_ov_t]:-}" ]] \
                && { _ov_done[$_ov_t]=1; _ov_n=$((_ov_n + 1)); }
        done
        [[ $_ov_n -ge 2 ]] && labelly=0
    fi
    if [[ $caps0 -eq 1 || ( $v0 -eq 0 && ${dcount[0]} -eq 0 && $labelly -eq 1 && $maxd -gt 0 ) \
          || ( $v0 -eq 0 && $labelly -eq 1 && $vrows -gt 0 && $vrows -eq $((nlines - 1)) ) \
          || ( $v0 -eq 0 && $labelly -eq 1 && $(( moren * 2 )) -gt $((nlines - 1)) ) ]]; then
        _AC_SHAPE_OUT="HDR ${counts[0]}"
        return 0
    fi

    # All-text table (no digits anywhere): numeric contrast can't identify the
    # header, but wording can — row 1 is a header when every token is a bare
    # word (letters only, no path/host/option punctuation) and none of them
    # recurs in row 2 (labels don't repeat as values). This promotes
    # `Package Ecosystem Severity State` / `database tableName isTemporary`
    # while `mount`/`retroarch`-style all-text records (slashes, dashes,
    # repeated words) stay headerless.
    local alltext=1
    for ((i = 0; i < nlines; i++)); do [[ ${dcount[$i]} -gt 0 ]] && { alltext=0; break; }; done
    if [[ $v0 -eq 0 && $alltext -eq 1 && $nlines -ge 3 ]]; then
        local wordy=1 styled=0
        for _t in "${_t1arr[@]}"; do [[ "$_t" =~ ^[A-Za-z][A-Za-z0-9_%]*$ ]] || { wordy=0; break; }; done
        # Labels are STYLED words — Titlecase (`Package`) or camelCase
        # (`tableName`); an all-lowercase row (`sqlite3 .tables` name grid)
        # is data, not a header.
        for _t in "${_t1arr[@]}"; do [[ "$_t" =~ ^[A-Z][a-z] || "$_t" =~ [a-z][A-Z] ]] && { styled=1; break; }; done
        # …or the styling contrast is on the DATA side: a lowercase header
        # (`username fullname active`, `household members flag`) still reads
        # as a header when EVERY data row carries a token the header lacks —
        # Titlecase (`Alice Anders`) or fully non-ASCII (emoji, Farsi). A
        # lowercase name grid (sqlite .tables) has neither and stays data.
        if [[ $wordy -eq 1 && $styled -eq 0 ]]; then
            local _dc_all=1 _dc_hit _dc_tk _dc_l _dc_i=0
            [[ $_acs_fl -eq 1 ]] || _fr_lines "$text"
            local _fri784; for ((_fri784 = 0; _fri784 < ${#_FR_LINES[@]}; _fri784++)); do _dc_l="${_FR_LINES[$_fri784]}"
                [[ "${_dc_l}" != *[![:space:]]* ]] && continue
                _dc_i=$((_dc_i + 1))
                [[ $_dc_i -eq 1 ]] && continue          # skip the header row
                _dc_hit=0
                local _dc_arr=(); _fr_tok "$_dc_l"; _dc_arr=("${_FR_TOK[@]}")
                for _dc_tk in "${_dc_arr[@]}"; do
                    [[ "$_dc_tk" =~ ^[A-Z][a-z] ]] && { _dc_hit=1; break; }
                    [[ "$_dc_tk" != *[[:ascii:]]* ]] && { _dc_hit=1; break; }
                done
                [[ $_dc_hit -eq 0 ]] && { _dc_all=0; break; }
                [[ $_dc_i -ge 40 ]] && break
            done
            [[ $_dc_all -eq 1 ]] && styled=1
        fi
        # And the data under it must be TABLE-shaped: a modal column count
        # covering >=60% of the data rows, within 1 of the header's own count
        # (multi-word labels run one over). Ragged prose (`dolt status`,
        # whose "On branch main" is a sentence) fails this.
        local shaped=0
        if [[ $wordy -eq 1 && $styled -eq 1 ]]; then
            local _dm=0 _db=0 _da _dbn
            for ((i = 1; i < nlines; i++)); do
                _dbn=0
                for ((_da = 1; _da < nlines; _da++)); do [[ ${counts[$_da]} -eq ${counts[$i]} ]] && _dbn=$((_dbn + 1)); done
                [[ $_dbn -gt $_db ]] && { _db=$_dbn; _dm=${counts[$i]}; }
            done
            local _hd=$(( counts[0] - _dm )); [[ $_hd -lt 0 ]] && _hd=$(( -_hd ))
            [[ $(( _db * 100 / (nlines - 1) )) -ge 60 && $_hd -le 1 ]] && shaped=1
            # `Name Description` over wider free-text rows (spin templates):
            # a 2-label header with a consistent, much wider body is the
            # name+description family — positional assignment reunites the
            # description column downstream.
            [[ $(( _db * 100 / (nlines - 1) )) -ge 60 && ${counts[0]} -eq 2 && $_dm -ge 4 ]] && shaped=1
            # SPARSE MATRIX (`Role  read  write  delete  admin` over `viewer
            # x` / `editor  x  x`): ragged rows whose every cell sits under
            # one header label, left to right, at most one cell per label.
            [[ $shaped -eq 0 && ${counts[0]} -ge 3 && $nlines -ge 3 ]] && _ac_sparse_grid "$text" && shaped=1
        fi
        if [[ $shaped -eq 1 ]]; then
            local second_line="" idx2=0
            [[ $_acs_fl -eq 1 ]] || _fr_lines "$text"
            local _fri822; for ((_fri822 = 0; _fri822 < ${#_FR_LINES[@]}; _fri822++)); do _line="${_FR_LINES[$_fri822]}"
                [[ "${_line}" != *[![:space:]]* ]] && continue
                idx2=$((idx2 + 1)); [[ $idx2 -eq 2 ]] && { second_line="$_line"; break; }
            done
            local overlap=0 _t2 _t2arr; _t2arr=(); _fr_tok "$second_line"; _t2arr=("${_FR_TOK[@]}")
            for _t in "${_t1arr[@]}"; do
                for _t2 in "${_t2arr[@]}"; do [[ "$_t" == "$_t2" ]] && { overlap=1; break 2; }; done
            done
            [[ $overlap -eq 0 ]] && { _AC_SHAPE_OUT="HDR ${counts[0]}"; return 0; }
        fi
    fi

    # Headerless: require a modal column count (>=3) shared by most lines.
    local mode=0 best=0 c d k
    for c in "${counts[@]}"; do
        k=0
        for d in "${counts[@]}"; do [[ "$d" -eq "$c" ]] && k=$((k + 1)); done
        [[ $k -gt $best ]] && { best=$k; mode=$c; }
    done
    if [[ $mode -eq 2 && $nlines -ge 3 && $(( best * 100 / nlines )) -ge 60 ]]; then
        # A strict 2-column block is a table (not prose / key-value) only when
        # its tokens are VALUES: pure numbers or strings carrying separator
        # punctuation (paths, module@version, timestamps) — `go mod graph`,
        # redis latency history. Prose and `Key value` snapshots don't qualify.
        local vlike=0 tot=0 _ln
        [[ $_acs_fl -eq 1 ]] || _fr_lines "$text"
        for _ln in "${_FR_LINES[@]}"; do
            [[ "${_ln}" != *[![:space:]]* ]] && continue
            _t1arr=(); _fr_tok "$_ln"; _t1arr=("${_FR_TOK[@]}")
            for _t in "${_t1arr[@]}"; do
                tot=$((tot + 1))
                [[ "$_t" =~ ^[0-9][0-9.,:%-]*$ || "$_t" == */* || "$_t" == *@* || "$_t" == *:* ]] && vlike=$((vlike + 1))
            done
        done
        [[ $tot -gt 0 && $(( vlike * 100 / tot )) -ge $(( 75 - ${_FR_SLACK:-0} )) ]] && { _AC_SHAPE_OUT="HL 2"; return 0; }
    fi
    [[ $mode -lt 3 ]] && return 1
    [[ $(( best * 100 / ${#counts[@]} )) -lt 60 ]] && return 1
    _AC_SHAPE_OUT="HL $mode"
    return 0
}

# A BIG text's verdict is memoised (a pure function of the text and the
# sample slack): the extract phase re-runs detect on the same 10 MB text,
# and recomputing it cost ~2 s. Initialised once (see _AC_BODY_KEY).
: "${_AC_DET_KEY=}" "${_AC_DET_SLK:=0}" "${_AC_DET_RC:=1}" "${_AC_DET_CONF:=0}" "${_AC_DET_OK:=0}"
strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    if (( ${#text} > _FR_BIG_BYTES )); then
        if [[ $_AC_DET_OK -eq 1 && "${_FR_SLACK:-0}" == "$_AC_DET_SLK" ]] \
           && (( ${#text} == ${#_AC_DET_KEY} )) && [[ "$text" == "$_AC_DET_KEY" ]]; then
            _STRATEGY_CONFIDENCE=$_AC_DET_CONF
            return $_AC_DET_RC
        fi
        local _acd_rc=0
        _ac_detect "$text" || _acd_rc=$?
        _AC_DET_KEY="$text"; _AC_DET_SLK="${_FR_SLACK:-0}"
        _AC_DET_RC=$_acd_rc; _AC_DET_CONF=$_STRATEGY_CONFIDENCE; _AC_DET_OK=1
        return $_acd_rc
    fi
    _ac_detect "$text"
}

_ac_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0

    # Decline space-padded assignment blocks — `KEY = value`, `KEY(ctx) = value`
    # (e.g. `ansible-config dump`). The ` = ` is a separator, not a data column;
    # aligned-columns would split it into a bogus middle column and mangle any
    # value with inner spaces. The equals parser tidies these to one field per key.
    local _eq=0 _et=0 _el
    if (( ${#text} > _FR_BIG_BYTES )); then
        # BIG input: this loop and the kv-decline loop below in ONE awk pass
        # (non-blank lines, ` = ` lines, kv-shaped lines, and the modal
        # token count with _fr_modal's first-occurrence tie-break).
        local _nb=0 _kv=0 _m=0 _best=0
        read -r _et _eq _kv _m _best < <(cat <<< "$text" | awk '
            /[^ \t\n\v\f\r]/ {
                et++
                if (index($0, " = ")) eq++
                if ($0 ~ /^[ \t\n\v\f\r]*[A-Za-z][^:=]*:[ \t\n\v\f\r]/ \
                    || $0 ~ /^[ \t\n\v\f\r]*[A-Za-z][A-Za-z0-9_]*=/) kv++
                if (!(NF in C)) ord[++no] = NF
                C[NF]++
            }
            END {
                for (i = 1; i <= no; i++) if (C[ord[i]] > best) { best = C[ord[i]]; mode = ord[i] }
                printf "%d %d %d %d %d\n", et, eq, kv, mode, best
            }')
        [[ $_et -ge 2 && $(( _eq * 100 / _et )) -ge $(( 80 + ${_FR_SLACK:-0} )) ]] && return 1
        _nb=$_et
        if [[ $_nb -ge 2 && $(( _kv * 100 / _nb )) -ge $(( 80 + ${_FR_SLACK:-0} )) ]]; then
            [[ $_m -ge 3 && $(( _best * 100 / _nb )) -ge $(( 60 - ${_FR_SLACK:-0} )) ]] || return 1
        fi
    else
    _fr_lines "$text"
    for _el in "${_FR_LINES[@]}"; do
        [[ "${_el}" != *[![:space:]]* ]] && continue
        _et=$((_et + 1))
        [[ "$_el" == *" = "* ]] && _eq=$((_eq + 1))
    done
    [[ $_et -ge 2 && $(( _eq * 100 / _et )) -ge $(( 80 + ${_FR_SLACK:-0} )) ]] && return 1

    # Decline pure key/value blocks — `label : value` / `label: value` (e.g.
    # `pacman -Qi`, `rpm -qi`) or `Key=Value` (e.g. `systemctl show`). These are
    # single-record snapshots the colons/equals parsers tidy to one wide row;
    # aligned-columns would wrongly split them into a ragged 2-column table.
    # But a consistent multi-column table whose rows happen to end in a `label:`
    # (e.g. `/proc/softirqs` "HI:  0 0 0", `lsusb` "… Device 002: ID …") is a real
    # table — so only decline when the block is RAGGED (no dominant column count),
    # which is what a genuine key/value block looks like.
    local _nb=0 _kv=0 _cl _cc=() _ct
    for _cl in "${_FR_LINES[@]}"; do
        [[ "${_cl}" != *[![:space:]]* ]] && continue
        _nb=$((_nb + 1))
        if [[ "$_cl" =~ ^[[:space:]]*[A-Za-z][^:=]*:[[:space:]] \
              || "$_cl" =~ ^[[:space:]]*[A-Za-z][A-Za-z0-9_]*= ]]; then
            _kv=$((_kv + 1))
        fi
        _fr_tok "$_cl"; _cc+=("${#_FR_TOK[@]}")
    done
    if [[ $_nb -ge 2 && $(( _kv * 100 / _nb )) -ge $(( 80 + ${_FR_SLACK:-0} )) ]]; then
        # Modal column count: a strong, consistent ≥3-column shape means a table,
        # not a kv block — keep it with aligned-columns.
        local _m=0 _best=0
        _fr_modal ${_cc[@]+"${_cc[@]}"}; _m=$_FR_MODE; _best=$_FR_MODE_N
        [[ $_m -ge 3 && $(( _best * 100 / _nb )) -ge $(( 60 - ${_FR_SLACK:-0} )) ]] || return 1
    fi
    fi

    # Structural detection: a header row (or a headerless block) of columns with
    # a consistent count. Recognises the whole class of whitespace-columnar tool
    # output (ps, df, ss, iostat, netstat, top, lsblk, systemctl, mount, who,
    # vmstat, ls -l …) without a per-tool rule. Confidence scales with column
    # consistency so a clean table outranks the key/value parsers.
    local shape; _ac_shape_v "$text" || return 1; shape="$_AC_SHAPE"
    local mode="${shape%% *}" n_h="${shape##* }"
    local hdr_lines=1
    case "$mode" in HL) hdr_lines=0 ;; HDR) hdr_lines=1 ;; HDR2) hdr_lines=2 ;; esac

    local idx=0 data_rows=0 consistent=0 header_caps=1 _line
    [[ ${_AC_SHAPE_FRESH:-0} -eq 1 ]] || { _ac_body_v "$text"; _fr_lines "$_AC_BODY"; }
    local _fri944; for ((_fri944 = 0; _fri944 < ${#_FR_LINES[@]}; _fri944++)); do _line="${_FR_LINES[$_fri944]}"
        [[ "${_line}" != *[![:space:]]* ]] && continue
        idx=$((idx + 1))
        local _tk; _tk=(); _fr_tok "$_line"; _tk=("${_FR_TOK[@]}")
        local n=${#_tk[@]}
        if [[ $idx -le $hdr_lines ]]; then
            if [[ $idx -eq $hdr_lines ]]; then
                local t
                for t in "${_tk[@]}"; do [[ "$t" =~ [a-z] ]] && header_caps=0; done
            fi
            continue    # header row(s) are not data rows
        fi
        [[ $n -ge 2 ]] && data_rows=$((data_rows + 1))
        [[ $n -ge $((n_h - 1)) ]] && consistent=$((consistent + 1))
        [[ $idx -ge 40 ]] && break
    done
    [[ "$mode" == HL ]] && header_caps=0

    [[ $data_rows -lt 1 ]] && return 1

    local conf=40
    [[ $data_rows -ge 2 ]] && conf=$((conf + 10))
    conf=$((conf + consistent * 20 / data_rows))   # column-consistency bonus (0..20)
    [[ $header_caps -eq 1 ]] && conf=$((conf + 5))  # ALL-CAPS header (ps/df/ss style)
    [[ "$mode" == HL ]] && conf=$((conf - 10))      # headerless is a weaker signal
    [[ $conf -gt 75 ]] && conf=75
    [[ $conf -lt 40 ]] && conf=40
    # General-structure tier (extract/README.md "Confidence rubric"): the raw
    # 40..75 evidence score maps onto 60..69. A header + consistent columns is
    # stronger evidence than any catch-all or loose kv shape (<= 60), and
    # weaker than a format-specific syntax (>= 70) — the parsers that used to
    # outrank it by priority now outrank it by confidence too.
    _STRATEGY_CONFIDENCE=$(( 60 + (conf - 40) * 9 / 35 ))
    return 0
}

# Is the block cleanly column-aligned to its header? (first input line = header).
# A data row is aligned when the character just before each header column start
# is whitespace — i.e. no value bleeds across a header column boundary. Prints
# "1" when >=80% of data rows are aligned and the header has >=2 columns, else
# "0". Only cleanly-aligned tables (docker/kubectl/helm) get positional parsing;
# irregular / right-aligned-overflow tables (ps/df/vmstat) stay on tokenization.
_ac_aligned () {
    awk '
    NR==1 {
        hl=$0; L=length(hl); i=1; nc=0
        while (i<=L) {
            while (i<=L && substr(hl,i,1)==" ") i++
            if (i>L) break
            nc++; cstart[nc]=i
            while (i<=L && !(substr(hl,i,1)==" " && substr(hl,i+1,1)==" ")) i++
        }
        next
    }
    {
        ndata++; ok=1
        for (c=2;c<=nc;c++) {
            ch=substr($0,cstart[c]-1,1)
            if (ch!="" && ch!=" ") { ok=0; break }
        }
        if (ok) aligned++
    }
    END {
        if (nc<2 || ndata==0) { print "0"; exit }
        if (aligned*100/ndata >= 80) print "1"; else print "0"
    }'
}

# Positional token assignment for a cleanly-aligned block. First input line is the
# header; its 2+-space fields define column start positions. Each line's tokens
# are assigned to the column region [cstart_i, cstart_{i+1}) their start falls in,
# so a multi-word cell ("2 weeks ago" under CREATED) is rejoined and a multi-word
# header ("IMAGE ID") names a single column. Emits TAB-separated cells per line.
_ac_assign () {
    awk '
    NR==1 {
        hl=$0; L=length(hl); i=1; nc=0
        while (i<=L) {
            while (i<=L && substr(hl,i,1)==" ") i++
            if (i>L) break
            nc++; cstart[nc]=i
            while (i<=L && !(substr(hl,i,1)==" " && substr(hl,i+1,1)==" ")) i++
        }
        cstart[nc+1]=1000000
        # Header tokens with their own start/end offsets — the raw material
        # for the sub-column refinement below.
        hn=0; i=1
        while (i<=L) {
            while (i<=L && substr(hl,i,1)==" ") i++
            if (i>L) break
            hn++; hts[hn]=i; htx[hn]=""
            while (i<=L && substr(hl,i,1)!=" ") { htx[hn]=htx[hn] substr(hl,i,1); i++ }
            hte[hn]=i-1
        }
        for (i2=1;i2<=hn;i2++) hcnt[htx[i2]]++
    }
    { rows[NR]=$0; nr=NR }
    END {
        # SUB-COLUMN REFINEMENT. A 2-space window holding k>=2 header tokens
        # is EITHER one multi-word label ("Ends At", "Property Name") OR k
        # separate single-space-separated columns ("SIZE USED PRIO",
        # "DEVICE OFFSET TYPE UUID"). The tell is alignment: real sub-columns
        # keep their data tokens edge-aligned under each header token (left
        # edge for left-aligned, right edge for right-aligned); a multi-word
        # value ("2026-07-11 06:00:00" under "Ends At") aligns only with the
        # window, not with each label token. Split a window into sub-columns
        # only when EVERY header token in it edge-aligns in >=60% of rows.
        ndata=nr-1
        for (r=2;r<=nr;r++) {
            line=rows[r]; L=length(line); i=1
            tn[r]=0
            while (i<=L) {
                while (i<=L && substr(line,i,1)==" ") i++
                if (i>L) break
                ts=i; anum=0
                while (i<=L && substr(line,i,1)!=" ") {
                    if (substr(line,i,1) ~ /[A-Za-z0-9]/) anum=1
                    i++
                }
                # Only alnum-bearing tokens witness an edge: a bare "/"
                # separator (docker stats MEM USAGE) must not vouch for a
                # sub-column boundary. Spans are kept for the bridge veto;
                # bare separators are kept for the composite-value veto.
                if (anum) {
                    sa[r "," ts]=1; ea[r "," (i-1)]=1
                    tn[r]++; tsA[r "," tn[r]]=ts; teA[r "," tn[r]]=i-1
                } else {
                    bn[r]++; bsA[r "," bn[r]]=ts
                }
            }
        }
        # Token spans per row are also needed window-wise: a window may only
        # split when the MODAL count of data tokens inside it equals its
        # label count — a single "webapp" under "Job ID", "0.006442" under
        # "Avg time" or "a1b2c3" under "CONTAINER ID" must never split (the
        # duplicate/empty sub-columns collide in the melt and DROP data).
        for (r=2;r<=nr;r++) {
            line=rows[r]; L=length(line); i=1
            while (i<=L) {
                while (i<=L && substr(line,i,1)==" ") i++
                if (i>L) break
                ts=i
                while (i<=L && substr(line,i,1)!=" ") i++
                for (w=1;w<=nc;w++)
                    if (ts>=cstart[w] && ts<cstart[w+1]) { wc[r "," w]++; break }
            }
        }
        m=0
        for (w=1;w<=nc;w++) {
            k=0
            for (t=1;t<=hn;t++)
                if (hts[t]>=cstart[w] && hts[t]<cstart[w+1]) { k++; wt[k]=t }
            ok=0
            if (k>=2 && ndata>0) {
                # MAX data token count inside this window must REACH the
                # label count: a lone "webapp" under "Job ID" (max 1 < 2)
                # must never split — the duplicate/empty sub-columns collide
                # in the melt and DROP data. More tokens than labels is fine
                # (xz-list holds "12.4 MiB  88.2 MiB" under
                # "Compressed Uncompressed"); the edge gate arbitrates.
                mo=0
                for (r=2;r<=nr;r++) if (wc[r "," w]+0 > mo) mo=wc[r "," w]+0
                if (mo>=k) {
                    ok=1
                    # DUPLICATE-NAME veto: sub-labels that repeat elsewhere
                    # in the header ("CPU REQUESTS  CPU LIMITS" —
                    # kube-capacity) would collide in the melt and DROP a
                    # column; the joined window names stay unique.
                    for (j=1;j<=k;j++)
                        if (hcnt[htx[wt[j]]] > 1) ok=0
                    # COMPOSITE-VALUE veto: a bare SEPARATOR token ("12M / 4M"
                    # under "NET RX/TX" — ctop gauges) inside the window marks
                    # one composite value, never two columns. A separator sits
                    # BETWEEN alnum tokens of the same window; a bare token
                    # with nothing after it is a value in its own right
                    # (a "/" mountpoint) and does not veto.
                    for (r=2;r<=nr && ok;r++)
                        for (x=1;x<=bn[r]+0;x++) {
                            if (!(bsA[r "," x] >= cstart[w] && bsA[r "," x] < cstart[w+1])) continue
                            lft=0; rgt=0
                            for (y=1;y<=tn[r];y++) {
                                if (tsA[r "," y] >= cstart[w] && tsA[r "," y] < cstart[w+1]) {
                                    if (teA[r "," y] < bsA[r "," x]) lft=1
                                    if (tsA[r "," y] > bsA[r "," x]) rgt=1
                                }
                            }
                            if (lft && rgt) { ok=0; break }
                        }
                    # BRIDGE veto: a data token that SPANS a sub-column
                    # start ("93.184.216.34:443" across "Peer Address:Port")
                    # is one value bridging both labels — splitting would
                    # strand an empty sub-column.
                    for (j=2;j<=k && ok;j++) {
                        t=wt[j]; br=0; bden=0
                        for (r=2;r<=nr;r++) {
                            if (wc[r "," w]+0 < 1) continue
                            bden++
                            for (x=1;x<=tn[r];x++)
                                if (tsA[r "," x] < hts[t] && teA[r "," x] >= hts[t]) { br++; break }
                        }
                        if (bden>0 && br*100/bden >= 40) ok=0
                    }
                    if (!ok) { m++; bstart[m]=cstart[w]; bend[m]=0; bsub[m]=0; continue }
                    for (j=1;j<=k;j++) {
                        t=wt[j]; hit=0; den=0
                        # Denominator: only rows that HAVE a j-th token in
                        # this window — a sparse trailing sub-column (lsblk
                        # MOUNTPOINT) is judged on the rows where it exists.
                        # +-1 tolerance: `#`-prefixed headers (collectl) and
                        # one-char pads shift edges by a column.
                        for (r=2;r<=nr;r++) {
                            if (wc[r "," w]+0 < j) continue
                            den++
                            if (sa[r "," hts[t]] || sa[r "," (hts[t]-1)] || sa[r "," (hts[t]+1)] || \
                                ea[r "," hte[t]] || ea[r "," (hte[t]-1)] || ea[r "," (hte[t]+1)]) hit++
                        }
                        if (den==0 || hit*100/den < 60) { ok=0; break }
                    }
                }
            }
            if (ok) {
                for (j=1;j<=k;j++) {
                    m++; bstart[m]=hts[wt[j]]; bend[m]=hte[wt[j]]; bsub[m]=1
                }
            } else { m++; bstart[m]=cstart[w]; bend[m]=0; bsub[m]=0 }
        }
        bstart[m+1]=1000000
        for (r=1;r<=nr;r++) {
            line=rows[r]; L=length(line); i=1
            for (c=1;c<=m;c++) cell[c]=""
            while (i<=L) {
                while (i<=L && substr(line,i,1)==" ") i++
                if (i>L) break
                ts=i; tok=""
                while (i<=L && substr(line,i,1)!=" ") { tok=tok substr(line,i,1); i++ }
                te=i-1
                col=1
                for (c=1;c<=m;c++) { if (bstart[c]<=ts) col=c; else break }
                # Right-aligned escape: a value wider than its header label
                # starts left of the sub-column boundary but ENDS on the
                # label end (+-1, matching the split tolerance) —
                # end-alignment wins over start assignment.
                for (c=1;c<=m;c++)
                    if (bsub[c] && te>=bend[c]-1 && te<=bend[c]+1) { col=c; break }
                if (cell[col]=="") cell[col]=tok; else cell[col]=cell[col] " " tok
            }
            out=cell[1]
            for (c=2;c<=m;c++) out=out "\t" cell[c]
            print out
        }
    }'
}

# Split a line into cells at runs of >=2 spaces (the same column boundary a
# fixed-width table uses), keeping a single-spaced multi-word cell intact ("1.0
# TiB", "RAW USE", "pid 8821, uptime 2:14:08"). Emits TAB-separated cells. This
# is `_ac_seg` as a splitter — used for right-aligned numeric tables whose values
# carry inner spaces, which positional (start-of-column) assignment can't align.
_ac_split () {
    awk '{
      line=$0; L=length(line); i=1; nc=0; out=""; cur=""
      while(i<=L && substr(line,i,1)==" ") i++
      while(i<=L){
        if(substr(line,i,1)==" " && substr(line,i+1,1)==" "){
          out=(nc==0?cur:out"\t"cur); nc++; cur=""
          while(i<=L && substr(line,i,1)==" ") i++
        } else { cur=cur substr(line,i,1); i++ }
      }
      if(cur!=""){ out=(nc==0?cur:out"\t"cur); nc++ }
      print out
    }'
}

# Char-accurate positional grid for blocks with SCATTERED multibyte content
# (asv's `412±2ns`): the awk grid measures BYTES, so every token after a
# multibyte char drifts right and lands under the wrong header window. Bash
# under a UTF-8 locale measures characters. Subshell body so the locale
# switch can't leak. Prints the TAB grid when the block is cleanly aligned
# (>=80% of rows), else exits 1 (caller falls back). Fully-CJK tables keep
# the awk path — their double-width glyphs make byte math the closer proxy.
_ac_grid_mb () (
    export LC_ALL=C.UTF-8
    local hl; IFS= read -r hl
    local L=${#hl}; local i=0; local nc=0; local cstart=()
    while (( i < L )); do
        while (( i < L )) && [[ "${hl:$i:1}" == " " ]]; do i=$((i+1)); done
        (( i >= L )) && break
        cstart+=("$i"); nc=$((nc+1))
        while (( i < L )); do
            [[ "${hl:$i:1}" == " " && "${hl:$((i+1)):1}" == " " ]] && break
            i=$((i+1))
        done
    done
    (( nc < 2 )) && exit 1
    local rows=("$hl"); local l
    # `|| [[ -n "$l" ]]`: the caller pipes without a trailing newline, and a
    # plain read loop would silently drop the final data row.
    while IFS= read -r l || [[ -n "$l" ]]; do rows+=("$l"); done
    local aligned=0; local ndata=0; local r; local c; local ch
    for ((r=1; r<${#rows[@]}; r++)); do
        ndata=$((ndata+1)); local ok=1
        for ((c=1; c<nc; c++)); do
            ch="${rows[$r]:$((${cstart[$c]}-1)):1}"
            [[ -n "$ch" && "$ch" != " " ]] && { ok=0; break; }
        done
        [[ $ok -eq 1 ]] && aligned=$((aligned+1))
    done
    (( ndata == 0 )) && exit 1
    if (( aligned * 100 / ndata >= 80 )); then
        for ((r=0; r<${#rows[@]}; r++)); do
            local line="${rows[$r]}"; local n=${#line}; local j=0
            local cells=()
            for ((c=0; c<nc; c++)); do cells+=(""); done
            while (( j < n )); do
                while (( j < n )) && [[ "${line:$j:1}" == " " ]]; do j=$((j+1)); done
                (( j >= n )) && break
                local ts=$j; local tok=""
                while (( j < n )) && [[ "${line:$j:1}" != " " ]]; do tok+="${line:$j:1}"; j=$((j+1)); done
                local col=0
                for ((c=0; c<nc; c++)); do
                    if (( ${cstart[$c]} <= ts )); then col=$c; else break; fi
                done
                if [[ -z "${cells[$col]}" ]]; then cells[$col]="$tok"; else cells[$col]+=" $tok"; fi
            done
            local out="${cells[0]}"
            for ((c=1; c<nc; c++)); do out+=$'\t'"${cells[$c]}"; done
            printf '%s\n' "$out"
        done
        exit 0
    fi
    # RAGGED-ALIGNMENT fallback: a benchmark-style table whose data rows have
    # a UNIFORM token count above the label count (asv's `+ 412±2ns 440±3ns
    # 1.07 parser.time_parse` under `before after ratio`) with right-aligned
    # bleed. Use the first modal-width row's token spans as the reference
    # columns, map each header label onto the column it overlaps most (extra
    # columns stay unnamed for the caller's letter fallback), then assign
    # every row's tokens to reference columns by best overlap.
    _mb_spans () {  # $1=line -> _MB_TS/_MB_TE/_MB_TOK arrays
        local line="$1"; local n=${#line}; local j=0
        _MB_TS=(); _MB_TE=(); _MB_TOK=()
        while (( j < n )); do
            while (( j < n )) && [[ "${line:$j:1}" == " " ]]; do j=$((j+1)); done
            (( j >= n )) && break
            local ts=$j; local tok=""
            while (( j < n )) && [[ "${line:$j:1}" != " " ]]; do tok+="${line:$j:1}"; j=$((j+1)); done
            _MB_TS+=("$ts"); _MB_TE+=("$((j-1))"); _MB_TOK+=("$tok")
        done
    }
    local counts=(); local r2
    for ((r2=1; r2<${#rows[@]}; r2++)); do
        _mb_spans "${rows[$r2]}"
        counts+=("${#_MB_TOK[@]}")
    done
    local modal=0; local best=0
    _fr_modal ${counts[@]+"${counts[@]}"}; modal=$_FR_MODE; best=$_FR_MODE_N
    (( modal > nc && best >= 2 )) || exit 1
    local refts=(); local refte=()
    for ((r2=1; r2<${#rows[@]}; r2++)); do
        _mb_spans "${rows[$r2]}"
        [[ ${#_MB_TOK[@]} -eq $modal ]] || continue
        refts=("${_MB_TS[@]}"); refte=("${_MB_TE[@]}"); break
    done
    [[ ${#refts[@]} -eq $modal ]] || exit 1
    _mb_best_col () {  # $1=ts $2=te -> echoes reference column with max overlap
        local ts=$1; local te=$2; local bc=0; local bo=-999999; local c2 o lo hi
        for ((c2=0; c2<modal; c2++)); do
            lo=$ts; [[ ${refts[$c2]} -gt $lo ]] && lo=${refts[$c2]}
            hi=$te; [[ ${refte[$c2]} -lt $hi ]] && hi=${refte[$c2]}
            o=$((hi - lo))
            [[ $o -gt $bo ]] && { bo=$o; bc=$c2; }
        done
        echo "$bc"
    }
    local out_rows=(); local hdr=(); local c3
    for ((c3=0; c3<modal; c3++)); do hdr+=(""); done
    _mb_spans "$hl"
    local hi2
    for ((hi2=0; hi2<${#_MB_TOK[@]}; hi2++)); do
        c3="$(_mb_best_col "${_MB_TS[$hi2]}" "${_MB_TE[$hi2]}")"
        if [[ -z "${hdr[$c3]}" ]]; then hdr[$c3]="${_MB_TOK[$hi2]}"; else hdr[$c3]+=" ${_MB_TOK[$hi2]}"; fi
    done
    local out="${hdr[0]}"
    for ((c3=1; c3<modal; c3++)); do out+=$'\t'"${hdr[$c3]}"; done
    out_rows+=("$out")
    for ((r2=1; r2<${#rows[@]}; r2++)); do
        _mb_spans "${rows[$r2]}"
        local cells2=()
        for ((c3=0; c3<modal; c3++)); do cells2+=(""); done
        for ((hi2=0; hi2<${#_MB_TOK[@]}; hi2++)); do
            c3="$(_mb_best_col "${_MB_TS[$hi2]}" "${_MB_TE[$hi2]}")"
            if [[ -z "${cells2[$c3]}" ]]; then cells2[$c3]="${_MB_TOK[$hi2]}"; else cells2[$c3]+=" ${_MB_TOK[$hi2]}"; fi
        done
        out="${cells2[0]}"
        for ((c3=1; c3<modal; c3++)); do out+=$'\t'"${cells2[$c3]}"; done
        out_rows+=("$out")
    done
    printf '%s\n' "${out_rows[@]}"
    exit 0
)

# ---------------------------------------------------------------------------
# BIG-TABLE TWINS (perf). strategy_extract walks its `lines` array many times
# (token counts, 2-space segment counts, header-repeat and wrap checks); in
# bash each walk costs ~50 µs per line, so a 100k-row table spent most of a
# minute in them. Above _FR_BIG_BYTES (the body's size) each walk below is
# done by one awk pass with byte-identical results: tokens split exactly as
# _fr_tok's default IFS does (awk's default field splitting), segments are
# _ac_seg_v's count (1 + the interior runs of >=2 spaces), and modal values
# break ties toward the value seen first, as _fr_modal does.
# ---------------------------------------------------------------------------
_AC_AWK_SEG='
function seg(l) {
    sub(/^[ \t\n\v\f\r]+/, "", l)
    if (l == "") return 0
    sub(/ +$/, "", l)
    return gsub(/  +/, "&", l) + 1
}'

# _ac_group_prefix — strategy_extract's HDR2 group-prefixing step, on the
# CALLER's `headers`, `lines` (rows 0 and 1 only) and `mode` (bash dynamic
# scope), so the bash path and the big-table path share it.
_ac_group_prefix () {
    # HDR2 group-prefixing: when the field row repeats names under different
    # group labels (`Pod  Req Lim Use  Req Lim Use` under `CPU  Memory`), the
    # duplicates would COLLIDE in the wide record and the melt silently drops
    # the earlier group's columns. Disambiguate positionally: each duplicated
    # header token (except the first, key column) gets the group label whose
    # printed CENTER is nearest — `CPU_Req`, `Memory_Req`. Unique names stay
    # untouched, so single-group two-line headers (vmstat) are unaffected.
    if [[ "$mode" == HDR2 && ${#headers[@]} -ge 3 ]]; then
        local _gpdup=0 _gpi _gpj
        for ((_gpi = 1; _gpi < ${#headers[@]} && _gpdup == 0; _gpi++)); do
            for ((_gpj = _gpi + 1; _gpj < ${#headers[@]}; _gpj++)); do
                [[ "${headers[$_gpi]}" == "${headers[$_gpj]}" ]] && { _gpdup=1; break; }
            done
        done
        if [[ $_gpdup -eq 1 ]]; then
            # token centers of a raw line -> _GP_CENTERS / _GP_TOKS
            _gp_scan () {
                local _s="$1"
                local _i _c _st=-1 _n=${#_s}
                _GP_CENTERS=(); _GP_TOKS=()
                for ((_i = 0; _i <= _n; _i++)); do
                    _c="${_s:$_i:1}"
                    if [[ "$_c" != " " && "$_c" != "	" && $_i -lt $_n ]]; then
                        [[ $_st -lt 0 ]] && _st=$_i
                    elif [[ $_st -ge 0 ]]; then
                        _GP_TOKS+=("${_s:$_st:$((_i - _st))}")
                        _GP_CENTERS+=($(( (_st + _i - 1) / 2 )))
                        _st=-1
                    fi
                done
            }
            _gp_scan "${lines[0]}"
            local _gpg_toks=("${_GP_TOKS[@]}") _gpg_cent=("${_GP_CENTERS[@]}")
            # The group row's tokens become NAME PREFIXES — sanitize each
            # (vmstat -d's `------------reads------------` → `reads`), and bail
            # out entirely when the row is banner chrome rather than labels
            # (goose's `=== PER REQUEST METRICS ===`: punctuation-only edge
            # tokens mark a banner, whose words would make junk prefixes).
            local _gpk _gpsan=1
            if [[ ! "${_gpg_toks[0]}" =~ [A-Za-z0-9] \
                  || ! "${_gpg_toks[$(( ${#_gpg_toks[@]} - 1 ))]}" =~ [A-Za-z0-9] ]]; then
                _gpsan=0
            fi
            for ((_gpk = 0; _gpk < ${#_gpg_toks[@]}; _gpk++)); do
                local _gpt="${_gpg_toks[$_gpk]}"
                _gpt="${_gpt##+(-)}"; _gpt="${_gpt%%+(-)}"
                while [[ "$_gpt" == -* ]]; do _gpt="${_gpt#-}"; done
                while [[ "$_gpt" == *- ]]; do _gpt="${_gpt%-}"; done
                [[ -z "$_gpt" ]] && { _gpsan=0; break; }
                _gpg_toks[$_gpk]="$_gpt"
            done
            _gp_scan "${lines[1]}"
            local _gph_cent=("${_GP_CENTERS[@]}")
            if [[ $_gpsan -eq 1 && ${#_gpg_toks[@]} -ge 2 && ${#_gph_cent[@]} -eq ${#headers[@]} ]]; then
                # Mark duplicates on the ORIGINAL names first — renaming inside
                # the same pass would hide a later twin (`Req` at index 4 stops
                # matching once index 1 became `CPU_Req`) and leave the second
                # group's columns bare and still colliding with any third.
                local _gpdups=() _gpnew=()
                for ((_gpi = 0; _gpi < ${#headers[@]}; _gpi++)); do _gpdups[$_gpi]=0; done
                for ((_gpi = 1; _gpi < ${#headers[@]}; _gpi++)); do
                    for ((_gpj = 1; _gpj < ${#headers[@]}; _gpj++)); do
                        [[ $_gpj -ne $_gpi && "${headers[$_gpj]}" == "${headers[$_gpi]}" ]] && { _gpdups[$_gpi]=1; break; }
                    done
                done
                for ((_gpi = 1; _gpi < ${#headers[@]}; _gpi++)); do
                    [[ ${_gpdups[$_gpi]} -eq 0 ]] && continue
                    local _gpbest=0 _gpbd=999999 _gpdist
                    for ((_gpj = 0; _gpj < ${#_gpg_toks[@]}; _gpj++)); do
                        _gpdist=$(( ${_gph_cent[$_gpi]} - ${_gpg_cent[$_gpj]} ))
                        [[ $_gpdist -lt 0 ]] && _gpdist=$(( -_gpdist ))
                        [[ $_gpdist -lt $_gpbd ]] && { _gpbd=$_gpdist; _gpbest=$_gpj; }
                    done
                    _gpnew[$_gpi]="${_gpg_toks[$_gpbest]}_${headers[$_gpi]}"
                done
                # Nearest-centre can still COLLIDE when the group labels drift
                # off their fields across a wide header (zpool iostat -l: seven
                # groups over fourteen read/write fields, labels sliding right
                # until two `read`s both land on total_wait). Only then, and
                # only when the fields right of the key split EVENLY over the
                # groups, assign by ORDER instead: group g owns fields
                # g*k+1 .. (g+1)*k — the layout every evenly grouped header has.
                local _gpcol=0 _gpk2 _gpng=${#_gpg_toks[@]} _gpnf=$(( ${#headers[@]} - 1 ))
                local -A _gpseen=()
                for ((_gpi = 1; _gpi < ${#headers[@]}; _gpi++)); do
                    _gpk2="${_gpnew[$_gpi]:-${headers[$_gpi]}}"
                    [[ -n "${_gpseen[$_gpk2]:-}" ]] && _gpcol=1
                    _gpseen[$_gpk2]=1
                done
                if [[ $_gpcol -eq 1 && $(( _gpnf % _gpng )) -eq 0 && $_gpnf -ge $(( 2 * _gpng )) ]]; then
                    _gpk2=$(( _gpnf / _gpng ))
                    for ((_gpi = 1; _gpi < ${#headers[@]}; _gpi++)); do
                        [[ ${_gpdups[$_gpi]} -eq 0 ]] && continue
                        _gpnew[$_gpi]="${_gpg_toks[$(( (_gpi - 1) / _gpk2 ))]}_${headers[$_gpi]}"
                    done
                fi
                for ((_gpi = 1; _gpi < ${#headers[@]}; _gpi++)); do
                    [[ -n "${_gpnew[$_gpi]:-}" ]] && headers[$_gpi]="${_gpnew[$_gpi]}"
                done
            fi
        fi
    fi
}

# The OFFSET-ASSIGNMENT pass of strategy_extract (see the comment there),
# shared by the bash path and the big-table path.
_AC_AWK_OFFSET='
                    NR == 1 {
                        # Header token spans (1-based columns).
                        len = length($0); st = 0; nh = 0
                        for (i = 1; i <= len + 1; i++) {
                            c = (i <= len) ? substr($0, i, 1) : " "
                            if (c != " " && c != "\t") { if (st == 0) st = i }
                            else if (st > 0) {
                                nh++; hs[nh] = st; he[nh] = i - 1
                                nm = substr($0, st, i - st)
                                gsub(/\./, "_", nm)
                                hn[nh] = nm
                                st = 0
                            }
                        }
                        # A trailing preposition is the tail of a two-word
                        # label (`Mounted on`), not a column of its own —
                        # weld it onto its neighbour so the last value gets
                        # the full name instead of a truncated one.
                        pl = tolower(hn[nh])
                        if (nh >= 3 && pl ~ /^(on|by|in|at|of|to)$/) {
                            hn[nh - 1] = hn[nh - 1] "_" hn[nh]
                            he[nh - 1] = he[nh]
                            nh--
                        }
                        # DUPLICATE header token names are the signature of
                        # multi-word labels tokenized apart: doctl repeats ID
                        # (`Active Deployment ID` / `In Progress Deployment
                        # ID`), spark repeats Tasks three times. Per-token
                        # spans are meaningless there — the duplicate names
                        # collide in the melt and each label loses half of
                        # itself — so the whole path withdraws.
                        for (i = 1; i <= nh; i++)
                            for (j = i + 1; j <= nh; j++)
                                if (hn[i] == hn[j]) { dupname = 1 }
                        next
                    }
                    {
                        row++
                        len = length($0); st = 0
                        for (c = 1; c <= nh; c++) cells[c] = ""
                        for (i = 1; i <= len + 1; i++) {
                            ch = (i <= len) ? substr($0, i, 1) : " "
                            if (ch != " " && ch != "\t") { if (st == 0) st = i }
                            else if (st > 0) {
                                s = st; e = i - 1; st = 0
                                tok = substr($0, s, e - s + 1)
                                if (s >= hs[nh]) { col = nh; ov = 1 }
                                else {
                                    col = 0; ov = 0; nspan = 0
                                    for (c = 1; c <= nh; c++) {
                                        lo = (s > hs[c]) ? s : hs[c]
                                        hi = (e < he[c]) ? e : he[c]
                                        o = hi - lo + 1
                                        if (o > 0) nspan++
                                        if (o > ov) { ov = o; col = c }
                                    }
                                    # A token stretching across TWO header
                                    # token spans is a value sitting under a
                                    # multi-word label (`starfish-api` under
                                    # `Spec Name`) — count them; too many and
                                    # the table is not per-token aligned.
                                    if (nspan >= 2) nwide++
                                    if (col == 0) {
                                        # no overlap: nearest span by gap
                                        bd = -1
                                        for (c = 1; c <= nh; c++) {
                                            d = (e < hs[c]) ? hs[c] - e : s - he[c]
                                            if (bd < 0 || d < bd) { bd = d; col = c }
                                        }
                                    }
                                }
                                ntok++
                                if (ov > 0) nhit++
                                # Edge alignment: a genuinely offset-aligned
                                # table puts each value START at its header
                                # label start (left-aligned columns) or its
                                # END at the label end (right-aligned
                                # numerics). Prose that merely OVERLAPS spans
                                # (deno error lines under a first line
                                # mistaken for a header) has almost no edge
                                # hits, and that difference is the gate.
                                # NOTE: this comment sits inside a single-
                                # quoted awk program — no apostrophes.
                                for (c2 = 1; c2 <= nh; c2++)
                                    if (s == hs[c2] || e == he[c2]) { nedge++; break }
                                cells[col] = (cells[col] == "") ? tok : cells[col] " " tok
                            }
                        }
                        for (c = 1; c <= nh; c++)
                            if (cells[c] != "")
                                buf = buf "entry" row "." hn[c] " " cells[c] "\n"
                    }
                    END {
                        # Withdraw unless the rows really sit under the header:
                        # >=80% of tokens overlap a header span AND >=60% land
                        # exactly on a span edge (left- or right-aligned) AND
                        # the header names are per-token meaningful — no
                        # duplicate names, and <10% of tokens spanning two
                        # labels (multi-word-label tables belong to the
                        # positional grid / seg-split paths, not this one).
                        if (row == 0 || ntok == 0 || nhit * 5 < ntok * 4) exit 0
                        if (nedge * 10 < ntok * 6) exit 0
                        if (dupname) exit 0
                        if (nwide * 10 > ntok) exit 0
                        printf "%s", buf
                        printf "total_entries %d\n", row
                    }
'

# _ac_lines_stats FROM — aggregates over lines[FROM..] (the caller's `lines`):
#   _ACS_N      rows
#   _ACS_TMAX   largest token count
#   _ACS_TMOD   modal token count, _ACS_TMODN its count
#   _ACS_SMOD   modal segment count, _ACS_SMODN its count
#   _ACS_DIGIT  1 when any row holds a digit
#   _ACS_SSAME  1 when every row has the same segment count (_ACS_SFIRST)
#   _ACS_TFIRST token count of the first row; _ACS_TRAG 1 when any differs
# (When _ACX_F names a file — the big-table path — the rows are read from it
# instead, and results are memoised per FROM until _ACX_STATS_KEY is reset.)
_ACX_F=""
_ACX_STATS_KEY=""
declare -A _ACX_STATS=()
_ac_lines_stats () {
    local _from="$1"
    _ACS_N=0 _ACS_TMAX=0 _ACS_TMOD=0 _ACS_TMODN=0 _ACS_SMOD=0 _ACS_SMODN=0
    _ACS_DIGIT=0 _ACS_SSAME=1 _ACS_SFIRST=0 _ACS_TFIRST=0 _ACS_TRAG=0
    local _stats
    if [[ -n "$_ACX_F" ]]; then
        if [[ "$_ACX_STATS_KEY" != "$_ACX_F" ]]; then _ACX_STATS=(); _ACX_STATS_KEY="$_ACX_F"; fi
        if [[ -z "${_ACX_STATS[$_from]:-}" ]]; then
            _ACX_STATS[$_from]=$(_ac_lines_stats_awk "$_from" "$_ACX_F")
        fi
        _stats="${_ACX_STATS[$_from]}"
    else
        (( _from < ${#lines[@]} )) || return 0
        _stats=$(printf '%s\n' "${lines[@]:_from}" | _ac_lines_stats_awk)
    fi
    read -r _ACS_N _ACS_TMAX _ACS_TMOD _ACS_TMODN _ACS_SMOD _ACS_SMODN _ACS_DIGIT \
            _ACS_SSAME _ACS_SFIRST _ACS_TFIRST _ACS_TRAG <<< "$_stats"
}
# _ac_lines_stats_awk [SKIP FILE] — the stats of stdin, or of FILE's lines
# after the first SKIP (one pass, no `awk 'NR > SKIP' FILE |` in front).
_ac_lines_stats_awk () {
    awk -v skip="${1:-0}" "$_AC_AWK_SEG"'
        NR <= skip { next }
        {
            n++; t = NF; g = seg($0)
            if (t > tmax) tmax = t
            if (!(t in TC)) tord[++nt] = t
            TC[t]++
            if (!(g in SC)) sord[++ns] = g
            SC[g]++
            if (!dig && $0 ~ /[0-9]/) dig = 1
            if (n == 1) { sfirst = g; tfirst = t } else { if (g != sfirst) sdiff = 1; if (t != tfirst) trag = 1 }
        }
        END {
            for (i = 1; i <= nt; i++) if (TC[tord[i]] > tb) { tb = TC[tord[i]]; tm = tord[i] }
            for (i = 1; i <= ns; i++) if (SC[sord[i]] > sb) { sb = SC[sord[i]]; sm = sord[i] }
            printf "%d %d %d %d %d %d %d %d %d %d %d\n", n, tmax, tm, tb, sm, sb, dig, !sdiff, sfirst, tfirst, trag
        }' ${2:+"$2"}
}

# ---------------------------------------------------------------------------
# _ac_extract_big MODE NCOLS — strategy_extract for a BIG block, file to file.
# Mirrors strategy_extract step for step on the table held in a scratch file
# (only a few leading rows ever enter bash): collect the non-blank rows,
# drop header repeats / the units row, merge first-cell wraps, then the
# positional / segment / offset / header decisions from awk aggregates, and
# emit through _ac_emit_rows. Every decision is the bash path's, computed the
# same way (see the BIG-TABLE TWINS note). Paths that stay bash-only — the
# positional grid, non-ASCII blocks, the segment split, the headerless
# scaffold split and phrase merges — return 3 with the rows collected so far
# in _ACX_F, and strategy_extract carries on from there with its own loops.
# Returns 0 with the result printed otherwise.
# ---------------------------------------------------------------------------
_ac_extract_big () {
    local mode="$1" ncols="$2" p="$_FR_SCRATCH/ac.$BASHPID"
    local cur="$p.rows0" n H=()
    _ACX_F=""
    printf '%s\n' "$_AC_BODY" > "$p.body"

    # --- collect non-blank rows (footer-legend stop, as the bash loop) ---
    local need=0
    case "$mode" in HDR) need=2 ;; HDR2) need=3 ;; esac
    awk -v need="$need" '
        $0 !~ /[^ \t\n\v\f\r]/ { if (need > 0 && kept >= need) armed = 1; next }
        { if (armed && index($0, " = ")) exit; armed = 0; kept++; print }' "$p.body" > "$cur"
    rm -f "$p.body"
    _acx_rows () { n=$(awk 'END { print NR }' "$cur"); H=(); mapfile -t -n 4 H < "$cur"; }
    _acx_rows

    # --- table chrome: header repeats + the units row ---
    if [[ ( "$mode" == HDR || "$mode" == HDR2 ) && $n -ge 3 ]]; then
        local _fhidx=0; [[ "$mode" == HDR2 ]] && _fhidx=1
        local _fharr; _fr_tok "${H[$_fhidx]}"; _fharr=("${_FR_TOK[@]}")
        local _fhnorm="${_fharr[*]}"
        local _fhind="${H[$_fhidx]%%[![:space:]]*}"
        local _acx_norm='{ s = ""; for (k = 1; k <= NF; k++) s = (k > 1) ? s " " $k : $k }'
        local _fhdrfree=1
        if [[ ${#_fharr[@]} -lt 3 ]]; then
            _fhdrfree=0
        elif [[ "${H[$_fhidx]}" =~ [0-9] ]]; then
            local _frep=0 _ftot=0
            read -r _frep _ftot < <(_ACX_H="$_fhnorm" awk -v hidx="$_fhidx" "$_acx_norm"'
                NR - 1 > hidx { tot++; if (s == ENVIRON["_ACX_H"]) rep++ }
                END { printf "%d %d\n", rep, tot }' "$cur")
            [[ $_frep -eq 0 || $_ftot -eq 0 || $((_frep * 4)) -gt $_ftot ]] && _fhdrfree=0
        fi
        local _fi _farr _fnorm _fdind _ft _ftok _acx_dropu=0
        _fi=$((_fhidx + 1))
        _fr_tok "${H[$_fi]}"; _farr=("${_FR_TOK[@]}")
        _fnorm="${_farr[*]}"
        if ! [[ $_fhdrfree -eq 1 && "$_fnorm" == "$_fhnorm" ]] \
           && [[ ${#_farr[@]} -lt ${#_fharr[@]} && ${#_farr[@]} -ge 2 && ! "${H[$_fi]}" =~ [0-9] ]]; then
            _fdind="${H[$_fi]%%[![:space:]]*}"
            if [[ ${#_fdind} -gt ${#_fhind} ]]; then
                _ft=1
                for _ftok in "${_farr[@]}"; do
                    [[ ${#_ftok} -gt 6 ]] && { _ft=0; break; }
                    if [[ "$_ftok" == "("*")" ]]; then continue; fi
                    [[ "$_ftok" == *[A-Z]* && "$_ftok" == *[a-z]* ]] || { _ft=0; break; }
                done
                [[ $_ft -eq 1 ]] && _acx_dropu=1
            fi
        fi
        _ACX_H="$_fhnorm" awk -v hidx="$_fhidx" -v free="$_fhdrfree" -v dropu="$_acx_dropu" "$_acx_norm"'
            {
                i = NR - 1
                if (i > hidx) {
                    if (free && s == ENVIRON["_ACX_H"]) next
                    if (i == hidx + 1 && dropu) next
                }
                print
            }' "$cur" > "$p.rows1"
        cur="$p.rows1"; _acx_rows
    fi

    # --- first-cell wraps ---
    if [[ "$mode" == HDR && $ncols -ge 4 && $n -ge 3 ]]; then
        awk -v ncols="$ncols" '
            { L[NR] = $0; T[NR] = NF }
            END {
                for (i = 1; i <= NR; i++) {
                    if (i > 1 && i < NR && T[i] == 1) {
                        m = 1 + T[i + 1]
                        c = substr(L[i + 1], 1, 1)
                        if (m >= ncols - 1 && m <= ncols && (c == " " || c == "\t")) {
                            k = split(L[i], a); r = a[1]
                            k = split(L[i + 1], b)
                            for (j = 1; j <= k; j++) r = r " " b[j]
                            print r
                            i++
                            continue
                        }
                    }
                    print L[i]
                }
            }' "$cur" > "$p.rows2"
        cur="$p.rows2"; _acx_rows
    fi
    _ACX_F="$cur"
    _ACX_STATS_KEY=""     # _ac_lines_stats reads $_ACX_F from here on

    # --- positional decision (HDR/HDR2) ---
    if [[ "$mode" == HDR || "$mode" == HDR2 ]]; then
        local hidx=0; [[ "$mode" == HDR2 ]] && hidx=1
        local _htok; _fr_tok "${H[$hidx]}"; _htok=${#_FR_TOK[@]}
        _ac_lines_stats $((hidx + 1))
        local _maxd=$_ACS_TMAX _moded=$_ACS_TMOD
        local _use_pos=0
        if [[ $_maxd -gt $_htok ]]; then _use_pos=1
        elif [[ $_htok -ge 3 ]] && _ac_sparse_grid "$(awk -v h="$hidx" 'NR > h && NR <= h + 41' "$cur")"; then
            _use_pos=1
        elif [[ $_htok -gt $_maxd ]]; then
            _ac_lines_stats 0
            if [[ $_ACS_DIGIT -eq 0 ]]; then _use_pos=1
            else
                _ac_seg_v "${H[$hidx]}"
                [[ $_AC_SEG -ge 2 && $_AC_SEG -eq $_moded ]] && _use_pos=1
            fi
        else
            local _hsegq; _ac_seg_v "${H[$hidx]}"; _hsegq="$_AC_SEG"
            if [[ $_hsegq -ge 2 && $_hsegq -lt $_htok ]]; then
                _ac_lines_stats $((hidx + 1))
                [[ $_ACS_SMOD -eq $_hsegq ]] && _use_pos=1
            fi
        fi
        if [[ $_use_pos -eq 1 ]]; then
            # a non-ASCII block (the mb grid) or a cleanly aligned one (the
            # positional grid) takes the bash path
            awk -v h="$hidx" 'NR > h' "$cur" | LC_ALL=C grep -q $'[\x80-\xff]' && return 3
            [[ "$(awk -v h="$hidx" 'NR > h' "$cur" | _ac_aligned)" == "1" ]] && return 3
        fi
    fi

    # --- segment-split fallback (HDR): bash path when it fires ---
    if [[ "$mode" == HDR && $n -ge 2 ]]; then
        _ac_lines_stats 0
        local _sok=$_ACS_SSAME _sS=$_ACS_SFIRST _shw=$_ACS_TFIRST
        _ac_lines_stats 1
        [[ $_sok -eq 1 && $_sS -ge 2 && $_ACS_TMOD -gt $_shw ]] && return 3
        # (twin of the bash path's repeated-header-token trigger)
        if [[ $_sok -eq 1 && $_sS -ge 2 ]]; then
            local -A _xdseen=(); local _xdt
            _fr_tok "${H[0]}"
            for _xdt in "${_FR_TOK[@]}"; do
                [[ -n "${_xdseen[$_xdt]:-}" ]] && return 3
                _xdseen[$_xdt]=1
            done
        fi
    fi

    # --- offset assignment for sparse tables (HDR) ---
    if [[ "$mode" == HDR && $n -ge 3 ]]; then
        local _oa_h; _fr_tok "${H[0]}"; _oa_h=("${_FR_TOK[@]}")
        if [[ ${#_oa_h[@]} -ge 4 ]]; then
            _ac_lines_stats 1
            if [[ $_ACS_TMOD -lt ${#_oa_h[@]} && $_ACS_TMOD -ge 1 ]]; then
                local _oa_out
                _oa_out=$(awk "$_AC_AWK_OFFSET" "$cur")
                if [[ -n "$_oa_out" ]]; then
                    echo "$_oa_out"; return 0
                fi
            fi
        fi
    fi

    # --- header names ---
    local headers=() startidx=0 i lines=("${H[@]:0:2}")
    case "$mode" in
        HDR)  _fr_tok "${H[0]}"; headers=("${_FR_TOK[@]}"); startidx=1 ;;
        HDR2) _fr_tok "${H[1]}"; headers=("${_FR_TOK[@]}"); startidx=2 ;;
        HL)   for ((i = 1; i <= ncols; i++)); do _fr_col_letter "$i"; headers+=("$_FR_LETTER"); done; startidx=0 ;;
    esac
    _ac_group_prefix
    for ((i = 0; i < ${#headers[@]}; i++)); do headers[$i]="${headers[$i]//./_}"; done

    # --- trailing preposition weld ---
    if [[ ( "$mode" == HDR || "$mode" == HDR2 ) && ${#headers[@]} -ge 3 ]]; then
        local _tp_last="${headers[$(( ${#headers[@]} - 1 ))]}"
        local _tp_lc="${_tp_last,,}"
        case "$_tp_lc" in
            on|by|in|at|of|to)
                _ac_lines_stats "$startidx"
                if [[ $_ACS_TMOD -eq $(( ${#headers[@]} - 1 )) ]]; then
                    headers[$(( ${#headers[@]} - 2 ))]="${headers[$(( ${#headers[@]} - 2 ))]}_${_tp_last}"
                    unset 'headers[$(( ${#headers[@]} - 1 ))]'
                    headers=("${headers[@]}")
                fi
                ;;
        esac
    fi

    # --- headerless scaffold split: bash path when its first-row test passes ---
    if [[ "$mode" == HL && $n -ge 2 ]]; then
        _ac_lines_stats "$startidx"
        if [[ $_ACS_TRAG -eq 1 ]]; then
            local _sc_seq=() _sc_pre=-1 _sc_ok=1 _sc_tk _sc_i _sc_a _sc_b
            _fr_tok "${H[$startidx]}"; _sc_tk=("${_FR_TOK[@]}")
            for ((_sc_i = 0; _sc_i < ${#_sc_tk[@]}; _sc_i++)); do
                case "${_sc_tk[$_sc_i]}" in
                    at|on|from|via|dev|to|of|by|for)
                        [[ ${#_sc_seq[@]} -eq 0 ]] && _sc_pre=$_sc_i
                        _sc_seq+=("${_sc_tk[$_sc_i]}") ;;
                esac
            done
            for ((_sc_a = 0; _sc_a < ${#_sc_seq[@]} && _sc_ok == 1; _sc_a++)); do
                for ((_sc_b = _sc_a + 1; _sc_b < ${#_sc_seq[@]}; _sc_b++)); do
                    [[ "${_sc_seq[$_sc_a]}" == "${_sc_seq[$_sc_b]}" ]] && { _sc_ok=0; break; }
                done
            done
            [[ $_sc_ok -eq 1 && ${#_sc_seq[@]} -ge 2 && $_sc_pre -ge 1 ]] && return 3
        fi
    fi

    # --- headerless phrase merge: bash path when it applies ---
    if [[ "$mode" == HL && ${#headers[@]} -ge 3 && $n -ge 2 ]]; then
        local _pm_ok
        _pm_ok=$(awk -v s="$startidx" -v nh="${#headers[@]}" '
            NR <= s { next }
            {
                if (NF != nh || $(nh - 1) !~ /^[a-z]+$/ || $nh !~ /^[a-z]+$/) { bad = 1; exit }
                pr = $(nh - 1) " " $nh
                if (!seen) { first = pr; seen = 1 } else if (pr != first) { bad = 1; exit }
            }
            END { print bad ? 0 : 1 }' "$cur")
        [[ "$_pm_ok" == 1 ]] && return 3
    fi

    # --- emit (the fast path: no phrase merge) ---
    [[ ${#headers[@]} -ge 1 ]] || return 3
    local entry=$(( n - startidx ))
    if [[ $entry -gt 0 ]]; then
        local _hjoin
        _ac_join_tab "${headers[@]}"; _hjoin="$_AC_JOINED"
        awk -v s="$startidx" 'NR > s' "$cur" | _ac_emit_rows "$_hjoin"
        printf 'total_entries %d\n' "$entry"
    fi
    return 0
}

strategy_extract () {
    local text="$1"
    local shape; _ac_shape_v "$text" || { echo ""; return 0; }; shape="$_AC_SHAPE"
    local mode="${shape%% *}" ncols="${shape##* }"

    # Collect non-blank lines (after dropping any `total <n>` preamble).
    # For a HEADED table, a blank line after the header + at least one data
    # row ends the table WHEN a footer legend follows — the next non-blank
    # line is a "KEY = explanation" definition (`systemctl --failed` prints
    # "LOAD = …" lines after a blank). A table that resumes after the blank
    # (faillock's per-user sections) keeps collecting.
    local _raw=() lines=() _l _li
    local _acx_big=0 _acx_o="" _acx_pre=0
    _ACX_F=""
    _ac_body_v "$text"
    (( ${#_AC_BODY} > _FR_BIG_BYTES )) && _acx_big=1
    if [[ $_acx_big -eq 1 ]] && _fr_scratch; then
        # BIG block: the file-to-file path; it hands back (rc 3) only for the
        # bash-only paths, with the collected rows in _ACX_F.
        local _acx_rc=0
        _ac_extract_big "$mode" "$ncols" || _acx_rc=$?
        if [[ $_acx_rc -ne 3 ]]; then _ACX_F=""; return $_acx_rc; fi
        mapfile -t lines < "$_ACX_F"
        _ACX_F=""; _acx_pre=1
    fi
    if [[ $_acx_pre -eq 1 ]]; then
        :   # rows already collected, chrome dropped, wraps merged
    elif [[ $_acx_big -eq 1 ]]; then
        # BIG: the collection loop below in one awk pass (a blank line after
        # enough kept rows arms the footer check; the next non-blank line
        # ends the table when it is a `KEY = …` legend).
        local _acx_need=0
        case "$mode" in HDR) _acx_need=2 ;; HDR2) _acx_need=3 ;; esac
        _acx_o="$(printf '%s\n' "$_AC_BODY" | awk -v need="$_acx_need" '
            $0 !~ /[^ \t\n\v\f\r]/ { if (need > 0 && kept >= need) armed = 1; next }
            { if (armed && index($0, " = ")) exit; armed = 0; kept++; print }'; printf .)"; _fr_split_out "${_acx_o%.}"; _acx_o=""
        lines=(${_FR_OUT[@]+"${_FR_OUT[@]}"}); _FR_OUT=()
    else
    _fr_lines "$_AC_BODY"; _raw=("${_FR_LINES[@]}")
    fi
    [[ $_acx_pre -eq 1 ]] && _raw=()
    for ((_li = 0; _li < ${#_raw[@]}; _li++)); do
        _l="${_raw[$_li]}"
        if [[ "${_l}" != *[![:space:]]* ]]; then
            if [[ ( "$mode" == HDR && ${#lines[@]} -ge 2 ) || ( "$mode" == HDR2 && ${#lines[@]} -ge 3 ) ]]; then
                local _peek="" _pi
                for ((_pi = _li + 1; _pi < ${#_raw[@]}; _pi++)); do
                    [[ "${_raw[$_pi]}" == *[![:space:]]* ]] && { _peek="${_raw[$_pi]}"; break; }
                done
                [[ "$_peek" == *" = "* ]] && break
            fi
            continue
        fi
        lines+=("$_l")
    done

    # Table chrome, not data — drop it here so both the positional and the
    # tokenized paths below see only real rows:
    #   * mid-table HEADER REPEATS (watch/top/vmstat/sar re-print the header
    #     every page/interval) — any later line token-identical to the header,
    #     but only when the header is DIGIT-FREE, the mark of a label row: a
    #     legitimately repeated log/data line ("[app] listening on :8080")
    #     almost always carries a digit and must survive;
    #   * a UNITS ROW printed directly under the header ("(C)  (RPM)  (V)",
    #     "MHz  dBm  dB") — recognised only in that one position, and only when
    #     it has fewer tokens than the header, no digit anywhere, a deeper
    #     indent (its first column is blank), and EVERY token short (≤6 chars)
    #     the way unit labels are. Real data rows carry digits, fill the first
    #     column, or have long values (paths, service names).
    if [[ "$mode" == HDR || "$mode" == HDR2 ]] && [[ ${#lines[@]} -ge 3 && $_acx_pre -eq 0 ]]; then
        local _fhidx=0; [[ "$mode" == HDR2 ]] && _fhidx=1
        local _fharr; _fr_tok "${lines[$_fhidx]}"; _fharr=("${_FR_TOK[@]}")
        local _fhnorm="${_fharr[*]}"
        local _fhind="${lines[$_fhidx]%%[![:space:]]*}"
        # repeat-drop only for a real label row: >=3 tokens (a 2-token log line
        # mistaken for a header must not eat its own repeats) and digit-free —
        # OR digit-bearing but with RARE repeats: sar's timestamped header
        # (`07:00:01  CPU  %user …`) re-prints each interval, and those exact
        # repeats are chrome even though the timestamp carries digits. The
        # rarity gate (repeats <= 1/4 of data rows) is what separates that from
        # a block dominated by one legitimately repeated log line (entr), where
        # the repeats ARE the data and must survive.
        local _fhdrfree=1
        # (BIG: the token-normalised form of every row, one awk pass — the
        # `${arr[*]}` join of _fr_tok's words is the row's fields joined by
        # one space)
        local _acx_norm='{ s = ""; for (k = 1; k <= NF; k++) s = (k > 1) ? s " " $k : $k }'
        if [[ ${#_fharr[@]} -lt 3 ]]; then
            _fhdrfree=0
        elif [[ "${lines[$_fhidx]}" =~ [0-9] ]]; then
            local _frep=0 _ftot=0 _fj _fjarr
            if [[ $_acx_big -eq 1 ]]; then
                read -r _frep _ftot < <(printf '%s\n' "${lines[@]:$((_fhidx + 1))}" \
                    | _ACX_H="$_fhnorm" awk "$_acx_norm"' { tot++; if (s == ENVIRON["_ACX_H"]) rep++ }
                        END { printf "%d %d\n", rep, tot }')
                [[ $((_fhidx + 1)) -ge ${#lines[@]} ]] && { _frep=0; _ftot=0; }
            else
            for ((_fj = _fhidx + 1; _fj < ${#lines[@]}; _fj++)); do
                _ftot=$((_ftot + 1))
                _fr_tok "${lines[$_fj]}"; _fjarr=("${_FR_TOK[@]}")
                [[ "${_fjarr[*]}" == "$_fhnorm" ]] && _frep=$((_frep + 1))
            done
            fi
            [[ $_frep -eq 0 || $_ftot -eq 0 || $((_frep * 4)) -gt $_ftot ]] && _fhdrfree=0
        fi
        local _fout=() _fi _farr _fnorm _fdind _ft _ftok
        local _acx_n=${#lines[@]}
        if [[ $_acx_big -eq 1 ]]; then
            # BIG: decide the one units-row candidate (row _fhidx+1) here,
            # then let one awk pass drop header repeats (and that row).
            local _acx_dropu=0
            _fi=$((_fhidx + 1))
            _fr_tok "${lines[$_fi]}"; _farr=("${_FR_TOK[@]}")
            _fnorm="${_farr[*]}"
            if ! [[ $_fhdrfree -eq 1 && "$_fnorm" == "$_fhnorm" ]] \
               && [[ ${#_farr[@]} -lt ${#_fharr[@]} && ${#_farr[@]} -ge 2 && ! "${lines[$_fi]}" =~ [0-9] ]]; then
                _fdind="${lines[$_fi]%%[![:space:]]*}"
                if [[ ${#_fdind} -gt ${#_fhind} ]]; then
                    _ft=1
                    for _ftok in "${_farr[@]}"; do
                        [[ ${#_ftok} -gt 6 ]] && { _ft=0; break; }
                        if [[ "$_ftok" == "("*")" ]]; then continue; fi
                        [[ "$_ftok" == *[A-Z]* && "$_ftok" == *[a-z]* ]] || { _ft=0; break; }
                    done
                    [[ $_ft -eq 1 ]] && _acx_dropu=1
                fi
            fi
            _acx_o="$(printf '%s\n' "${lines[@]}" \
                | _ACX_H="$_fhnorm" awk -v hidx="$_fhidx" -v free="$_fhdrfree" -v dropu="$_acx_dropu" "$_acx_norm"'
                    {
                        i = NR - 1
                        if (i > hidx) {
                            if (free && s == ENVIRON["_ACX_H"]) next
                            if (i == hidx + 1 && dropu) next
                        }
                        print
                    }'; printf .)"; _fr_split_out "${_acx_o%.}"; _acx_o=""
            lines=(${_FR_OUT[@]+"${_FR_OUT[@]}"}); _FR_OUT=()
            _acx_n=0
        fi
        for ((_fi = 0; _fi < _acx_n; _fi++)); do
            if [[ $_fi -gt $_fhidx ]]; then
                _fr_tok "${lines[$_fi]}"; _farr=("${_FR_TOK[@]}")
                _fnorm="${_farr[*]}"
                [[ $_fhdrfree -eq 1 && "$_fnorm" == "$_fhnorm" ]] && continue
                if [[ $_fi -eq $((_fhidx + 1)) && ${#_farr[@]} -lt ${#_fharr[@]} \
                      && ${#_farr[@]} -ge 2 && ! "${lines[$_fi]}" =~ [0-9] ]]; then
                    _fdind="${lines[$_fi]%%[![:space:]]*}"
                    if [[ ${#_fdind} -gt ${#_fhind} ]]; then
                        # every token must LOOK like a unit label: parenthesized
                        # ("(C)", "(RPM)") or case-mixed the way unit symbols are
                        # ("MHz", "dBm", "GiB") — an all-lowercase data row with an
                        # empty first cell ("web  db  allow") is data, not units
                        _ft=1
                        for _ftok in "${_farr[@]}"; do
                            [[ ${#_ftok} -gt 6 ]] && { _ft=0; break; }
                            if [[ "$_ftok" == "("*")" ]]; then continue; fi
                            [[ "$_ftok" == *[A-Z]* && "$_ftok" == *[a-z]* ]] || { _ft=0; break; }
                        done
                        [[ $_ft -eq 1 ]] && continue
                    fi
                fi
            fi
            _fout+=("${lines[$_fi]}")
        done
        [[ $_acx_big -eq 1 ]] || lines=("${_fout[@]}")
    fi

    # FIRST-CELL WRAP: a data row that is a LONE token, followed by an INDENTED
    # row exactly one column short, is a value too long for column 1 printed on
    # its own line (df's `/dev/mapper/vg-root` over an indented `98G 45G …`) —
    # merge the pair into one row. Gated on a headed table with >=4 columns so
    # narrow key/value layouts never pair-merge.
    if [[ $_acx_pre -eq 1 ]]; then
        :
    elif [[ "$mode" == HDR && $ncols -ge 4 && ${#lines[@]} -ge 3 && $_acx_big -eq 1 ]]; then
        # BIG: the pair-merge loop below in one awk pass (all rows buffered
        # for the one-row lookahead)
        _acx_o="$(printf '%s\n' "${lines[@]}" | awk -v ncols="$ncols" '
            { L[NR] = $0; T[NR] = NF }
            END {
                for (i = 1; i <= NR; i++) {
                    if (i > 1 && i < NR && T[i] == 1) {
                        m = 1 + T[i + 1]
                        c = substr(L[i + 1], 1, 1)
                        if (m >= ncols - 1 && m <= ncols && (c == " " || c == "\t")) {
                            n = split(L[i], a); r = a[1]
                            n = split(L[i + 1], b)
                            for (k = 1; k <= n; k++) r = r " " b[k]
                            print r
                            i++
                            continue
                        }
                    }
                    print L[i]
                }
            }'; printf .)"; _fr_split_out "${_acx_o%.}"; _acx_o=""
        lines=(${_FR_OUT[@]+"${_FR_OUT[@]}"}); _FR_OUT=()
    elif [[ "$mode" == HDR && $ncols -ge 4 && ${#lines[@]} -ge 3 ]]; then
        local _mw=() _mi _mt1 _mt2
        for ((_mi = 0; _mi < ${#lines[@]}; _mi++)); do
            if [[ $_mi -gt 0 && $((_mi + 1)) -lt ${#lines[@]} ]]; then
                _fr_tok "${lines[$_mi]}"; _mt1=("${_FR_TOK[@]}")
                if [[ ${#_mt1[@]} -eq 1 ]]; then
                    _fr_tok "${lines[$((_mi + 1))]}"; _mt2=("${_FR_TOK[@]}")
                    # merged pair must land on a full row: ncols tokens, or one
                    # short of it (a multi-word header label like `Mounted on`
                    # makes ncols one higher than any data row)
                    if [[ $((1 + ${#_mt2[@]})) -ge $((ncols - 1)) && $((1 + ${#_mt2[@]})) -le $ncols \
                          && "${lines[$((_mi + 1))]}" == [' 	']* ]]; then
                        _mw+=("${_mt1[0]} ${_mt2[*]}")
                        _mi=$((_mi + 1))
                        continue
                    fi
                fi
            fi
            _mw+=("${lines[$_mi]}")
        done
        lines=("${_mw[@]}")
    fi

    # For a cleanly-aligned HDR/HDR2 table, use positional token assignment so
    # multi-word headers/values (docker `IMAGE ID` / `2 weeks ago`, kubectl PORTS
    # `80, 443`) survive. Everything else keeps whitespace tokenization.
    if [[ "$mode" == HDR || "$mode" == HDR2 ]]; then
        local hidx=0; [[ "$mode" == HDR2 ]] && hidx=1
        # (printf -v + trailing-newline strip == the old `$(printf …)` capture)
        local hd; printf -v hd '%s\n' "${lines[@]:$hidx}"
        if [[ $_acx_big -eq 1 ]]; then
            # (trailing newlines counted from the end: the `##*[!…]` suffix
            # scan walks the whole big string)
            local _hdn=0
            while (( _hdn < ${#hd} )) && [[ "${hd: -$((_hdn + 1)):1}" == $'\n' ]]; do _hdn=$((_hdn + 1)); done
            hd="${hd:0:$(( ${#hd} - _hdn ))}"
        else
            hd="${hd%"${hd##*[!$'\n']}"}"
        fi
        # Positional assignment only helps when a data cell is multi-word (docker
        # "2 hours ago", helm's timestamp) — i.e. data rows carry MORE whitespace
        # tokens than the header has labels. When every cell is a single token
        # (df, lsblk, ss, elasticsearch), the header's 2-space segmentation can
        # UNDER-count columns (single-spaced labels like df's "Used Avail Use%"),
        # so positional would cram them; whitespace tokenization is correct there.
        local _htok _harr; _fr_tok "${lines[$hidx]}"; _harr=("${_FR_TOK[@]}"); _htok=${#_harr[@]}
        local _maxd=0 _dli _darr _dcnt=()
        # Modal data-row token count.
        local _moded=0 _mdbest=0
        if [[ $_acx_big -eq 1 ]]; then
            _ac_lines_stats $((hidx + 1))
            _maxd=$_ACS_TMAX; _moded=$_ACS_TMOD; _mdbest=$_ACS_TMODN
        else
        for ((_dli = hidx + 1; _dli < ${#lines[@]}; _dli++)); do
            _fr_tok "${lines[$_dli]}"; _darr=("${_FR_TOK[@]}")
            [[ ${#_darr[@]} -gt $_maxd ]] && _maxd=${#_darr[@]}
            _dcnt+=("${#_darr[@]}")
        done
        _fr_modal ${_dcnt[@]+"${_dcnt[@]}"}; _moded=$_FR_MODE; _mdbest=$_FR_MODE_N
        fi
        # In an ALL-TEXT table (no digits anywhere) the reverse mismatch also
        # wants positional assignment: a header with MORE tokens than the data
        # rows means multi-word labels (`Service Name`), which 2-space
        # segmentation names as one column. Numeric tables keep tokenization
        # (their single-spaced labels under-segment) UNLESS the header's own
        # 2-space segmentation collapses EXACTLY to the data column count — a
        # genuine multi-word-header table (STREAM's "Best Rate MB/s", docker's
        # "IMAGE ID"). That equality is the safety: single-spaced labels (df's
        # "Used Avail Use%") under-segment and so never match.
        local _use_pos=0
        if [[ $_maxd -gt $_htok ]]; then _use_pos=1
        elif [[ $_htok -ge 3 ]] && _ac_sparse_grid "$hd"; then
            # a sparse matrix: cells belong to the label above them, not to
            # the next free column
            _use_pos=1
        elif [[ $_htok -gt $_maxd ]]; then
            local _alljoin _acx_nodig=0
            if [[ $_acx_big -eq 1 ]]; then
                # any digit in ANY row (header rows included): lines[0..]
                _ac_lines_stats 0; [[ $_ACS_DIGIT -eq 0 ]] && _acx_nodig=1
            else
                printf -v _alljoin '%s\n' "${lines[@]}"
                [[ ! "$_alljoin" =~ [0-9] ]] && _acx_nodig=1
            fi
            if [[ $_acx_nodig -eq 1 ]]; then _use_pos=1
            else
                local _hseg; _ac_seg_v "${lines[$hidx]}"; _hseg="$_AC_SEG"
                [[ $_hseg -ge 2 && $_hseg -eq $_moded ]] && _use_pos=1
            fi
        else
            # EQUAL token counts can still hide multi-word labels AND multi-word
            # values in the same table ("Property Name … Group" over
            # "www.example.com … Web Delivery" — 8 tokens each). The tell: the
            # header's 2-space segmentation collapses BELOW its token count
            # (multi-word labels exist) while the DATA rows segment the same
            # way the header does. Data that segments more finely than the
            # header (pam-tally2, ip6tables — their own 2-space runs mark MORE
            # columns than the header shows) is telling us the single-spaced
            # header under-segments, and tokenization is the right reading.
            local _hsegq; _ac_seg_v "${lines[$hidx]}"; _hsegq="$_AC_SEG"
            if [[ $_hsegq -ge 2 && $_hsegq -lt $_htok ]]; then
                local _dsegc=() _dsi _dsbest=0 _dsmod=0
                if [[ $_acx_big -eq 1 ]]; then
                    _ac_lines_stats $((hidx + 1)); _dsmod=$_ACS_SMOD; _dsbest=$_ACS_SMODN
                else
                for ((_dsi = hidx + 1; _dsi < ${#lines[@]}; _dsi++)); do
                    _ac_seg_v "${lines[$_dsi]}"; _dsegc+=("$_AC_SEG")
                done
                _fr_modal ${_dsegc[@]+"${_dsegc[@]}"}; _dsmod=$_FR_MODE; _dsbest=$_FR_MODE_N
                fi
                [[ $_dsmod -eq $_hsegq ]] && _use_pos=1
            fi
        fi
        # Route lightly-non-ASCII blocks (<20% multibyte chars) through the
        # char-accurate bash grid; everything else through the awk grid.
        # Only NARROW 2-byte chars qualify (±, µ, é): emoji/CJK/box-drawing
        # (3-4 byte, double-width), soft hyphens (zero-width) and combining
        # marks all break the char==display-column assumption, so those
        # blocks keep the awk path.
        local _mb_grid=""
        if [[ $_use_pos -eq 1 && "$hd" == *[![:ascii:]]* ]]; then
            local _mb_ascii="${hd//[![:ascii:]]/}"
            local _mb_wide=0
            case "$hd" in
                *$'\xe0'*|*$'\xe1'*|*$'\xe2'*|*$'\xe3'*|*$'\xe4'*|*$'\xe5'*|*$'\xe6'*|*$'\xe7'*|*$'\xe8'*|*$'\xe9'*|*$'\xea'*|*$'\xeb'*|*$'\xec'*|*$'\xed'*|*$'\xee'*|*$'\xef'*|*$'\xf0'*|*$'\xf1'*|*$'\xf2'*|*$'\xf3'*|*$'\xf4'*) _mb_wide=1 ;;
            esac
            case "$hd" in
                *$'\xc2\xad'*|*$'\xcc'*|*$'\xcd'*) _mb_wide=1 ;;
            esac
            if [[ $_mb_wide -eq 0 ]] && (( (${#hd} - ${#_mb_ascii}) * 5 < ${#hd} )); then
                _mb_grid="$(printf '%s' "$hd" | _ac_grid_mb)" || _mb_grid=""
            fi
        fi
        if [[ $_use_pos -eq 1 ]] && { [[ -n "$_mb_grid" ]] || [[ "$(printf '%s' "$hd" | _ac_aligned)" == "1" ]]; }; then
            local gridrows=() _g
            if [[ -n "$_mb_grid" ]]; then
                _fr_lines "$_mb_grid"; gridrows=("${_FR_LINES[@]}")
            else
                # Captured whole (bulk read) instead of read line-by-line from a
                # process-substitution pipe (one read(2) per byte).
                _g="$(printf '%s' "$hd" | _ac_assign; printf .)"
                _ac_stream_lines "${_g%.}"; gridrows=(${_FR_LINES[@]+"${_FR_LINES[@]}"})
            fi
            if [[ ${#gridrows[@]} -ge 2 ]]; then
                # Tab-SAFE cell split: `IFS=$'\t' read -ra` treats TAB as IFS
                # whitespace, so leading/consecutive tabs COLLAPSE and an empty
                # leading cell shifts every value left. Split explicitly.
                _ac_cells () {
                    local _s="$1"; _AC_CELLS=()
                    while [[ "$_s" == *$'\t'* ]]; do
                        _AC_CELLS+=("${_s%%$'\t'*}"); _s="${_s#*$'\t'}"
                    done
                    _AC_CELLS+=("$_s")
                }
                # WRAPPED CELLS: rejoin continuation lines before emitting.
                #   * tail wrap — a grid row whose FIRST cell is empty and whose
                #     only content sits in the LAST cell is the previous row's
                #     last column wrapped onto a new line (kubectl events'
                #     MESSAGE, systemctl's DESCRIPTION, crontab COMMAND): append
                #     it, space-joined. A sparse-matrix row keeps its row label,
                #     so first-cell-empty + only-last-cell never fires there.
                #   * leading overflow — a grid row with ONLY its first cell
                #     filled, when the NEXT row's first cell is empty, is a value
                #     too long for column 1 printed alone (df's long device
                #     path): carry it into the next row's first cell.
                local _wj=() _wr _wc=() _wn _wonly_last _wonly_first _wnc
                for ((_wr = 1; _wr < ${#gridrows[@]}; _wr++)); do
                    _ac_cells "${gridrows[$_wr]}"; _wc=("${_AC_CELLS[@]}")
                    _wnc=${#_wc[@]}
                    _wonly_last=0; _wonly_first=0
                    if [[ $_wnc -ge 2 ]]; then
                        local _wi _wfilled=0 _wlastfill=0 _wfirstfill=0
                        for ((_wi = 0; _wi < _wnc; _wi++)); do
                            [[ "${_wc[$_wi]}" == *[![:space:]]* ]] || continue
                            _wfilled=$((_wfilled + 1))
                            [[ $_wi -eq $((_wnc - 1)) ]] && _wlastfill=1
                            [[ $_wi -eq 0 ]] && _wfirstfill=1
                        done
                        [[ $_wfilled -eq 1 && $_wlastfill -eq 1 ]] && _wonly_last=1
                        [[ $_wfilled -eq 1 && $_wfirstfill -eq 1 ]] && _wonly_first=1
                    fi
                    if [[ $_wonly_last -eq 1 && ${#_wj[@]} -gt 0 ]]; then
                        # append to previous kept row's last cell
                        local _wprev=() _wpi=$(( ${#_wj[@]} - 1 ))
                        _ac_cells "${_wj[$_wpi]}"; _wprev=("${_AC_CELLS[@]}")
                        _wprev[$((${#_wprev[@]} - 1))]="${_wprev[$((${#_wprev[@]} - 1))]:+${_wprev[$((${#_wprev[@]} - 1))]} }${_wc[$((_wnc - 1))]}"
                        _ac_join_tab "${_wprev[@]}"; _wj[$_wpi]="$_AC_JOINED"
                        continue
                    fi
                    if [[ $_wonly_first -eq 1 && $((_wr + 1)) -lt ${#gridrows[@]} ]]; then
                        local _wnext=(); _ac_cells "${gridrows[$((_wr + 1))]}"; _wnext=("${_AC_CELLS[@]}")
                        if [[ ${#_wnext[@]} -ge 2 && "${_wnext[0]}" != *[![:space:]]* ]]; then
                            _wnext[0]="${_wc[0]}"
                            _ac_join_tab "${_wnext[@]}"; gridrows[$((_wr + 1))]="$_AC_JOINED"
                            continue
                        fi
                    fi
                    _wj+=("${gridrows[$_wr]}")
                done
                gridrows=("${gridrows[0]}" "${_wj[@]}")

                local headers=() result="" entry=0 li i
                # Tab-SAFE header split too: the ragged-alignment mb grid can
                # emit EMPTY leading/interior header cells (asv's unnamed sign
                # column) — IFS-tab read would strip them and shift every name
                # left. Empty cells fall through to the letter fallback below.
                _ac_cells "${gridrows[0]}"; headers=("${_AC_CELLS[@]}")
                for ((i = 0; i < ${#headers[@]}; i++)); do
                    local h="${headers[$i]//./_}"; h="${h// /_}"
                    while [[ "$h" == *__* ]]; do h="${h//__/_}"; done
                    h="${h#_}"; h="${h%_}"; [[ -z "$h" ]] && { _fr_col_letter $((i + 1)); h="$_FR_LETTER"; }
                    headers[$i]="$h"
                done
                local _resl=()
                for ((li = 1; li < ${#gridrows[@]}; li++)); do
                    local values; _ac_cells "${gridrows[$li]}"; values=("${_AC_CELLS[@]}")
                    local nonempty=0 v
                    for v in "${values[@]}"; do [[ "${v}" == *[![:space:]]* ]] && { nonempty=1; break; }; done
                    [[ $nonempty -eq 0 ]] && continue
                    entry=$((entry + 1))
                    for ((i = 0; i < ${#headers[@]}; i++)); do
                        local name="${headers[$i]}" value="${values[$i]:-}"
                        [[ -z "$value" ]] && continue
                        _resl+=("entry${entry}.${name} ${value}")
                    done
                done
                [[ $entry -gt 0 ]] && _resl+=("total_entries ${entry}")
                [[ ${#_resl[@]} -gt 0 ]] && printf -v result '%s\n' "${_resl[@]}"
                echo "$result"; return 0
            fi
        fi
    fi

    # Segment-split fallback for right-aligned space-in-value tables (ceph osd df's
    # "1.0 TiB" under a "RAW USE" multi-word header; supervisorctl's "pid 8821,
    # uptime 2:14:08"). Positional assignment above couldn't align these (their
    # values are right-justified, so a value's start falls under the WRONG header
    # column). Splitting on >=2-space gaps instead keeps each multi-word cell whole.
    # Fires only for a PERFECTLY regular segmentation table (every non-blank line
    # has the same >=2 segment count) that actually carries a multi-word cell
    # (some row's whitespace-token count exceeds the segment count) — so a normal
    # single-token table, already correct via tokenization, is never touched.
    # HDR-only: a headed table's header row fixes the true column count, so
    # rejoining segments is unambiguous. Headerless log records (who/last, whose
    # "date time (host)" trailing field the established tidy splits into columns)
    # are deliberately excluded — there is no header to say the field is one cell.
    if [[ "$mode" == HDR ]] && [[ ${#lines[@]} -ge 2 ]]; then
        local _sS="" _sok=1 _si _sarr _ss _sw _shw=0 _sdw=()
        local _smod=0 _sbest=0 _acx_sn=${#lines[@]}
        if [[ $_acx_big -eq 1 ]]; then
            # BIG: same verdicts from two awk aggregates (every row's
            # segment count equal to row 0's; modal data-row token count)
            _ac_lines_stats 0
            _sok=$_ACS_SSAME; _sS=$_ACS_SFIRST; _shw=$_ACS_TFIRST
            _ac_lines_stats 1
            _smod=$_ACS_TMOD; _sbest=$_ACS_TMODN
            _acx_sn=0
        fi
        for ((_si = 0; _si < _acx_sn; _si++)); do
            _ac_seg_v "${lines[$_si]}"; _ss="$_AC_SEG"
            _fr_tok "${lines[$_si]}"; _sarr=("${_FR_TOK[@]}"); _sw=${#_sarr[@]}
            [[ $_si -eq 0 ]] && _shw=$_sw || _sdw+=("$_sw")
            [[ -z "$_sS" ]] && _sS="$_ss"
            [[ "$_ss" -ne "$_sS" ]] && { _sok=0; break; }
        done
        # Modal (not max) data-row whitespace-token count: robust to a single
        # ragged row. seg-split is right ONLY when data cells carry inner spaces —
        # i.e. the typical data row has MORE whitespace tokens than the header has
        # labels ("1.0 TiB" is 2 tokens in 1 column). When they're EQUAL, the
        # columns are single-token and tokenization is already correct, even if a
        # header label happens to be single-spaced (ps -ef's "C STIME TTY" — three
        # narrow columns, not one multi-word cell). That equality is the guard that
        # keeps single-space-delimited fixed tables on tokenization.
        if [[ $_acx_big -eq 0 ]]; then
        _fr_modal ${_sdw[@]+"${_sdw[@]}"}; _smod=$_FR_MODE; _sbest=$_FR_MODE_N
        fi
        # ...or when the header REPEATS a token (`Mean [ms]  Min [ms]  Max
        # [ms]` — hyperfine): repeated names are multi-word labels tokenized
        # apart, and tokenization would collide them and drop columns.
        local _sdup=0
        if [[ $_sok -eq 1 && $_sS -ge 2 && $_smod -le $_shw ]]; then
            local -A _sdseen=(); local _sdt
            _fr_tok "${lines[0]}"
            for _sdt in "${_FR_TOK[@]}"; do
                [[ -n "${_sdseen[$_sdt]:-}" ]] && { _sdup=1; break; }
                _sdseen[$_sdt]=1
            done
        fi
        if [[ $_sok -eq 1 && $_sS -ge 2 && ( $_smod -gt $_shw || $_sdup -eq 1 ) ]]; then
            # mode==HDR guarantees a header row: split it on the same >=2-space
            # boundaries and use its cells as column names ("RAW USE" -> RAW_USE).
            local _sgrid=() _sg
            _sg="$(printf '%s\n' "${lines[@]}" | _ac_split; printf .)"
            _ac_stream_lines "${_sg%.}"; _sgrid=(${_FR_LINES[@]+"${_FR_LINES[@]}"})
            local _sheaders=() _sstart=1
            IFS=$'\t' _fr_tok "${_sgrid[0]}"; _sheaders=("${_FR_TOK[@]}")
            for ((_si = 0; _si < ${#_sheaders[@]}; _si++)); do
                local _sh="${_sheaders[$_si]//./_}"; _sh="${_sh// /_}"
                while [[ "$_sh" == *__* ]]; do _sh="${_sh//__/_}"; done
                _sh="${_sh#_}"; _sh="${_sh%_}"; [[ -z "$_sh" ]] && { _fr_col_letter $((_si + 1)); _sh="$_FR_LETTER"; }
                _sheaders[$_si]="$_sh"
            done
            local _sresult="" _sentry=0 _sli _sresl=()
            for ((_sli = _sstart; _sli < ${#_sgrid[@]}; _sli++)); do
                local _svals=(); IFS=$'\t' _fr_tok "${_sgrid[$_sli]}"; _svals=("${_FR_TOK[@]}")
                local _sne=0 _sv
                for _sv in "${_svals[@]}"; do [[ "${_sv}" == *[![:space:]]* ]] && { _sne=1; break; }; done
                [[ $_sne -eq 0 ]] && continue
                _sentry=$((_sentry + 1))
                for ((_si = 0; _si < ${#_sheaders[@]}; _si++)); do
                    local _sname="${_sheaders[$_si]}" _sval="${_svals[$_si]:-}"
                    [[ -z "$_sval" ]] && continue
                    _sresl+=("entry${_sentry}.${_sname} ${_sval}")
                done
            done
            if [[ $_sentry -gt 0 ]]; then
                _sresl+=("total_entries ${_sentry}")
                printf -v _sresult '%s\n' "${_sresl[@]}"
                echo "$_sresult"; return 0
            fi
        fi
    fi

    # OFFSET ASSIGNMENT for SPARSE tables. When data rows carry FEWER tokens
    # than the header names columns, whitespace tokenization assigns the
    # surviving values to the FIRST header names rather than their own:
    # `lsblk -f` (five of eight columns empty on every row) put sizes under
    # FSTYPE and mountpoints under LABEL, and `lsof` put USER under TID — and
    # nothing in the output betrays the error, which is what makes this the
    # most insidious defect the held-out benchmark found. The header's
    # CHARACTER OFFSETS say which column a value belongs to; use them.
    #
    # Each data token goes to the header token whose printed span it overlaps
    # most (nearest span when a right-aligned value pokes out); everything at
    # or past the last header's start joins the last column, which is where
    # free-text tails (lsof's NAME) live. The whole parse is buffered and
    # WITHDRAWN unless >=80% of data tokens actually overlap a header span —
    # a table that is not genuinely offset-aligned falls through to the
    # tokenized path below exactly as before.
    if [[ "$mode" == HDR && ${#lines[@]} -ge 3 ]]; then
        local _oa_h; _fr_tok "${lines[0]}"; _oa_h=("${_FR_TOK[@]}")
        if [[ ${#_oa_h[@]} -ge 4 ]]; then
            # Modal data-row token count, and raggedness.
            local _oa_cnt=() _oa_i _oa_t _oa_mod=0 _oa_ba _oa_bb _oa_bk _oa_best=0
            if [[ $_acx_big -eq 1 ]]; then
                _ac_lines_stats 1; _oa_mod=$_ACS_TMOD; _oa_best=$_ACS_TMODN
            else
            for ((_oa_i = 1; _oa_i < ${#lines[@]}; _oa_i++)); do
                _fr_tok "${lines[$_oa_i]}"; _oa_t=("${_FR_TOK[@]}")
                _oa_cnt+=("${#_oa_t[@]}")
            done
            _fr_modal ${_oa_cnt[@]+"${_oa_cnt[@]}"}; _oa_mod=$_FR_MODE; _oa_best=$_FR_MODE_N
            fi
            if [[ $_oa_mod -lt ${#_oa_h[@]} && $_oa_mod -ge 1 ]]; then
                local _oa_out
                _oa_out=$(printf '%s\n' "${lines[@]}" | awk "$_AC_AWK_OFFSET")
                if [[ -n "$_oa_out" ]]; then
                    echo "$_oa_out"; return 0
                fi
            fi
        fi
    fi

    # Header names: the header line's tokens (HDR/HDR2), or synthetic c1..cN (HL).
    local headers=() startidx=0 i
    case "$mode" in
        HDR)  _fr_tok "${lines[0]}"; headers=("${_FR_TOK[@]}"); startidx=1 ;;
        HDR2) _fr_tok "${lines[1]}"; headers=("${_FR_TOK[@]}"); startidx=2 ;;
        HL)   for ((i = 1; i <= ncols; i++)); do _fr_col_letter "$i"; headers+=("$_FR_LETTER"); done; startidx=0 ;;
    esac
    _ac_group_prefix
    # Field names must not contain '.' (the tidy melt splits entry<N>.<field> on
    # the first dot).
    for ((i = 0; i < ${#headers[@]}; i++)); do headers[$i]="${headers[$i]//./_}"; done

    # A TRAILING PREPOSITION in the header is the tail of a two-word label,
    # not a column: df's `Mounted on` tokenizes as two names, the data rows
    # run one token short, and the last real value landed under `Mounted`
    # with `on` forever empty — silently truncating the label. When the data
    # rows are exactly one short and the last header token is such a word,
    # weld it onto its neighbour (`Mounted_on`).
    if [[ ( "$mode" == HDR || "$mode" == HDR2 ) && ${#headers[@]} -ge 3 ]]; then
        local _tp_last="${headers[$(( ${#headers[@]} - 1 ))]}"
        local _tp_lc="${_tp_last,,}"
        case "$_tp_lc" in
            on|by|in|at|of|to)
                local _tp_cnt=() _tp_i _tp_t _tp_mod=0 _tp_a _tp_b _tp_k _tp_best=0
                if [[ $_acx_big -eq 1 ]]; then
                    _ac_lines_stats "$startidx"; _tp_mod=$_ACS_TMOD; _tp_best=$_ACS_TMODN
                else
                for ((_tp_i = startidx; _tp_i < ${#lines[@]}; _tp_i++)); do
                    _fr_tok "${lines[$_tp_i]}"; _tp_t=("${_FR_TOK[@]}")
                    _tp_cnt+=("${#_tp_t[@]}")
                done
                _fr_modal ${_tp_cnt[@]+"${_tp_cnt[@]}"}; _tp_mod=$_FR_MODE; _tp_best=$_FR_MODE_N
                fi
                if [[ $_tp_mod -eq $(( ${#headers[@]} - 1 )) ]]; then
                    headers[$(( ${#headers[@]} - 2 ))]="${headers[$(( ${#headers[@]} - 2 ))]}_${_tp_last}"
                    unset 'headers[$(( ${#headers[@]} - 1 ))]'
                    headers=("${headers[@]}")
                fi
                ;;
        esac
    fi

    # SCAFFOLD SPLIT: headerless RAGGED rows sharing >=2 function words
    # (`? (ip) at MAC [ether] on eth0` / `? (ip) at <incomplete> on eth0`,
    # arp -an) are sentence-records, and per-position columns misalign the
    # moment an optional field is absent. The constant function words are the
    # real field boundaries: split there, name each following segment after
    # its scaffold word, and keep multi-token segments as ONE cell. Fires
    # only when every row carries the SAME allowlisted words (at on from via
    # dev to of by for), each exactly once, in the same order, with a uniform
    # prefix width — so ordinary uniform tables and ip-route-style blocks
    # (word sets differ per row) never enter.
    if [[ "$mode" == HL && ${#lines[@]} -ge 2 ]]; then
        local _sc_r _sc_tk _sc_w0=-1 _sc_ragged=0
        if [[ $_acx_big -eq 1 ]]; then
            _ac_lines_stats "$startidx"; _sc_ragged=$_ACS_TRAG
        else
        for ((_sc_r = startidx; _sc_r < ${#lines[@]}; _sc_r++)); do
            _fr_tok "${lines[$_sc_r]}"; _sc_tk=("${_FR_TOK[@]}")
            [[ $_sc_w0 -lt 0 ]] && _sc_w0=${#_sc_tk[@]}
            [[ ${#_sc_tk[@]} -ne $_sc_w0 ]] && _sc_ragged=1
        done
        fi
        if [[ $_sc_ragged -eq 1 ]]; then
            local _sc_seq=() _sc_pre=-1 _sc_ok=1 _sc_t _sc_i
            _fr_tok "${lines[$startidx]}"; _sc_tk=("${_FR_TOK[@]}")
            for ((_sc_i = 0; _sc_i < ${#_sc_tk[@]}; _sc_i++)); do
                case "${_sc_tk[$_sc_i]}" in
                    at|on|from|via|dev|to|of|by|for)
                        [[ ${#_sc_seq[@]} -eq 0 ]] && _sc_pre=$_sc_i
                        _sc_seq+=("${_sc_tk[$_sc_i]}") ;;
                esac
            done
            local _sc_a _sc_b
            for ((_sc_a = 0; _sc_a < ${#_sc_seq[@]} && _sc_ok == 1; _sc_a++)); do
                for ((_sc_b = _sc_a + 1; _sc_b < ${#_sc_seq[@]}; _sc_b++)); do
                    [[ "${_sc_seq[$_sc_a]}" == "${_sc_seq[$_sc_b]}" ]] && { _sc_ok=0; break; }
                done
            done
            if [[ $_sc_ok -eq 1 && ${#_sc_seq[@]} -ge 2 && $_sc_pre -ge 1 ]]; then
                # verify every row: same words, same order, exactly once,
                # same prefix width
                local _sc_rows=()
                for ((_sc_r = startidx; _sc_r < ${#lines[@]} && _sc_ok == 1; _sc_r++)); do
                    _fr_tok "${lines[$_sc_r]}"; _sc_tk=("${_FR_TOK[@]}")
                    local _sc_found=() _sc_fpre=-1
                    for ((_sc_i = 0; _sc_i < ${#_sc_tk[@]}; _sc_i++)); do
                        case "${_sc_tk[$_sc_i]}" in
                            at|on|from|via|dev|to|of|by|for)
                                [[ ${#_sc_found[@]} -eq 0 ]] && _sc_fpre=$_sc_i
                                _sc_found+=("${_sc_tk[$_sc_i]}") ;;
                        esac
                    done
                    [[ "${_sc_found[*]}" == "${_sc_seq[*]}" && $_sc_fpre -eq $_sc_pre ]] || _sc_ok=0
                done
                if [[ $_sc_ok -eq 1 ]]; then
                    local _sc_res="" _sc_e=0
                    for ((_sc_r = startidx; _sc_r < ${#lines[@]}; _sc_r++)); do
                        _fr_tok "${lines[$_sc_r]}"; _sc_tk=("${_FR_TOK[@]}")
                        _sc_e=$((_sc_e + 1))
                        for ((_sc_i = 0; _sc_i < _sc_pre; _sc_i++)); do
                            _fr_col_letter $((_sc_i + 1))
                            _sc_res+="entry${_sc_e}.${_FR_LETTER} ${_sc_tk[$_sc_i]}"$'\n'
                        done
                        local _sc_name="" _sc_val=""
                        for ((_sc_i = _sc_pre; _sc_i < ${#_sc_tk[@]}; _sc_i++)); do
                            local _sc_isword=0
                            case "${_sc_tk[$_sc_i]}" in
                                at|on|from|via|dev|to|of|by|for) _sc_isword=1 ;;
                            esac
                            if [[ $_sc_isword -eq 1 ]]; then
                                [[ -n "$_sc_name" && -n "$_sc_val" ]] && _sc_res+="entry${_sc_e}.${_sc_name} ${_sc_val}"$'\n'
                                _sc_name="${_sc_tk[$_sc_i]}"; _sc_val=""
                            else
                                _sc_val+="${_sc_val:+ }${_sc_tk[$_sc_i]}"
                            fi
                        done
                        [[ -n "$_sc_name" && -n "$_sc_val" ]] && _sc_res+="entry${_sc_e}.${_sc_name} ${_sc_val}"$'\n'
                    done
                    if [[ $_sc_e -gt 0 ]]; then
                        _sc_res+="total_entries ${_sc_e}"$'\n'
                        echo "$_sc_res"; return 0
                    fi
                fi
            fi
        fi
    fi

    # HEADERLESS PHRASE MERGE: with no header to say otherwise, the TRAILING
    # pair of columns holding the SAME two lowercase words on every row
    # ("not confined" split into C/D — aa-unconfined) is one status phrase,
    # not two columns. Trailing-only: a constant mid-table word pair is a
    # real pair of columns that happens to be constant (`ls -l`'s owner and
    # group, masscan's "open port"), so only the LAST pair may merge. Both
    # cells pure lowercase alpha, identical down the whole table, every row
    # full-width.
    local _pm_join=()
    if [[ "$mode" == HL && ${#headers[@]} -ge 3 && ${#lines[@]} -ge 2 ]]; then
        local _pm_c _pm_l _pm_vals _pm_first _pm_ok
        for ((i = 0; i < ${#headers[@]}; i++)); do _pm_join[$i]=0; done
        _pm_c=$(( ${#headers[@]} - 1 ))
        _pm_ok=1; _pm_first=""
        for ((_pm_l = startidx; _pm_l < ${#lines[@]}; _pm_l++)); do
            _fr_tok "${lines[$_pm_l]}"; _pm_vals=("${_FR_TOK[@]}")
            [[ ${#_pm_vals[@]} -eq ${#headers[@]} ]] || { _pm_ok=0; break; }
            local _pm_pair="${_pm_vals[$((_pm_c - 1))]} ${_pm_vals[$_pm_c]}"
            [[ "${_pm_vals[$((_pm_c - 1))]}" =~ ^[a-z]+$ && "${_pm_vals[$_pm_c]}" =~ ^[a-z]+$ ]] || { _pm_ok=0; break; }
            [[ -z "$_pm_first" ]] && _pm_first="$_pm_pair"
            [[ "$_pm_pair" != "$_pm_first" ]] && { _pm_ok=0; break; }
        done
        [[ $_pm_ok -eq 1 ]] && _pm_join[$_pm_c]=1
    fi

    # Emit each data line as an indexed group (entry<N>.<field>) so the tidy melt
    # renders one row per line with shared columns.
    # Emitted pairs accumulate in an array (joined once below — a per-field
    # `result+=` re-copies the whole string: quadratic on big tables). The
    # letter name of a phrase-merged column is only computed when it is used.
    local result="" entry=0 li _resl=()
    # FAST PATH (no phrase merge in effect — the common case): one awk pass
    # emits exactly what the bash loop below would (see _ac_emit_rows).
    if [[ " ${_pm_join[*]:-} " != *" 1 "* && ${#headers[@]} -ge 1 ]]; then
        entry=$(( ${#lines[@]} - startidx ))
        if [[ $entry -gt 0 ]]; then
            local _hjoin _pairs
            _ac_join_tab "${headers[@]}"; _hjoin="$_AC_JOINED"
            _pairs="$(printf '%s\n' "${lines[@]:$startidx}" | _ac_emit_rows "$_hjoin")"
            [[ -n "$_pairs" ]] && result="$_pairs"$'\n'
            result+="total_entries ${entry}"$'\n'
        fi
        echo "$result"
        return 0
    fi
    for ((li = startidx; li < ${#lines[@]}; li++)); do
        local values; _fr_tok "${lines[$li]}"; values=("${_FR_TOK[@]}")
        # Apply the phrase merges (right-to-left so indices stay valid).
        if [[ ${#_pm_join[@]} -gt 0 && ${#values[@]} -eq ${#headers[@]} ]]; then
            for ((i = ${#headers[@]} - 1; i >= 1; i--)); do
                [[ "${_pm_join[$i]:-0}" -eq 1 ]] || continue
                values[$((i - 1))]="${values[$((i - 1))]} ${values[$i]}"
                values=("${values[@]:0:$i}" "${values[@]:$((i + 1))}")
            done
        fi
        entry=$((entry + 1))
        local _ncols=${#headers[@]}
        if [[ ${#_pm_join[@]} -gt 0 ]]; then
            _ncols=0
            for ((i = 0; i < ${#headers[@]}; i++)); do
                [[ "${_pm_join[$i]:-0}" -eq 1 ]] || _ncols=$((_ncols + 1))
            done
        fi
        for ((i = 0; i < _ncols; i++)); do
            local name
            if [[ ${#_pm_join[@]} -eq 0 || $_ncols -eq ${#headers[@]} ]]; then
                name="${headers[$i]}"
            else
                _fr_col_letter $((i + 1)); name="$_FR_LETTER"
            fi
            local value="${values[$i]:-}"
            [[ -z "$value" ]] && continue
            # Last column absorbs any extra trailing tokens (joined per the
            # VALUE-SPACE ENCODING setting, _AC_VALUE_JOIN).
            if [[ $i -eq $((_ncols - 1)) && ${#values[@]} -gt $_ncols ]]; then
                local j
                for ((j = i + 1; j < ${#values[@]}; j++)); do value+="${_AC_VALUE_JOIN}${values[$j]}"; done
            fi
            _resl+=("entry${entry}.${name} ${value}")
        done
    done

    [[ $entry -gt 0 ]] && _resl+=("total_entries ${entry}")
    [[ ${#_resl[@]} -gt 0 ]] && printf -v result '%s\n' "${_resl[@]}"
    echo "$result"
}
