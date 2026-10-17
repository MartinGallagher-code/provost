#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: colons
## Description: Extract field:value pairs from colon-delimited data
## Version: 1.2
## Priority: 60
## Confidence-Max: 60
## Sample: samples/colons/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    # NOTE: no repeated-top-key guard here. `colons` is the last-resort fallback
    # (priority 60) — a dedicated record strategy (e.g. block-records, p40) always
    # outranks it for real multi-record input, so the guard is unnecessary. It
    # also must keep accepting repeated-key input so `--aggregate` can compute
    # count/min/max/sum/avg over repeated numeric fields.
    # Apply if input contains lines with colons (but not just URLs or timestamps)
    # Use variable for regex: (^|newline) to match any line start
    if (( ${#text} > _FR_BIG_BYTES )); then
        # BIG input: the regex screen and the share count below in one awk
        # pass. The screen is "some line is a `label:` line" — exactly kv > 0
        # (a `#` line or a blank one can never match) — so the count decides.
        local _kv=0 _nb=0
        read -r _kv _nb < <(cat <<< "$text" | awk '
            /^[ \t\n\v\f\r]*$/ { next }
            { t = $0; sub(/^[ \t\n\v\f\r]+/, "", t); if (substr(t, 1, 1) == "#") next }
            {
                nb++
                if ($0 ~ /^[ \t\n\v\f\r]*[A-Za-z][A-Za-z0-9_ -]*:([ \t\n\v\f\r]|$)/ \
                    || $0 ~ /^[ \t\n\v\f\r]*\[[A-Za-z][A-Za-z0-9._-]*\]:([ \t\n\v\f\r]|$)/) kv++
            }
            END { printf "%d %d\n", kv, nb }')
        [[ $_kv -gt 0 ]] || return 1
        [[ $_nb -gt 0 && $(( _kv * 100 / _nb )) -ge $(( 40 - ${_FR_SLACK:-0} )) ]] || return 1
        _STRATEGY_CONFIDENCE=$(( 55 + (_kv * 100 / _nb - 40) * 5 / 60 ))
        return 0
    fi
    local _nl=$'\n'
    # A real `key: value` line: optional indent, a label, a colon, then whitespace
    # or end of line. Requiring whitespace after the colon avoids matching colons
    # inside timestamps/values (e.g. `date`'s `10:15:42`) as a key.
    local _re="(^|${_nl})[[:space:]]*[A-Za-z][A-Za-z0-9_ -]*:([[:space:]]|${_nl}|$)"
    # Bracketed keys — Android getprop's `[ro.product.model]: [Pixel 8]`.
    local _bre="(^|${_nl})\[[A-Za-z][A-Za-z0-9._-]*\]:([[:space:]]|${_nl}|$)"
    [[ "$text" =~ $_re || "$text" =~ $_bre ]] || return 1

    # Require key:value lines to be a real fraction of the content, not a lone
    # stray colon in otherwise free text (e.g. a single `usage:` line inside
    # `strings` output). Below ~40% this isn't colon-delimited data — let the
    # last-resort line-records catch it as a one-column list instead.
    #
    # `#` comment banners are excluded from BOTH sides of that ratio: they are
    # not data, strategy_extract already drops them (no colon, or an empty
    # value), and counting them in the denominator buries the real pairs. `perf
    # bench sched` prints three banner lines over a single `Total time:` pair —
    # 25% with the banners, 100% without, and only the pair is data.
    local _kv=0 _nb=0 _l
    local _line_re="^[[:space:]]*[A-Za-z][A-Za-z0-9_ -]*:([[:space:]]|$)"
    local _bline_re="^[[:space:]]*\[[A-Za-z][A-Za-z0-9._-]*\]:([[:space:]]|$)"
    _fr_lines "$text"
    for _l in "${_FR_LINES[@]}"; do
        [[ "${_l}" != *[![:space:]]* ]] && continue
        [[ "${_l#"${_l%%[![:space:]]*}"}" == "#"* ]] && continue
        _nb=$((_nb + 1))
        [[ "$_l" =~ $_line_re || "$_l" =~ $_bline_re ]] && _kv=$((_kv + 1))
    done
    [[ $_nb -gt 0 && $(( _kv * 100 / _nb )) -ge $(( 40 - ${_FR_SLACK:-0} )) ]] || return 1
    # General-structure tier (extract/README.md "Confidence rubric"): 55..60,
    # scaled by the share of `label: value` lines (40% -> 55, 100% -> 60).
    # Above the catch-alls (line-records <= 55 loses the tie on priority,
    # text-lines 50), at or below a real table (aligned-columns >= 60, which
    # wins the tie on priority). It used to be a flat 35 — under provost's
    # filing threshold — but under confidence ranking that would rank colons
    # below text-lines and hand every colon block to a catch-all.
    _STRATEGY_CONFIDENCE=$(( 55 + (_kv * 100 / _nb - 40) * 5 / 60 ))
    return 0
}

# _strat_colons_extract_awk TEXT — strategy_extract for a BIG input in one awk
# pass, byte-identical to the bash loops below: clean_text's date / paren
# protection, the uniform dash-bullet test, the indented-list FOLD, the main
# key/value loop and restore_text_values, in that order. Returns 3 (nothing
# printed) when a line needs bash-only semantics — a paren span holding a
# glob / `&` byte, an over-long non-ASCII key (${#key} counts characters) or
# a non-ASCII bracketed value — and the caller runs the bash loops instead.
_strat_colons_extract_awk () {
    local _o
    _o="$(cat <<< "$1" | awk '
        BEGIN { SP = sprintf("%c", 30); CO = sprintf("%c", 31); n = 0 }
        {
            line = $0
            # clean_text
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
            L[++n] = line
        }
        END {
            if (bail) exit 3
            # (the bash text is the cleaned lines newline-joined, then read
            # back with a here-string: the same lines)
            # uniform "- " bullets over every non-blank line (and >= 2 of them)
            db = 1; dbn = 0
            for (i = 1; i <= n; i++) {
                if (L[i] !~ /[^ \t\n\v\f\r]/) continue
                dbn++
                s = L[i]; sub(/^[ \t\n\v\f\r]+/, "", s)
                if (substr(s, 1, 2) != "- ") { db = 0; break }
            }
            if (dbn < 2) db = 0
            # FOLD indented list blocks into their bare header
            m = 0; hdr = ""; hind = 0; items = ""; cnt = 0
            for (i = 1; i <= n; i++) {
                l = L[i]
                if (hdr != "") {
                    match(l, /^[ \t\n\v\f\r]*/); ind = RLENGTH; body = substr(l, ind + 1)
                    if (body != "" && ind > hind && index(body, ": ") == 0 && substr(body, length(body)) != ":") {
                        sub(/[ \t\n\v\f\r]+$/, "", body)
                        items = items (items != "" ? "; " : "") body
                        cnt++
                        continue
                    }
                    F[++m] = (items != "" && cnt >= 2) ? hdr " " items : hdr
                    hdr = ""; items = ""; cnt = 0
                }
                if (l ~ /^[ \t\n\v\f\r]*[A-Za-z][A-Za-z0-9_ -]*:[ \t\n\v\f\r]*$/) {
                    match(l, /^[ \t\n\v\f\r]*/); hind = RLENGTH
                    hdr = l
                    continue
                }
                F[++m] = l
            }
            if (hdr != "") F[++m] = (items != "" && cnt >= 2) ? hdr " " items : hdr
            # main loop
            nc = 0
            for (i = 1; i <= m; i++) {
                l = F[i]
                if (l == "") continue
                c = index(l, ":")
                banner = 0
                if (c) { pre = substr(l, 1, c - 1); if (index(pre, "(") && !index(pre, ")")) banner = 1 }
                if (!c || banner) {
                    t = l; sub(/^[ \t\n\v\f\r]+/, "", t); sub(/[ \t\n\v\f\r]+$/, "", t)
                    if (t == "") continue
                    if (t ~ /^[-=~*+_][-=~*+_][-=~*+_]+$/) continue
                    nc++
                    out("line" nc, t)
                    continue
                }
                s = l
                if (substr(s, 1, 2) == "* ") s = substr(s, 3)
                else if (db) {
                    d = s; sub(/^[ \t\n\v\f\r]+/, "", d)
                    if (substr(d, 1, 2) == "- ") s = substr(d, 3)
                }
                sub(/^ +/, "", s)
                c = index(s, ":"); key = substr(s, 1, c - 1)
                j = index(s, ": ")
                if (j) val = substr(s, j + 2); else val = substr(s, c + 1)
                if (key ~ /^\[[A-Za-z][A-Za-z0-9._-]*\]$/) {
                    key = substr(key, 2, length(key) - 2)
                    sub(/^ +/, "", val); sub(/ +$/, "", val)
                    if (val ~ /[^\001-\177]/) exit 3
                    if (val ~ /^\[.*\]$/) val = substr(val, 2, length(val) - 2)
                }
                sub(/^[ \t\n\v\f\r]+/, "", key); sub(/[ \t\n\v\f\r]+$/, "", key)
                if (key == "") continue
                if (length(key) > 50) { if (key ~ /[^\001-\177]/) exit 3; continue }
                if (substr(val, 1, 2) == "//") continue
                if (key ~ /^[0-9]/) continue
                gsub(/ /, "_", key); gsub(/__+/, "_", key); sub(/^_/, "", key); sub(/_$/, "", key)
                sub(/^[ \t]+/, "", val); sub(/[ \t]+$/, "", val)
                if (val == "") continue
                out(key, val)
            }
            # RECORDS (see _COLONS_REC_AWK): the bash loop emits those
            if (nk && KS[1] !~ /^line[0-9]+$/) {
                op = KS[1]; r = 0; distinct = 0; fields = 0; bad = 0
                for (i = 1; i <= nk; i++) {
                    k = KS[i]
                    if (k == op) r++
                    if (k ~ /^line[0-9]+$/) continue
                    if ((r, k) in rseen) bad = 1
                    rseen[r, k] = 1
                    if (!(k in RD)) { RD[k] = 1; distinct++ }
                    fields++
                }
                if (!bad && r >= 2 && distinct >= 2 && fields >= 2 * r) exit 3
            }
            # `echo "$_RESTORED_TEXT"`: echo adds a newline, and
            # restore_text_values (which only rewrites when a sentinel is
            # present) re-reads its newline-terminated input with a
            # here-string and so keeps one more
            printf "\n"
            if (sent) printf "\n"
        }
        # restore_text_values: sentinels -> "_" in the name, back to space /
        # colon in the value
        function out(k, v) {
            if (!sent && (index(k v, SP) || index(k v, CO))) sent = 1
            gsub(SP, "_", k); gsub(CO, "_", k)
            gsub(SP, " ", v); gsub(CO, ":", v)
            KS[++nk] = k
            print k " " v
        }' && printf .)" || return 3
    [[ "$_o" == *. ]] || return 3
    printf '%s' "${_o%.}"
    return 0
}

strategy_extract () {
    local text="$1"
    if (( ${#text} > _FR_BIG_BYTES )); then
        local _cox_rc=0
        _strat_colons_extract_awk "$text" || _cox_rc=$?
        [[ $_cox_rc -eq 3 ]] || return $_cox_rc
    fi

    # Clean text (dates, parentheses) -- cached by engine after first call
    clean_text "$text"; text="$_CLEAN_TEXT_RESULT"

    # A UNIFORM `- ` bullet lead on every non-blank line is a bulleted list
    # (gnutls-cli-info's `- Certificate type: X.509`) — the dash is chrome,
    # stripped below. Detected once here (not per line) so a stray `- foo`
    # diff/hexdump line elsewhere never loses its dash.
    local _dash_bullets=1 _db_l _db_n=0
    _fr_lines "$text"
    for _db_l in "${_FR_LINES[@]}"; do
        [[ "${_db_l}" != *[![:space:]]* ]] && continue
        _db_n=$((_db_n + 1))
        local _db_s="${_db_l#"${_db_l%%[![:space:]]*}"}"
        [[ "$_db_s" == "- "* ]] || { _dash_bullets=0; break; }
    done
    [[ $_db_n -ge 2 ]] || _dash_bullets=0

    # FOLD indented list blocks into their bare header. A `Key:` line with no
    # value over STRICTLY deeper-indented, colon-free plain lines is a list
    # field (dmidecode's `Characteristics:` over `PCI is supported` …). Both
    # halves used to be dropped — the header for its empty value, the items
    # for having no colon ("you left most of the info out"). The items join
    # into the header's value with `; `. Lines that don't fit pass through
    # untouched, so ordinary kv extraction is unchanged.
    local _fold="" _f_hdr="" _f_hind="" _f_items="" _f_l _f_count=0
    _colons_flush_fold () {
        if [[ -n "$_f_hdr" ]]; then
            # A LIST needs >=2 items — a lone indented line under a bare
            # header is a usage hint (dolt status's `(use "dolt add …")`),
            # not data, and folding it would keep chrome as a value.
            if [[ -n "$_f_items" && $_f_count -ge 2 ]]; then
                _fold+="${_f_hdr} ${_f_items}"$'\n'
            else
                _fold+="${_f_hdr}"$'\n'
            fi
            _f_hdr=""; _f_items=""; _f_count=0
        fi
    }
    _fr_lines "$text"
    for _f_l in "${_FR_LINES[@]}"; do
        if [[ -n "$_f_hdr" ]]; then
            local _f_ind="${_f_l%%[![:space:]]*}"
            local _f_body="${_f_l#"$_f_ind"}"
            if [[ -n "$_f_body" && ${#_f_ind} -gt ${#_f_hind} \
                  && "$_f_body" != *": "* && "$_f_body" != *: ]]; then
                _f_body="${_f_body%"${_f_body##*[![:space:]]}"}"
                _f_items+="${_f_items:+; }${_f_body}"
                _f_count=$((_f_count + 1))
                continue
            fi
            _colons_flush_fold
        fi
        # A bare header: `Key:` (letter-led, no value after the colon).
        if [[ "$_f_l" =~ ^([[:space:]]*)([A-Za-z][A-Za-z0-9_\ -]*):[[:space:]]*$ ]]; then
            _f_hind="${BASH_REMATCH[1]}"
            _f_hdr="$_f_l"
            continue
        fi
        _fold+="$_f_l"$'\n'
    done
    _colons_flush_fold
    text="${_fold%$'\n'}"

    # Collapse spaces around colons and extract "key: value" lines
    # Skip lines where the "key" portion is too long (>50 chars) or empty
    #
    # A line WITHOUT a colon is kept as a numbered line field rather than
    # dropped. `colons` is the last-resort fallback, and the lines it used to
    # discard were routinely the most important in the input — curl's first
    # line (its version and entire library list), gcc's closing `gcc version
    # 13.3.0 (…)`, openssl's banner. Pure separator rules are still chrome.
    local result="" _nc_n=0 _nr=0 _rawkey
    local -A _col_sec=()
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        # Skip empty lines
        [[ -z "$line" ]] && continue

        # A first colon that sits INSIDE parentheses is punctuation, not a kv
        # separator: openssl's banner `OpenSSL 3.0.13 … (Library: OpenSSL …)`
        # is one statement, and splitting it at that colon manufactured a
        # 36-character field name. Such a line is a banner — route it to the
        # line<N> keeper below with the genuinely colon-less lines.
        local _nc_pre="${line%%:*}" _nc_banner=0
        if [[ "$line" == *":"* && "$_nc_pre" == *"("* && "$_nc_pre" != *")"* ]]; then
            _nc_banner=1
        fi

        # Keep a colon-less line as line<N> (trimmed); drop bare rules.
        if [[ "$line" != *":"* || $_nc_banner -eq 1 ]]; then
            local _nc="${line#"${line%%[![:space:]]*}"}"
            _nc="${_nc%"${_nc##*[![:space:]]}"}"
            [[ -z "$_nc" ]] && continue
            [[ "$_nc" =~ ^[-=~*+_]{3,}$ ]] && continue
            _nc_n=$((_nc_n + 1))
            result+="line${_nc_n} ${_nc}"$'\n'; _nr=$((_nr + 1))
            continue
        fi

        # Extract key (everything before first colon) and value (everything after)
        local key value

        # Strip leading "* " bullet markers and spaces; "- " only in a
        # uniformly dash-bulleted block (see _dash_bullets above).
        local _stripped="$line"
        if [[ "$_stripped" == "* "* ]]; then
            _stripped="${_stripped#\* }"
        elif [[ $_dash_bullets -eq 1 ]]; then
            local _ds="${_stripped#"${_stripped%%[![:space:]]*}"}"
            [[ "$_ds" == "- "* ]] && _stripped="${_ds#- }"
        fi
        while [[ "$_stripped" == " "* ]]; do _stripped="${_stripped# }"; done

        key="${_stripped%%:*}"
        value="${_stripped#*: }"
        # If no space after colon, strip just the colon
        if [[ "$value" == "$_stripped" ]]; then
            value="${_stripped#*:}"
        fi

        # Bracketed kv (`[ro.product.model]: [Pixel 8]`): the brackets are
        # chrome — unwrap both sides, keeping the whole value (spaces intact).
        if [[ "$key" =~ ^\[([A-Za-z][A-Za-z0-9._-]*)\]$ ]]; then
            key="${BASH_REMATCH[1]}"
            while [[ "$value" == " "* ]]; do value="${value# }"; done
            while [[ "$value" == *" " ]]; do value="${value% }"; done
            [[ "$value" =~ ^\[(.*)\]$ ]] && value="${BASH_REMATCH[1]}"
        fi

        # Trim the key's surrounding whitespace BEFORE the length check — a
        # column-aligned kv block pads its keys to the colon (`chage -l`'s
        # `Last password change                : …`), and judging the padded
        # length rejected every line of it (empty extraction, no winner).
        key="${key#"${key%%[![:space:]]*}"}"
        key="${key%"${key##*[![:space:]]}"}"

        _rawkey="$key"
        # Skip if key is empty, too long, or looks like a non-field line
        [[ -z "$key" ]] && continue
        [[ ${#key} -gt 50 ]] && continue

        # Skip lines that look like URLs (value starts with //)
        [[ "$value" == //* ]] && continue

        # Skip lines where key starts with a digit
        [[ "$key" =~ ^[0-9] ]] && continue

        # Trim the key's surrounding whitespace (column-alignment padding, e.g.
        # `Battery #1     :`) BEFORE turning inner spaces into underscores, then
        # collapse any runs so the field name is clean (`Battery_#1`, not
        # `Battery_#1____`).
        key="${key#"${key%%[![:space:]]*}"}"
        key="${key%"${key##*[![:space:]]}"}"
        key="${key// /_}"
        while [[ "$key" == *__* ]]; do key="${key//__/_}"; done
        key="${key#_}"
        key="${key%_}"

        # Trim edges of value (spaces AND tabs — `inactive time:<TAB>1520 ms`);
        # spaces inside the value are preserved (the engine
        # keeps everything after the first space as the value).
        _trim "$value"; value="$_TRIMMED"

        # Skip if value is empty (a bare heading: remembered for RECORDS)
        if [[ -z "$value" ]]; then
            _rawkey="${_rawkey//$_CT_SP/ }"; _col_sec[$_nr]="${_rawkey//$_CT_CO/:}"
            continue
        fi

        result+="${key} ${value}"$'\n'; _nr=$((_nr + 1))
    done

    # clean_text protected dates/parenthesised spans with sentinels; put the
    # original spaces and colons back into the values.
    restore_text_values "$result"
    if [[ $_nr -ge 4 ]]; then
        local _rs="" _ri=0 _rl _ro
        _fr_lines "$_RESTORED_TEXT"
        for _rl in "${_FR_LINES[@]}"; do
            [[ -z "$_rl" ]] && continue
            [[ -n "${_col_sec[$_ri]+x}" ]] && _rs+=$'\001S\t'"${_col_sec[$_ri]}"$'\n'
            _rs+="$_rl"$'\n'; _ri=$((_ri + 1))
        done
        _ro="$(printf '%s' "$_rs" | awk "$_COLONS_REC_AWK")"
        if [[ "$_ro" == R$'\n'* ]]; then
            printf '%s\n' "${_ro#R$'\n'}"
            return 0
        fi
    fi
    echo "$_RESTORED_TEXT"
}

# RECORDS. A listing of repeated records — `openssl list -public-key-
# algorithms`: ` Name: …` over tab-indented `Type:` / `OID:` fields, fifteen
# times, under `Legacy:` / `Provided:` headings; `rpm -qi a b c` — comes out
# of the loops above as one key/value stream whose keys repeat, which a wide
# row collapses into one record with fifteen `Name` columns. When the stream
# splits cleanly into records it is emitted as records instead: the FIRST key
# opens a record each time it recurs (>= 2 records), no key repeats inside a
# record, there are >= 2 distinct keys and >= 2 fields per record on
# average, and no colon-less line comes before the first record. A bare
# `Label:` heading met before an opener (dropped by the loop as an empty
# value) names the `section` of the records below it; a record's colon-less
# lines join (`; `) into its `text` field. Input: the "key value" lines,
# with `\001S<TAB>heading` marker lines; prints `N` (not records) or `R`
# then the records. The awk twin applies the same test to its own key
# stream and hands such an input back to the bash loop (exit 3).
_COLONS_REC_AWK='
substr($0, 1, 1) == "\001" { pend = substr($0, 4); hassec = 1; next }
$0 == "" { next }
{
    k = $1; v = substr($0, length(k) + 2)
    n++; K[n] = k; V[n] = v
    if (n == 1) op = k
    if (k == op) { r++; SECR[r] = pend }
    if (k ~ /^line[0-9]+$/) next
    if ((r, k) in seen) bad = 1
    seen[r, k] = 1
    if (!(k in D)) { D[k] = 1; distinct++ }
    fields++
}
END {
    if (!n || op ~ /^line[0-9]+$/ || bad || r < 2 || distinct < 2 || fields < 2 * r) { print "N"; exit }
    print "R"
    e = 0
    for (i = 1; i <= n; i++) {
        if (K[i] == op) {
            if (e && txt != "") print "entry" e ".text " txt
            e++; txt = ""
            if (hassec) print "entry" e ".section " SECR[e]
        }
        if (K[i] ~ /^line[0-9]+$/) { txt = txt (txt != "" ? "; " : "") V[i]; continue }
        print "entry" e "." K[i] " " V[i]
    }
    if (txt != "") print "entry" e ".text " txt
    print "total_entries " e
}'

