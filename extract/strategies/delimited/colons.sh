#!/bin/bash
## Name: colons
## Description: Extract field:value pairs from colon-delimited data
## Version: 1.1
## Priority: 60
## Sample: samples/colons/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=35
    # NOTE: no repeated-top-key guard here. `colons` is the last-resort fallback
    # (priority 60) — a dedicated record strategy (e.g. block-records, p40) always
    # outranks it for real multi-record input, so the guard is unnecessary. It
    # also must keep accepting repeated-key input so `--aggregate` can compute
    # count/min/max/sum/avg over repeated numeric fields.
    # Apply if input contains lines with colons (but not just URLs or timestamps)
    # Use variable for regex: (^|newline) to match any line start
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
    while IFS= read -r _l; do
        [[ -z "${_l//[[:space:]]/}" ]] && continue
        [[ "${_l#"${_l%%[![:space:]]*}"}" == "#"* ]] && continue
        _nb=$((_nb + 1))
        [[ "$_l" =~ $_line_re || "$_l" =~ $_bline_re ]] && _kv=$((_kv + 1))
    done <<< "$text"
    [[ $_nb -gt 0 && $(( _kv * 100 / _nb )) -ge 40 ]]
}

strategy_extract () {
    local text="$1"

    # Clean text (dates, parentheses) -- cached by engine after first call
    clean_text "$text"; text="$_CLEAN_TEXT_RESULT"

    # A UNIFORM `- ` bullet lead on every non-blank line is a bulleted list
    # (gnutls-cli-info's `- Certificate type: X.509`) — the dash is chrome,
    # stripped below. Detected once here (not per line) so a stray `- foo`
    # diff/hexdump line elsewhere never loses its dash.
    local _dash_bullets=1 _db_l _db_n=0
    while IFS= read -r _db_l; do
        [[ -z "${_db_l//[[:space:]]/}" ]] && continue
        _db_n=$((_db_n + 1))
        local _db_s="${_db_l#"${_db_l%%[![:space:]]*}"}"
        [[ "$_db_s" == "- "* ]] || { _dash_bullets=0; break; }
    done <<< "$text"
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
    while IFS= read -r _f_l; do
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
    done <<< "$text"
    _colons_flush_fold
    text="${_fold%$'\n'}"

    # Collapse spaces around colons and extract "key: value" lines
    # Skip lines where the "key" portion is too long (>50 chars) or empty
    local result=""
    while IFS= read -r line; do
        # Skip empty lines
        [[ -z "$line" ]] && continue

        # Must contain a colon
        [[ "$line" != *":"* ]] && continue

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

        # Trim edges of value; spaces inside the value are preserved (the engine
        # keeps everything after the first space as the value).
        while [[ "$value" == " "* ]]; do value="${value# }"; done
        while [[ "$value" == *" " ]]; do value="${value% }"; done

        # Skip if value is empty
        [[ -z "$value" ]] && continue

        result+="${key} ${value}"$'\n'
    done <<< "$text"

    echo "$result"
}
