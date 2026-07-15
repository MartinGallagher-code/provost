#!/bin/bash
## Name: colons
## Description: Extract field:value pairs from colon-delimited data
## Version: 1.0
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
    local _re="(^|${_nl})[[:space:]]*[A-Za-z][A-Za-z0-9_. -]*:([[:space:]]|${_nl}|$)"
    # Bracketed keys — Android getprop's `[ro.product.model]: [Pixel 8]`.
    local _bre="(^|${_nl})\[[A-Za-z][A-Za-z0-9._-]*\]:([[:space:]]|${_nl}|$)"
    [[ "$text" =~ $_re || "$text" =~ $_bre ]] || return 1

    # Require key:value lines to be a real fraction of the content, not a lone
    # stray colon in otherwise free text (e.g. a single `usage:` line inside
    # `strings` output). Below ~40% this isn't colon-delimited data — let the
    # last-resort line-records catch it as a one-column list instead.
    local _kv=0 _nb=0 _l
    local _line_re="^[[:space:]]*[A-Za-z][A-Za-z0-9_. -]*:([[:space:]]|$)"
    local _bline_re="^[[:space:]]*\[[A-Za-z][A-Za-z0-9._-]*\]:([[:space:]]|$)"
    while IFS= read -r _l; do
        [[ -z "${_l//[[:space:]]/}" ]] && continue
        _nb=$((_nb + 1))
        [[ "$_l" =~ $_line_re || "$_l" =~ $_bline_re ]] && _kv=$((_kv + 1))
    done <<< "$text"
    [[ $_nb -gt 0 && $(( _kv * 100 / _nb )) -ge 40 ]]
}

strategy_extract () {
    local text="$1"

    # Clean text (dates, parentheses) -- cached by engine after first call
    clean_text "$text"; text="$_CLEAN_TEXT_RESULT"

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

        # Strip leading "* " bullet markers and spaces
        local _stripped="$line"
        if [[ "$_stripped" == "* "* ]]; then
            _stripped="${_stripped#\* }"
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
