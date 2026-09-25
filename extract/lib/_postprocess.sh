#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Post-processing functions for envoy-extract
##
## Accumulate, deduplicate, rename, aggregate, and filter extracted fields.
## Dependencies: _helpers.sh (strip_strat_prefix, _clean_field, _count_lines)
################################################################################

# Accumulate strategy output into the global output variable.
store () {
    local input="$1"
    local label="$2"

    # Number each line and prefix with strategy label (pure bash, no forks).
    # PERF: the labelled lines are collected in an array and appended to
    # `output` ONCE — a per-line `output+=` re-copies the whole (growing)
    # string every time, which made storing a big table quadratic.
    local _n=0 _st_all _st_joined
    local -a _st_out=()
    if (( ${#input} > _FR_BIG_BYTES )); then
        # BIG result: the same numbering in one awk pass (see _FR_BIG_BYTES)
        _st_joined="$(printf '%s\n' "$input" | _ST_LABEL="$label" awk '
            BEGIN { l = ENVIRON["_ST_LABEL"] }
            $0 != "" { n++; printf "%s:%d\t%s\n", l, n, $0 }'; printf .)"
        output+="${_st_joined%.}"
        _sline=""
        return 0
    fi
    mapfile -t _st_all <<< "$input"
    for _sline in "${_st_all[@]}"; do
        [[ -z "$_sline" ]] && continue
        _n=$((_n + 1))
        _st_out+=("${label}:${_n}	${_sline}")
    done
    _sline=""
    if [[ ${#_st_out[@]} -gt 0 ]]; then
        printf -v _st_joined '%s\n' "${_st_out[@]}"
        output+="$_st_joined"
    fi
}

# Deduplicate output across strategies.
# When multiple strategies extract the same field name+value, keep only the first.
# Sort-based O(n log n) approach using SOH (0x01) as the record delimiter.
# Format: fieldpart SOH lineno SOH origline
# Sort by fieldpart (col 1 only), dedup, restore insertion order by lineno (col 2).
deduplicate_output () {
    local input="$1"
    [[ -z "$input" ]] && return

    # PERF: records collected in an array and joined once (a per-line
    # `_formatted+=` is quadratic), and the final field-3 projection is one
    # sed pass instead of a `while read … | echo` loop that drained the pipe
    # one byte per read(2). The sed reproduces `IFS=$'\x01' read -r _ _ rest`
    # exactly: rest = everything after the 2nd SOH, minus one trailing SOH
    # when that SOH is the rest's only one (bash's trailing-delimiter rule).
    local _n=0 _formatted="" _dd_all _dd_line
    local -a _dd_out=()
    if (( ${#input} > _FR_BIG_BYTES )); then
        # BIG output: build the same SOH records in one awk pass
        printf '%s\n' "$input" \
            | awk '$0 != "" {
                n++; f = $0; i = index(f, "\t"); if (i) f = substr(f, i + 1)
                printf "%s\001%d\001%s\n", f, n, $0
            }' \
            | sort -t$'\x01' -k1,1 -u \
            | sort -t$'\x01' -k2,2 -n \
            | LC_ALL=C sed $'s/^[^\001]*\001[^\001]*\001//; s/^\\([^\001]*\\)\001$/\\1/'
        return
    fi
    mapfile -t _dd_all <<< "$input"
    for _dd_line in "${_dd_all[@]}"; do
        [[ -z "$_dd_line" ]] && continue
        _n=$((_n + 1))
        local _fpart
        case "$_dd_line" in
            *$'\t'*) _fpart="${_dd_line#*$'\t'}" ;;
            *)       _fpart="$_dd_line" ;;
        esac
        _dd_out+=("${_fpart}"$'\x01'"${_n}"$'\x01'"${_dd_line}")
    done
    [[ ${#_dd_out[@]} -gt 0 ]] && printf -v _formatted '%s\n' "${_dd_out[@]}"

    # Sort by fieldpart (SOH col 1), dedup, restore order by lineno (SOH col 2)
    printf '%s' "$_formatted" \
        | sort -t$'\x01' -k1,1 -u \
        | sort -t$'\x01' -k2,2 -n \
        | LC_ALL=C sed $'s/^[^\001]*\001[^\001]*\001//; s/^\\([^\001]*\\)\001$/\\1/'
}

# Apply field renames to output.
# Renames only the field name portion (after STRAT prefix tab, before first space).
apply_renames () {
    local input="$1"
    local renames="$2"

    # Build a sed script for O(n) rename application.
    # Each rename pair becomes a sed substitution on the field name portion
    # (the part between the tab and the first space).
    #
    # ENV-172: read the comma-separated rename list into an array
    # (`read -r -a`) instead of `for pair in $renames`. The legacy form
    # word-split on `,` correctly (IFS=','), but ALSO glob-expanded the
    # unquoted variable against CWD, so a `--rename 'a=*'` would
    # resolve `*` to whatever filenames were sitting around.
    #
    # ENV-172 (sed escapes): the pattern-side class previously was
    # `[.[\/*^$]` — covered `.`, `[`, `\`, `/`, `*`, `^`, `$` but
    # missed `]` (would close the char class). The replacement-side
    # class `[\/&]` covered `/` and `&` but missed `\`. A field name
    # containing `]` or a replacement containing a literal backslash
    # produced a malformed sed script and aborted the pipeline.
    local _renames_arr=()
    IFS=',' read -r -a _renames_arr <<< "$renames"
    local _sed_script=""
    local pair
    for pair in "${_renames_arr[@]}"; do
        local old_name="${pair%%=*}"
        local new_name="${pair#*=}"
        [[ -z "$old_name" || -z "$new_name" ]] && continue
        # Pattern-side: escape every BRE metacharacter PLUS `]`. The
        # bracket class `[].[\/*^$]` lists `]` first (so it's a
        # literal not the closer), then `.`, `[`, `\`, `/`, `*`, `^`,
        # `$`. The pre-fix class `[.[\/*^$]` missed `]` — a field
        # name containing `]` produced a malformed sed script.
        local _eo _en
        _eo="$(printf '%s' "$old_name" | sed 's/[].[\/*^$]/\\&/g')"
        # Replacement-side: escape `\`, `/`, and `&`. Pre-fix `\` was
        # NOT in the class (the class was `[\/&]` which is `/` and `&`
        # only), so a new_name containing a literal backslash produced
        # an invalid sed substitution.
        _en="$(printf '%s' "$new_name" | sed 's/[\\/&]/\\&/g')"
        _sed_script+="s/	${_eo} /	${_en} /;"
    done

    if [[ -z "$_sed_script" ]]; then
        echo "$input"
        return
    fi

    echo "$input" | sed "$_sed_script"
}

# Aggregate numeric fields: compute count/min/max/sum/avg.
# Uses a single awk call -- float arithmetic makes pure-bash impractical here.
aggregate_output () {
    local input="$1"

    echo "$input" | awk '/^$/ { next } {
        # Extract field portion (after STRAT prefix tab)
        idx = index($0, "\t")
        if (idx > 0) {
            rest = substr($0, idx + 1)
        } else {
            rest = $0
        }

        # Split into name and value at the FIRST space: the value is the
        # whole remainder (it may carry spaces — `12 KB` is not the number 12)
        sp = index(rest, " ")
        if (sp < 2) next
        name = substr(rest, 1, sp - 1)
        value = substr(rest, sp + 1)

        # Check if value is numeric
        if (value + 0 == value && value != "") {
            if (!(name in count)) {
                order[++order_n] = name
            }
            count[name]++
            sum[name] += value
            if (!(name in min_v) || value + 0 < min_v[name] + 0) min_v[name] = value
            if (!(name in max_v) || value + 0 > max_v[name] + 0) max_v[name] = value
        }
    }
    END {
        for (i = 1; i <= order_n; i++) {
            name = order[i]
            if (count[name] > 1) {
                printf "%s_count %d\n", name, count[name]
                printf "%s_min %s\n", name, min_v[name]
                printf "%s_max %s\n", name, max_v[name]
                printf "%s_sum %s\n", name, sum[name]
                printf "%s_avg %.2f\n", name, sum[name] / count[name]
            }
        }
    }'
}

# Filter output to only include fields matching a regex pattern.
# Operates on STRAT-prefixed lines; extracts field name from after the tab.
# Result replaces $output in-place (caller passes/receives via global).
apply_field_pattern () {
    local input="$1"
    local pattern="$2"
    [[ -z "$input" || -z "$pattern" ]] && { echo "$input"; return; }

    local _result="" _fpline _fpclean _fpname
    while IFS= read -r _fpline; do
        [[ -z "$_fpline" ]] && continue
        # Extract field name: strip STRAT prefix, then take first word
        case "$_fpline" in
            *$'\t'*) _fpclean="${_fpline#*$'\t'}" ;;
            *)       _fpclean="$_fpline" ;;
        esac
        _fpname="${_fpclean%% *}"
        if [[ "$_fpname" =~ $pattern ]]; then
            _result+="$_fpline"$'\n'
        fi
    done <<< "$input"
    printf '%s' "${_result%$'\n'}"
}

# Filter output to exclude fields with exact name matches.
# _OPT_exclude_fields array must be set by caller.
apply_exclude_fields () {
    local input="$1"
    [[ -z "$input" ]] && { echo "$input"; return; }
    [[ ${#_OPT_exclude_fields[@]} -eq 0 ]] && { echo "$input"; return; }

    # Build a lookup string for O(1) matching
    local _excl_lookup=$'\n'
    local _ef
    for _ef in "${_OPT_exclude_fields[@]}"; do
        _excl_lookup+="$_ef"$'\n'
    done

    local _result="" _efline _efclean _efname
    while IFS= read -r _efline; do
        [[ -z "$_efline" ]] && continue
        case "$_efline" in
            *$'\t'*) _efclean="${_efline#*$'\t'}" ;;
            *)       _efclean="$_efline" ;;
        esac
        _efname="${_efclean%% *}"
        if [[ "$_excl_lookup" == *$'\n'"$_efname"$'\n'* ]]; then
            continue
        fi
        _result+="$_efline"$'\n'
    done <<< "$input"
    printf '%s' "${_result%$'\n'}"
}

# Filter raw output by field numbers or names and strip STRAT prefix.
# Supports: "1,3,5" (numeric), "hostname,cpu_count" (names), or mixed.
# Returns clean "name value" lines for format functions.
filter_fields () {
    local input="$1"
    local field_filter="$2"

    # Build lookup string from comma-separated field specs
    local _wanted=$'\n'"${field_filter//,/$'\n'}"$'\n'

    # Determine if filter is purely numeric
    local _is_numeric=1
    if [[ ! "$field_filter" =~ ^[0-9,]+$ ]]; then
        _is_numeric=0
    fi

    local _n=0
    while IFS= read -r _fline; do
        [[ -z "$_fline" ]] && continue
        _n=$((_n + 1))

        # Strip STRAT prefix
        strip_strat_prefix "$_fline"
        local _clean="$_STRIPPED_LINE"
        local _fname="${_clean%% *}"

        if [[ $_is_numeric -eq 1 ]]; then
            # Check by line number
            [[ "$_wanted" == *$'\n'"$_n"$'\n'* ]] || continue
        else
            # Check by field name (or number for mixed)
            local _match=0
            if [[ "$_wanted" == *$'\n'"$_n"$'\n'* ]]; then
                _match=1
            elif [[ "$_wanted" == *$'\n'"$_fname"$'\n'* ]]; then
                _match=1
            fi
            [[ $_match -eq 1 ]] || continue
        fi
        echo "$_clean"
    done <<< "$input"
}
