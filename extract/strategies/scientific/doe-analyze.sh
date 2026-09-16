#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: doe-analyze
## Description: Extract Main Effects and ANOVA rows per response variable from `doe analyze` (doehelper) statistical reports
## Version: 1.0
## Priority: 22
## Sample: samples/doe-analyze/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=88

    # Both markers must be present: the report is a sequence of
    # "=== Section Name: <response> ===" blocks and these two are the
    # signature pair for `doe analyze`.
    [[ "$text" == "=== Main Effects: "* || "$text" == *$'\n=== Main Effects: '* ]] || return 1
    [[ "$text" == "=== ANOVA Table: "*  || "$text" == *$'\n=== ANOVA Table: '*  ]] || return 1
    return 0
}

## Trim trailing cell decorations from a numeric token: the percent sign and
## the significance markers "*", U+2731 (HEAVY ASTERISK) and U+2020 (DAGGER).
## The non-ASCII markers are matched byte-wise so the match does not depend on
## the locale. Result is left in _DOE_TOK (avoids a subshell per token).
_doe_trim_marks () {
    _DOE_TOK="$1"
    local prev=""
    while [[ "$_DOE_TOK" != "$prev" ]]; do
        prev="$_DOE_TOK"
        _DOE_TOK="${_DOE_TOK%\%}"
        _DOE_TOK="${_DOE_TOK%\*}"
        _DOE_TOK="${_DOE_TOK%$'\xe2\x9c\xb1'}"
        _DOE_TOK="${_DOE_TOK%$'\xe2\x80\xa0'}"
    done
}

strategy_extract () {
    local text="$1"
    local result=""
    local n=0

    local sec="" resp="" responses="" first_resp=""
    local r_squared="" adj_r_squared="" predicted_r_squared=""
    local in_adequacy=0

    # Regexes kept in variables: the report's section headers contain
    # literal parens (e.g. "(quadratic, k=5)") and bash's [[ =~ ]] would
    # otherwise mis-parse an inline pattern.
    local re_num='^[<>]?[-+]?[0-9]+([.][0-9]+)?([eE][-+]?[0-9]+)?$'
    local re_rule='^[[:space:]]*-+[[:space:]]*$'

    # U+2014 EM DASH, written byte-wise so the file stays ASCII-safe; the
    # report uses it as a "value not available" placeholder.
    local _DOE_EMDASH=$'\xe2\x80\x94'

    local line hdr name t
    local -a cols=()

    while IFS= read -r line; do
        # Strip a trailing CR so CRLF captures parse identically.
        line="${line%$'\r'}"

        # --- section header -------------------------------------------------
        if [[ "$line" == "==="*"===" ]]; then
            hdr="${line#=== }"
            hdr="${hdr% ===}"
            # "Model Adequacy (quadratic): yield" -> name / response.
            # A header without a colon carries no response variable.
            if [[ "$hdr" == *:* ]]; then
                name="${hdr%:*}"
                resp="${hdr##*:}"
                resp="${resp#"${resp%%[![:space:]]*}"}"
                resp="${resp%"${resp##*[![:space:]]}"}"
            else
                name="$hdr"
                resp=""
            fi

            in_adequacy=0
            case "$name" in
                "Main Effects") sec="main_effect" ;;
                "ANOVA Table")  sec="anova" ;;
                "Model Adequacy"*) sec=""; in_adequacy=1 ;;
                *) sec="" ;;
            esac

            if [[ -n "$resp" ]]; then
                case ",${responses}," in
                    *",${resp},"*) ;;
                    *) responses="${responses:+${responses},}${resp}"
                       [[ -z "$first_resp" ]] && first_resp="$resp" ;;
                esac
            fi
            continue
        fi

        # --- Model Adequacy key/value pairs (first response only) -----------
        if [[ $in_adequacy -eq 1 ]]; then
            t="${line#"${line%%[![:space:]]*}"}"
            if [[ -z "$t" ]]; then
                in_adequacy=0
                continue
            fi
            if [[ "$resp" == "$first_resp" && "$t" == *"="* ]]; then
                local val="${t#*=}"
                val="${val#"${val%%[![:space:]]*}"}"
                val="${val%%[[:space:]]*}"
                # An em-dash or "N/A" means "not computed"; leave the field absent.
                case "$val" in
                    "$_DOE_EMDASH"|"N/A"|"n/a"|"") val="" ;;
                esac
                [[ -n "$val" ]] || continue
                case "$t" in
                    "Predicted R"*) [[ -z "$predicted_r_squared" ]] && predicted_r_squared="$val" ;;
                    "Adj R"*)       [[ -z "$adj_r_squared" ]] && adj_r_squared="$val" ;;
                    "R"[!A-Za-z]*)  [[ -z "$r_squared" ]] && r_squared="$val" ;;
                esac
            fi
            continue
        fi

        [[ -n "$sec" ]] || continue

        # A blank line closes the current table block.
        if [[ -z "${line//[[:space:]]/}" ]]; then
            sec=""
            continue
        fi

        # The "---" rule beneath the header.
        [[ "$line" =~ $re_rule ]] && continue

        # Trailing prose the tool appends inside a block ("  Note: ...",
        # "  Lack-of-fit p=...") is never a data row.
        local body="${line#"${line%%[![:space:]]*}"}"
        body="${body%"${body##*[![:space:]]}"}"
        case "$body" in
            "Note:"*|"Lack-of-fit "*) continue ;;
        esac

        # How many numeric columns this section can carry.
        local min_num=3 max_num=5
        if [[ "$sec" == "main_effect" ]]; then min_num=2; max_num=3; fi

        # The label column ("Source"/"Factor") can contain spaces
        # (e.g. "Error (Lenth PSE)", "Lack of Fit", "Whole-Plot Error"), so a
        # plain whitespace split is wrong. The tool pads the label to a fixed
        # width, so the label is whatever precedes the first run of 2+ spaces;
        # if that does not yield a clean numeric tail (very long labels are not
        # padded), fall back to scanning numeric columns from the right.
        local term="" ok=0
        local -a nums=()

        if [[ "$body" == *"  "* ]]; then
            term="${body%%"  "*}"
            local rest="${body#*"  "}"
            cols=()
            read -r -a cols <<< "$rest"
            if [[ ${#cols[@]} -ge $min_num ]]; then
                ok=1
                nums=()
                local i
                for ((i = 0; i < ${#cols[@]} && ${#nums[@]} < max_num; i++)); do
                    _doe_trim_marks "${cols[i]}"
                    t="$_DOE_TOK"
                    # A cell that was nothing but a significance marker is not
                    # a column of its own.
                    [[ -z "$t" && "${cols[i]}" != "$_DOE_EMDASH" ]] && continue
                    if [[ "$t" =~ $re_num ]]; then
                        nums+=("$t")
                    elif [[ "$t" == "$_DOE_EMDASH" || "$t" == "N/A" || "$t" == "n/a" ]]; then
                        nums+=("")
                    else
                        ok=0
                        break
                    fi
                done
                [[ ${#nums[@]} -ge $min_num ]] || ok=0
            fi
        fi

        if [[ $ok -eq 0 ]]; then
            # Right-to-left scan: collect up to max_num numeric tokens from the
            # end; everything left of them is the label.
            cols=()
            read -r -a cols <<< "$body"
            local last=$(( ${#cols[@]} - 1 )) k
            local -a rev=()
            local nrev=0
            for ((k = last; k >= 1 && nrev < max_num; k--)); do
                _doe_trim_marks "${cols[k]}"
                t="$_DOE_TOK"
                [[ -z "$t" ]] && continue
                if [[ "$t" =~ $re_num ]]; then
                    rev+=("$t"); nrev=$((nrev + 1))
                elif [[ "$t" == "$_DOE_EMDASH" || "$t" == "N/A" || "$t" == "n/a" ]]; then
                    rev+=(""); nrev=$((nrev + 1))
                else
                    break
                fi
            done
            if [[ ${#rev[@]} -ge $min_num ]]; then
                # k is the index of the last token the scan did NOT consume,
                # so the label spans cols[0..k].
                local stop=$(( k + 1 ))
                nums=()
                for ((k = ${#rev[@]} - 1; k >= 0; k--)); do nums+=("${rev[k]}"); done
                term=""
                for ((k = 0; k < stop; k++)); do
                    term="${term:+${term} }${cols[k]}"
                done
                [[ -n "$term" ]] && ok=1
            fi
        fi

        [[ $ok -eq 1 && -n "$term" ]] || continue

        if [[ "$sec" == "main_effect" ]]; then
            # Factor / Effect / Std Error / % Contribution
            n=$((n + 1))
            local p="entry${n}."
            result+="${p}section main_effect"$'\n'
            result+="${p}response ${resp}"$'\n'
            result+="${p}term ${term}"$'\n'
            [[ -n "${nums[0]}" ]] && result+="${p}effect ${nums[0]}"$'\n'
            [[ -n "${nums[1]}" ]] && result+="${p}std_error ${nums[1]}"$'\n'
            [[ ${#nums[@]} -ge 3 && -n "${nums[2]}" ]] && result+="${p}pct_contribution ${nums[2]}"$'\n'
        else
            # Source / DF / SS / MS / F / p-value
            # (F and p-value are blank on Error / Total / Pure Error rows.)
            n=$((n + 1))
            local p="entry${n}."
            result+="${p}section anova"$'\n'
            result+="${p}response ${resp}"$'\n'
            result+="${p}term ${term}"$'\n'
            [[ -n "${nums[0]}" ]] && result+="${p}df ${nums[0]}"$'\n'
            [[ -n "${nums[1]}" ]] && result+="${p}ss ${nums[1]}"$'\n'
            [[ -n "${nums[2]}" ]] && result+="${p}ms ${nums[2]}"$'\n'
            [[ ${#nums[@]} -ge 4 && -n "${nums[3]}" ]] && result+="${p}f ${nums[3]}"$'\n'
            [[ ${#nums[@]} -ge 5 && -n "${nums[4]}" ]] && result+="${p}p_value ${nums[4]}"$'\n'
        fi
    done <<< "$text"

    [[ -n "$responses" ]] && result+="responses ${responses}"$'\n'
    [[ -n "$r_squared" ]] && result+="r_squared ${r_squared}"$'\n'
    [[ -n "$adj_r_squared" ]] && result+="adj_r_squared ${adj_r_squared}"$'\n'
    [[ -n "$predicted_r_squared" ]] && result+="predicted_r_squared ${predicted_r_squared}"$'\n'
    result+="total_entries ${n}"$'\n'
    echo "$result"
}
