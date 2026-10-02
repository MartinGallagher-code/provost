#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Strategy discovery and execution for envoy-extract
##
## Find, load, detect, and run extraction strategies.
## Dependencies: _log.sh, _helpers.sh (_clean_field, _count_lines),
##               _postprocess.sh (store)
################################################################################

# ---------------------------------------------------------------------------
# In-process caches. A single-file run pays each cost once, so these are
# almost free there — but batch mode runs the whole discovery pipeline once
# PER INPUT, which used to mean ~200 metadata re-reads, a directory rescan +
# sort, and ~60 strategy re-sources for every file in the batch. Everything
# cached here is immutable for the life of the process (strategy files are
# not edited mid-run).
# ENV-182 note applies: assoc arrays are explicitly initialised to empty —
# bash 4.x with `set -u` aborts expanding an unassigned assoc array.
# ---------------------------------------------------------------------------
declare -A _META_CACHE_HAVE=()
declare -A _META_CACHE_NAME=()
declare -A _META_CACHE_DESC=()
declare -A _META_CACHE_VER=()
declare -A _META_CACHE_PRI=()
declare -A _META_CACHE_DEP=()

# Read strategy metadata from file header (first 15 lines), memoised per path.
# Sets globals: _META_NAME, _META_DESCRIPTION, _META_VERSION, _META_PRIORITY,
#               _META_DEPRECATED
read_strategy_metadata () {
    local filepath="$1"
    if [[ -n "${_META_CACHE_HAVE[$filepath]:-}" ]]; then
        _META_NAME="${_META_CACHE_NAME[$filepath]}"
        _META_DESCRIPTION="${_META_CACHE_DESC[$filepath]}"
        _META_VERSION="${_META_CACHE_VER[$filepath]}"
        _META_PRIORITY="${_META_CACHE_PRI[$filepath]}"
        _META_DEPRECATED="${_META_CACHE_DEP[$filepath]}"
        return 0
    fi
    _META_NAME="" _META_DESCRIPTION="" _META_VERSION="0" _META_PRIORITY="99" _META_DEPRECATED=""
    local n=0
    while IFS= read -r _metaline; do
        n=$((n + 1))
        [[ $n -gt 15 ]] && break
        case "$_metaline" in
            '## Name: '*)        _META_NAME="${_metaline#'## Name: '}" ;;
            '## Description: '*) _META_DESCRIPTION="${_metaline#'## Description: '}" ;;
            '## Version: '*)     _META_VERSION="${_metaline#'## Version: '}" ;;
            '## Priority: '*)    _META_PRIORITY="${_metaline#'## Priority: '}" ;;
            '## Deprecated: '*)  _META_DEPRECATED="${_metaline#'## Deprecated: '}" ;;
        esac
    done < "$filepath"
    _META_CACHE_HAVE[$filepath]=1
    _META_CACHE_NAME[$filepath]="$_META_NAME"
    _META_CACHE_DESC[$filepath]="$_META_DESCRIPTION"
    _META_CACHE_VER[$filepath]="$_META_VERSION"
    _META_CACHE_PRI[$filepath]="$_META_PRIORITY"
    _META_CACHE_DEP[$filepath]="$_META_DEPRECATED"
}

# Strategy loader. Every load is a plain `source` of the file: it re-defines
# the file's strategy_detect / strategy_extract AND its helpers (`_strat_*`,
# `_ac_*`, …), so helpers can never go stale, and a strategy file's top level
# holds only constant assignments (regex/table constants), so re-running it
# is idempotent.
#
# PERF (measured): sourcing all ~257 strategy files costs ~0.1s in total.
# The loader used to snapshot each file's functions on first load — two
# `$(declare -F)` command substitutions + a `declare -f` capture per file
# (three forks), plus a `while read … <<< "$(declare -F)"` diff whose
# here-string is a PIPE that bash reads ONE BYTE PER read(2) and whose size
# grows with every strategy loaded (quadratic). That snapshot was ~95% of a
# single-file run's wall time (df -h: ~7.4s of ~7.8s; 1.5M read syscalls)
# while saving ~0.04s per re-load in batch mode (eval vs source parse cost).
# A failed source is memoised, so a broken file is not retried per input.
#
# Re-loads (batch mode runs the whole list once PER INPUT; --multi once per
# block; a hint target loads twice) stay cheap without the snapshot: the
# SECOND load of a file pins its strategy_detect / strategy_extract under
# unique names (two one-time `declare -f` captures) and every later load just
# re-points strategy_detect / strategy_extract at them with two one-line
# trampolines — no re-parse. The file's helpers and constants persist from
# its first source (helper names are unique per file — the per-file-prefix
# convention — so nothing else redefines them).
declare -A _STRAT_FN_STATE=()     # file -> 1 (sourced once) | pinned | bad
declare -A _STRAT_TRAMP=()        # file -> trampoline definitions
_STRAT_PIN_SEQ=0

# _source_strategy_cached FILE [ERRFILE] — make FILE's strategy_detect /
# strategy_extract (and its helper functions) current. Returns 1 if the
# file failed to source (remembered for the life of the process).
_source_strategy_cached () {
    local f="$1" errf="${2:-/dev/null}"
    local st="${_STRAT_FN_STATE[$f]:-}"
    [[ "$st" == "bad" ]] && return 1
    unset -f strategy_detect strategy_extract 2>/dev/null
    if [[ "$st" == "pinned" ]]; then
        eval "${_STRAT_TRAMP[$f]}"
        return 0
    fi
    if ! source "$f" 2>"$errf"; then
        _STRAT_FN_STATE[$f]="bad"
        return 1
    fi
    if [[ -z "$st" ]]; then
        _STRAT_FN_STATE[$f]=1
    else
        _strat_pin "$f"
    fi
    return 0
}

# _strat_pin FILE — copy the just-sourced strategy_detect / strategy_extract to
# __stratN_detect / __stratN_extract and record trampolines that call them.
_strat_pin () {
    local f="$1" _fn _def _tramp="" _id
    _STRAT_PIN_SEQ=$((_STRAT_PIN_SEQ + 1)); _id=$_STRAT_PIN_SEQ
    for _fn in strategy_detect strategy_extract; do
        declare -F "$_fn" >/dev/null || continue
        _def="$(declare -f "$_fn")"
        eval "__strat${_id}_${_fn#strategy_}${_def#"$_fn"}"
        _tramp+="$_fn () { __strat${_id}_${_fn#strategy_} \"\$@\"; }"$'\n'
    done
    _STRAT_TRAMP[$f]="$_tramp"
    _STRAT_FN_STATE[$f]="pinned"
}

# A strategy is "generic" iff it lives in one of the format-level categories.
# Generic = parses a FORMAT (aligned columns, key/value, JSON, YAML, ...),
# never a specific tool's output. Classification is by directory, so it cannot
# drift via a mistagged header: strategies/delimited/ and strategies/structured/
# are generic; every other category is bespoke.
_is_generic_strategy_file () {
    local _parent="${1%/*}"
    case "${_parent##*/}" in
        delimited|structured) return 0 ;;
        *) return 1 ;;
    esac
}

# _collect_strategy_dirs — the strategy search path in the global array
# _STRATEGY_DIRS, in precedence order (a later directory wins a name clash in
# build_strategy_list): the bundled tree, then the per-user ~/.mfe/strategies
# (when it exists), then --plugin-dir (when set and it exists). The single
# definition of the search path — every caller used to spell it out inline.
_collect_strategy_dirs () {
    _STRATEGY_DIRS=("$STRATEGIES_DIR")
    local _user_dir="${HOME:-/nonexistent}/.mfe/strategies"
    [[ -d "$_user_dir" ]] && _STRATEGY_DIRS+=("$_user_dir")
    [[ -n "${_OPT_plugin_dir:-}" && -d "${_OPT_plugin_dir:-}" ]] && _STRATEGY_DIRS+=("$_OPT_plugin_dir")
    return 0
}

# Build a priority-sorted list of strategy files from all strategy directories.
# Output: newline-separated "priority|version|filepath" entries, sorted by priority.
build_strategy_list () {
    local dirs=("$@")
    local list=""
    local names_seen=""

    # Process directories in reverse order (later dirs take precedence)
    local i
    for ((i=${#dirs[@]}-1; i>=0; i--)); do
        local sdir="${dirs[$i]}"
        [[ -d "$sdir" ]] || continue
        for sf in "$sdir"/*.sh "$sdir"/*/*.sh; do
            [[ -f "$sf" ]] || continue
            local sname="${sf##*/}"
            sname="${sname%.sh}"
            # Skip if already seen from higher-precedence directory (O(1) pattern match)
            if [[ $'\n'"$names_seen" == *$'\n'"$sname"$'\n'* ]]; then
                continue
            fi
            names_seen+="$sname"$'\n'
            # In --generic mode, only the format-level categories participate
            if [[ "${_OPT_generic:-0}" -eq 1 ]] && ! _is_generic_strategy_file "$sf"; then
                continue
            fi
            read_strategy_metadata "$sf"
            local _padded="000${_META_PRIORITY}"
            list+="${_padded: -3}|${_META_VERSION}|${sf}|${sname}"$'\n'
        done
    done

    # Sort by priority (numeric), then — the explicit tie-break — by strategy
    # NAME in plain byte order (LC_ALL=C), then by path. Ties used to fall to
    # the full file PATH under the caller's locale, so the category folder a
    # file sat in (and a collating locale like en_US.UTF-8) decided which of
    # two equal-priority strategies ran first. Names are unique (a name clash
    # across directories is resolved above, by precedence), so this order is
    # total and independent of directory layout and locale. Measured on the
    # corpus before adopting: 0 of 3705 winners change, full or --generic.
    echo "${list%$'\n'}" | LC_ALL=C sort -t'|' -k1,1n -k4,4 -k3,3 | cut -d'|' -f1-3
}

list_strategies () {
    _collect_strategy_dirs
    local strategy_dirs=("${_STRATEGY_DIRS[@]}")

    local sorted_list
    sorted_list=$(build_strategy_list "${strategy_dirs[@]}")

    if [[ -z "$sorted_list" ]]; then
        _log_error "No strategies found."
        return 1
    fi

    while IFS='|' read -r priority_val version strategy_file; do
        [[ -z "$strategy_file" ]] && continue
        local name="${strategy_file##*/}"
        name="${name%.sh}"
        read_strategy_metadata "$strategy_file"
        local _generic_marker=""
        _is_generic_strategy_file "$strategy_file" && _generic_marker="[G]"
        printf "  %-20s v%-6s p%-4s %-4s %s\n" "$name" "${_META_VERSION:-?}" "${_META_PRIORITY:-99}" "$_generic_marker" "${_META_DESCRIPTION:-No description}"
    done <<< "$sorted_list"
}

# ENV-016: search strategies by keyword across Name, Description, Technique, and category.
# Takes an array of keywords (AND semantics). Empty keywords list => match all.
# Honors globals: _OPT_search_case_sensitive, _OPT_search_category.
# Sets _SEARCH_MATCH_COUNT to number of matches. Returns 0 if any match, 1 if none.
search_strategies () {
    local -a keywords=("$@")
    _collect_strategy_dirs
    local strategy_dirs=("${_STRATEGY_DIRS[@]}")

    local sorted_list
    sorted_list=$(build_strategy_list "${strategy_dirs[@]}")
    _SEARCH_MATCH_COUNT=0
    if [[ -z "$sorted_list" ]]; then
        _log_error "No strategies found."
        return 1
    fi

    local case_sensitive="${_OPT_search_case_sensitive:-0}"
    local category_filter="${_OPT_search_category:-}"

    # Header row
    printf "  %-14s %-22s %-4s %s\n" "CATEGORY" "NAME" "PRI" "DESCRIPTION"
    printf "  %-14s %-22s %-4s %s\n" "--------" "----" "---" "-----------"

    while IFS='|' read -r priority_val version strategy_file; do
        [[ -z "$strategy_file" ]] && continue
        local name="${strategy_file##*/}"
        name="${name%.sh}"

        # Category is the parent directory name (e.g. .../structured/json.sh -> structured)
        local parent_dir="${strategy_file%/*}"
        local category="${parent_dir##*/}"

        # Filter by --category if provided
        if [[ -n "$category_filter" ]]; then
            if [[ "$case_sensitive" -eq 0 ]]; then
                [[ "${category,,}" == "${category_filter,,}" ]] || continue
            else
                [[ "$category" == "$category_filter" ]] || continue
            fi
        fi

        read_strategy_metadata "$strategy_file"
        # Build the haystack — fields used for matching
        local haystack="${name} ${_META_NAME:-} ${_META_DESCRIPTION:-} ${category}"
        if [[ "$case_sensitive" -eq 0 ]]; then
            haystack="${haystack,,}"
        fi

        # AND semantics: every keyword must match somewhere in haystack
        local match=1 kw
        for kw in "${keywords[@]}"; do
            local needle="$kw"
            [[ "$case_sensitive" -eq 0 ]] && needle="${needle,,}"
            if [[ "$haystack" != *"$needle"* ]]; then
                match=0
                break
            fi
        done

        if [[ $match -eq 1 ]]; then
            _SEARCH_MATCH_COUNT=$((_SEARCH_MATCH_COUNT + 1))
            printf "  %-14s %-22s %-4s %s\n" "$category" "$name" "${_META_PRIORITY:-99}" "${_META_DESCRIPTION:-No description}"
        fi
    done <<< "$sorted_list"

    if [[ "$_SEARCH_MATCH_COUNT" -eq 0 ]]; then
        return 1
    fi
    return 0
}

# Find a strategy file by name across all strategy directories.
# Sets _FOUND_STRATEGY_FILE to the path, or "" if not found.
find_strategy_file () {
    local name="$1"
    _FOUND_STRATEGY_FILE=""
    local sdir sf
    _collect_strategy_dirs
    for sdir in "${_STRATEGY_DIRS[@]}"; do
        [[ -d "$sdir" ]] || continue
        # Check flat directory first, then one level of subdirectories
        if [[ -f "$sdir/${name}.sh" ]]; then
            _FOUND_STRATEGY_FILE="$sdir/${name}.sh"
            return 0
        fi
        for sf in "$sdir"/*/"${name}.sh"; do
            if [[ -f "$sf" ]]; then
                _FOUND_STRATEGY_FILE="$sf"
                return 0
            fi
        done
    done
    return 1
}

# Run chained strategies: pipe output of A into B.
# Sets globals: output, matched_strategies
run_chain_strategies () {
    local chain_input="$text"
    local chain_output=""
    local chain_matched=""

    # ENV-172: read the |-separated chain list into an array via
    # `read -r -a` rather than the `for cs in $_OPT_chain` form. The
    # legacy form word-split on `|` correctly (because of `IFS='|'`)
    # but ALSO glob-expanded the unquoted variable against CWD, so a
    # `--chain '*.sh'` would have resolved to whatever `*.sh` files
    # were sitting in the cwd before iteration began.
    local _chain_arr=()
    IFS='|' read -r -a _chain_arr <<< "$_OPT_chain"
    local chain_list=""
    local cs
    for cs in "${_chain_arr[@]}"; do
        chain_list+="$cs"$'\n'
    done

    while IFS= read -r chain_strat; do
        [[ -z "$chain_strat" ]] && continue

        # Find strategy file and read its metadata (for version tracking)
        if ! find_strategy_file "$chain_strat"; then
            _log_error "Strategy not found: $chain_strat"
            exit 1
        fi
        read_strategy_metadata "$_FOUND_STRATEGY_FILE"
        local _chain_version="${_META_VERSION:-0}"

        # ENV-160: mktemp + umask 077 instead of the predictable
        # `${TMPDIR:-/tmp}/_mfe_src_err.$$` (symlink-attack vector).
        local _old_umask _src_tmpf
        _old_umask=$(umask); umask 077
        _src_tmpf=$(mktemp "${TMPDIR:-/tmp}/mfe_src_err.XXXXXX") || { umask "$_old_umask"; exit 1; }
        umask "$_old_umask"
        if ! source "$_FOUND_STRATEGY_FILE" 2>"$_src_tmpf"; then
            _log_warn "Failed to source chain strategy: $chain_strat"
            [[ -s "$_src_tmpf" ]] && _log_debug "Source error: $(cat "$_src_tmpf")"
            rm -f "$_src_tmpf"
            exit 1
        fi
        [[ -s "$_src_tmpf" ]] && _log_debug "Source warnings for '$chain_strat': $(cat "$_src_tmpf")"
        rm -f "$_src_tmpf"

        if type -t strategy_extract &>/dev/null; then
            chain_output=$(strategy_extract "$chain_input")
            if [[ -z "$chain_output" ]]; then
                _log_error "Chain strategy '$chain_strat' produced no output"
                exit 1
            fi
            # For next strategy, convert field values back to text
            chain_input=""
            while IFS= read -r _cline; do
                [[ -z "$_cline" ]] && continue
                _cline="${_cline#* }"
                _cline="${_cline//_/ }"
                chain_input+="$_cline"$'\n'
            done <<< "$chain_output"
            chain_input="${chain_input%$'\n'}"
        fi
        unset -f strategy_detect strategy_extract 2>/dev/null

        if [[ -n "$chain_strat" ]]; then
            [[ -n "$chain_matched" ]] && chain_matched+=","
            chain_matched+="${chain_strat}@${_chain_version}"
        fi
    done <<< "$chain_list"

    output=""
    matched_strategies="$chain_matched"

    if [[ -n "$chain_output" ]]; then
        store "$chain_output" "STRAT-chain"
    fi
}

# --- Declarative tool hints -------------------------------------------------
# extract/hints.tsv routes a recognized tool's output to an existing GENERIC
# strategy, replacing a per-tool parser script with one data row. Line format
# (TAB-separated, "#" comments and blank lines allowed):
#
#   tool <TAB> match-type <TAB> pattern <TAB> strategy
#
#   match-type: prefix   — first non-blank input line starts with pattern
#               contains — pattern appears anywhere in the input
#               regex    — the input matches the bash ERE pattern
#
# First matching row wins. The hinted strategy runs before auto-detection and
# BYPASSES its own strategy_detect — the hint row IS the detection. If it
# extracts nothing, normal auto-detection proceeds. The extraction reports the
# TOOL name (via _STRATEGY_REPORT_NAME), so the dataset keeps its tool identity
# without a bespoke parser script.

# _hint_required_literal ERE — a LITERAL string every match of the bash ERE
# must contain, in _HRL ("" when none can be proven). Conservative by
# construction: only top-level literal characters that are not optional
# (no `*`, `?` or `{…}` after them) join a run, a `+` ends the run after its
# character, and anything else — a bracket, group, `.`, anchor, `\w`-style
# escape — ends the run. A top-level `|`, a non-ASCII byte, or anything the
# scan does not understand yields "" (no prefilter). The longest run wins.
_HRL_PRINTABLE=' !"#$%&'"'"'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\]^_`abcdefghijklmnopqrstuvwxyz{|}~'
_hint_required_literal () {
    local p="$1" n=${#1} i=0 c d run="" best="" lit depth j
    _HRL=""
    while (( i < n )); do
        c="${p:i:1}"
        [[ "$_HRL_PRINTABLE" == *"$c"* ]] || return 0
        lit=""
        case "$c" in
            '\')
                d="${p:i+1:1}"
                [[ -n "$d" && "$_HRL_PRINTABLE" == *"$d"* ]] || return 0
                if [[ "$d" == [0-9A-Za-z] ]]; then lit=""; else lit="$d"; fi
                i=$((i + 2)) ;;
            '[')
                j=$((i + 1))
                [[ "${p:j:1}" == '^' ]] && j=$((j + 1))
                [[ "${p:j:1}" == ']' ]] && j=$((j + 1))
                while (( j < n )); do
                    if [[ "${p:j:2}" == '[:' || "${p:j:2}" == '[=' || "${p:j:2}" == '[.' ]]; then
                        d="${p:j+1:1}"; j=$((j + 2))
                        while (( j < n )) && [[ "${p:j:2}" != "$d]" ]]; do j=$((j + 1)); done
                        (( j < n )) || return 0
                        j=$((j + 2)); continue
                    fi
                    [[ "${p:j:1}" == ']' ]] && break
                    j=$((j + 1))
                done
                (( j < n )) || return 0
                i=$((j + 1)) ;;
            '(')
                depth=1; j=$((i + 1))
                while (( j < n && depth > 0 )); do
                    case "${p:j:1}" in
                        '\') j=$((j + 2)); continue ;;
                        '(') depth=$((depth + 1)) ;;
                        ')') depth=$((depth - 1)) ;;
                        '[') return 0 ;;          # keep the group scan simple
                    esac
                    j=$((j + 1))
                done
                (( depth == 0 )) || return 0
                i=$j ;;
            '.'|'^'|'$') i=$((i + 1)) ;;
            '|'|')'|'*'|'+'|'?'|'{') return 0 ;;
            *) lit="$c"; i=$((i + 1)) ;;
        esac
        # quantifier after the atom
        d="${p:i:1}"
        case "$d" in
            '*'|'?'|'{')
                if [[ "$d" == '{' ]]; then
                    # `X{m,…}` with m >= 1: X repeated m times is required
                    local _hm="${p:i+1}" _hk
                    _hm="${_hm%%[!0-9]*}"
                    j=$i
                    while (( i < n )) && [[ "${p:i:1}" != '}' ]]; do i=$((i + 1)); done
                    (( i < n )) || return 0
                    i=$((i + 1))
                    [[ "${p:i:1}" == [*+?{] ]] && return 0
                    if [[ -n "$lit" && -n "$_hm" ]] && (( 10#$_hm >= 1 && 10#$_hm <= 16 )); then
                        for ((_hk = 0; _hk < 10#$_hm; _hk++)); do run+="$lit"; done
                    fi
                    (( ${#run} > ${#best} )) && best="$run"
                    run=""
                    continue
                fi
                lit=""
                i=$((i + 1))
                [[ "${p:i:1}" == [*+?{] ]] && return 0
                (( ${#run} > ${#best} )) && best="$run"
                run=""
                continue ;;
            '+')
                i=$((i + 1))
                [[ "${p:i:1}" == [*+?{] ]] && return 0
                run+="$lit"
                (( ${#run} > ${#best} )) && best="$run"
                run=""
                continue ;;
        esac
        if [[ -n "$lit" ]]; then
            run+="$lit"
        else
            (( ${#run} > ${#best} )) && best="$run"
            run=""
        fi
    done
    (( ${#run} > ${#best} )) && best="$run"
    _HRL="$best"
    return 0
}

# _hint_first_atom ERE — for a `^`-anchored ERE whose first atom is required
# (a literal, an escaped character or a bracket expression, not followed by
# `*`, `?` or a `{0…}` bound), _HFA is `^ATOM`: a regex the input's FIRST
# CHARACTER must match for the ERE to match at all (bash `=~` without
# REG_NEWLINE anchors `^` at the start of the string only). "" otherwise.
_hint_first_atom () {
    local p="$1" a="" q j
    _HFA=""
    [[ "$p" == '^'* ]] || return 0
    # a top-level `|` makes the anchor apply to one branch only: no claim
    if [[ "$p" == *'|'* ]]; then
        local _i=0 _d=0 _c
        while (( _i < ${#p} )); do
            _c="${p:_i:1}"
            case "$_c" in
                '\') _i=$((_i + 2)); continue ;;
                '[') _i=$((_i + 1))
                     [[ "${p:_i:1}" == '^' ]] && _i=$((_i + 1))
                     [[ "${p:_i:1}" == ']' ]] && _i=$((_i + 1))
                     while (( _i < ${#p} )) && [[ "${p:_i:1}" != ']' ]]; do
                         [[ "${p:_i:2}" == '[:' || "${p:_i:2}" == '[=' || "${p:_i:2}" == '[.' ]] && return 0
                         _i=$((_i + 1))
                     done ;;
                '(') _d=$((_d + 1)) ;;
                ')') _d=$((_d - 1)) ;;
                '|') [[ $_d -eq 0 ]] && return 0 ;;
            esac
            _i=$((_i + 1))
        done
    fi
    p="${p:1}"
    case "${p:0:1}" in
        '\')
            [[ "${p:1:1}" == [A-Za-z0-9] || -z "${p:1:1}" ]] && return 0
            a="${p:0:2}" ;;
        '[')
            j=1
            [[ "${p:j:1}" == '^' ]] && j=$((j + 1))
            [[ "${p:j:1}" == ']' ]] && j=$((j + 1))
            while (( j < ${#p} )); do
                if [[ "${p:j:2}" == '[:' || "${p:j:2}" == '[=' || "${p:j:2}" == '[.' ]]; then
                    q="${p:j+1:1}"; j=$((j + 2))
                    while (( j < ${#p} )) && [[ "${p:j:2}" != "$q]" ]]; do j=$((j + 1)); done
                    (( j < ${#p} )) || return 0
                    j=$((j + 2)); continue
                fi
                [[ "${p:j:1}" == ']' ]] && break
                j=$((j + 1))
            done
            (( j < ${#p} )) || return 0
            a="${p:0:j+1}" ;;
        [A-Za-z0-9\ \#:/,=@%_-]) a="${p:0:1}" ;;
        *) return 0 ;;
    esac
    q="${p:${#a}:1}"
    case "$q" in
        '*'|'?') return 0 ;;
        '{') [[ "${p:${#a}+1:1}" == [1-9] ]] || return 0 ;;
    esac
    _HFA="^$a"
}

# _hint_presence TEXT — for a BIG input, one awk pass decides which hint
# LITERALS (a `contains` pattern, or a regex's _hint_required_literal) occur
# anywhere in TEXT: _HINT_ABSENT[literal]=1 for each one that does not. A
# `contains` row is then answered from the map, and a regex row whose
# required literal is absent cannot match, so its full-text bash regex is
# skipped; every other row runs exactly as before. (Literals hold no newline,
# so "occurs in the text" is "occurs in some line".) ~100 full-text scans of
# a 10 MB input cost ~7 s; this pass costs one.
declare -A _HINT_ABSENT=()
declare -A _HINT_REQLIT=()
declare -A _HINT_FIRSTATOM=()
_HINT_REQLIT_OK=0
_HINT_PRESENCE_OK=0
_hint_presence () {
    _HINT_ABSENT=()
    local tool mtype pattern strategy _rest _lits="" _l
    _HINT_FIRSTCHAR="${1:0:1}"
    if [[ $_HINT_REQLIT_OK -eq 0 ]]; then
        while IFS=$'\t' read -r tool mtype pattern strategy _rest; do
            [[ "$mtype" == regex && -n "$pattern" ]] || continue
            _hint_required_literal "$pattern"
            _HINT_REQLIT[$pattern]="$_HRL"
            _hint_first_atom "$pattern"
            _HINT_FIRSTATOM[$pattern]="$_HFA"
        done < "$HINTS_FILE"
        _HINT_REQLIT_OK=1
    fi
    local -A _seen=()
    while IFS=$'\t' read -r tool mtype pattern strategy _rest; do
        [[ -z "$tool" || "$tool" == \#* || -z "$pattern" || -z "$strategy" ]] && continue
        case "$mtype" in
            contains) _l="$pattern" ;;
            regex)    _l="${_HINT_REQLIT[$pattern]:-}" ;;
            *)        continue ;;
        esac
        [[ -n "$_l" && "$_l" != *$'\001'* && -z "${_seen[$_l]:-}" ]] || continue
        _seen[$_l]=1
        _lits+="$_l"$'\n'
    done < "$HINTS_FILE"
    [[ -n "$_lits" ]] || return 0
    local _absent
    _absent="$(_fr_absent_literals "$1" "${_lits%$'\n'}")" || return 0
    local -a _al=()
    [[ -n "$_absent" ]] && mapfile -t _al <<< "$_absent"
    for _l in ${_al[@]+"${_al[@]}"}; do _HINT_ABSENT[$_l]=1; done
    _HINT_PRESENCE_OK=1
}

# Match the input against hints.tsv.
# Sets _HINT_TOOL and _HINT_STRATEGY on a match. Returns 0 on match, 1 otherwise.
_match_hint () {
    local text="$1"
    _HINT_TOOL="" _HINT_STRATEGY=""
    [[ "${_OPT_no_hints:-0}" -eq 1 ]] && return 1
    [[ -f "${HINTS_FILE:-}" ]] || return 1
    local _mh_first="" _mh_line _mh_src="$text" _mh_found=0
    if (( ${#text} > 65536 )); then
        # BIG input: look for the first non-blank line among the WHOLE lines
        # of a 64 KB prefix (the here-string below copies the entire text);
        # none there — fall back to the full text, so the answer is exact.
        _mh_src="${text:0:65536}"
        [[ "$_mh_src" == *$'\n'* ]] && _mh_src="${_mh_src%$'\n'*}" || _mh_src=""
    fi
    while IFS= read -r _mh_line; do
        [[ -n "${_mh_line//[[:space:]]/}" ]] && { _mh_first="$_mh_line"; _mh_found=1; break; }
    done <<< "$_mh_src"
    if [[ $_mh_found -eq 0 && ${#_mh_src} -ne ${#text} ]]; then
        while IFS= read -r _mh_line; do
            [[ -n "${_mh_line//[[:space:]]/}" ]] && { _mh_first="$_mh_line"; break; }
        done <<< "$text"
    fi
    # BIG input: decide literal presence for every row in one pass (exact —
    # see _hint_presence); small inputs keep the per-row full-text tests.
    _HINT_PRESENCE_OK=0
    if (( ${#text} > _FR_BIG_BYTES )); then _hint_presence "$text"; fi
    local tool mtype pattern strategy _rest
    while IFS=$'\t' read -r tool mtype pattern strategy _rest; do
        [[ -z "$tool" || "$tool" == \#* ]] && continue
        [[ -z "$pattern" || -z "$strategy" ]] && continue
        case "$mtype" in
            prefix)   [[ "$_mh_first" == "$pattern"* ]] || continue ;;
            contains)
                if [[ $_HINT_PRESENCE_OK -eq 1 && "$pattern" != *$'\001'* ]]; then
                    [[ -z "${_HINT_ABSENT[$pattern]:-}" ]] || continue
                else
                    [[ "$text" == *"$pattern"* ]] || continue
                fi ;;
            regex)
                if [[ $_HINT_PRESENCE_OK -eq 1 && -n "${_HINT_REQLIT[$pattern]:-}" ]] \
                   && [[ -n "${_HINT_ABSENT[${_HINT_REQLIT[$pattern]}]:-}" ]]; then
                    continue
                fi
                # an anchored pattern whose first atom rejects the first
                # character cannot match anywhere
                if [[ $_HINT_PRESENCE_OK -eq 1 && -n "${_HINT_FIRSTATOM[$pattern]:-}" ]]; then
                    local _hfa_re="${_HINT_FIRSTATOM[$pattern]}"
                    [[ "$_HINT_FIRSTCHAR" =~ $_hfa_re ]] || continue
                fi
                [[ "$text" =~ $pattern ]] || continue ;;
            *)        continue ;;
        esac
        _HINT_TOOL="$tool"
        _HINT_STRATEGY="$strategy"
        return 0
    done < "$HINTS_FILE"
    return 1
}

# Hint fast-path: on a hints.tsv match, run the hinted generic strategy first.
# Returns: 1 = no hint fired / produced nothing (continue auto-detection),
#          2 = hint produced output and the strategy cap was hit (stop).
#          0 = hint produced output, no cap hit (continue loop; dedup applies).
_run_hint_strategy () {
    _match_hint "$text" || return 1
    if ! find_strategy_file "$_HINT_STRATEGY"; then
        _log_warn "hint '$_HINT_TOOL': strategy '$_HINT_STRATEGY' not found"
        return 1
    fi
    # A hint may route to a bespoke strategy (detection routing), but --generic
    # promises format-level parsers only — honor only generic targets there.
    if [[ "${_OPT_generic:-0}" -eq 1 ]] && ! _is_generic_strategy_file "$_FOUND_STRATEGY_FILE"; then
        _log_debug "hint '$_HINT_TOOL': target '$_HINT_STRATEGY' is bespoke; skipped under --generic"
        return 1
    fi
    read_strategy_metadata "$_FOUND_STRATEGY_FILE"
    if ! _source_strategy_cached "$_FOUND_STRATEGY_FILE" /dev/null; then
        _log_warn "hint '$_HINT_TOOL': failed to source strategy '$_HINT_STRATEGY'"
        return 1
    fi
    _log_debug "hint '$_HINT_TOOL' matched: forcing strategy '$_HINT_STRATEGY'"
    _STRATEGY_CONFIDENCE=95
    _STRATEGY_REPORT_NAME="$_HINT_TOOL"
    local _had_output_before="$strategies_matched" _rhs_rc=0
    # A hint row is explicit routing knowledge: the truncation guard must not
    # second-guess it, or hints stop being usable as an override.
    _TG_EXEMPT=1
    _extract_and_store "$_HINT_STRATEGY" "${_META_VERSION:-0}" || _rhs_rc=$?
    _TG_EXEMPT=0
    # No _strat_* helper sweep here: the cached loader re-defines a file's own
    # functions on every load, so helpers cannot go stale — and the old
    # `< <(declare -F)` sweep was a fork per strategy per input.
    unset -f strategy_detect strategy_extract 2>/dev/null
    _STRATEGY_REPORT_NAME=""
    [[ $_rhs_rc -eq 2 ]] && return 2
    [[ "$strategies_matched" -gt "$_had_output_before" ]] && return 0
    return 1
}

# Resolve the sorted strategy list for the current run.
# Uses --strategy fast path or full build_strategy_list.
# Sets _SORTED_STRATEGIES global.
_resolve_strategy_list () {
    local strategy_dirs=("$@")
    _SORTED_STRATEGIES=""

    # Memoise the directory scan + sort: in batch mode this runs once per
    # input over an identical directory set. Keyed on dirs + generic flag;
    # the single-strategy fast path below is cheap and stays uncached.
    local _rsl_key="${_OPT_generic:-0}|${strategy_dirs[*]}"
    if [[ -z "$_OPT_strategy" && "$_rsl_key" == "${_SORTED_STRATEGIES_KEY:-}" && -n "${_SORTED_STRATEGIES_CACHE:-}" ]]; then
        _SORTED_STRATEGIES="$_SORTED_STRATEGIES_CACHE"
        return 0
    fi

    if [[ -n "$_OPT_strategy" && -z "$_OPT_replay" ]]; then
        # Fast path: locate single strategy via find_strategy_file
        if find_strategy_file "$_OPT_strategy"; then
            read_strategy_metadata "$_FOUND_STRATEGY_FILE"
            local _padded="000${_META_PRIORITY}"
            _SORTED_STRATEGIES="${_padded: -3}|${_META_VERSION}|${_FOUND_STRATEGY_FILE}"
            return 0
        fi
        _log_error "Strategy not found: $_OPT_strategy"
        exit 1
    else
        _SORTED_STRATEGIES=$(build_strategy_list "${strategy_dirs[@]}")
        _SORTED_STRATEGIES_KEY="$_rsl_key"
        _SORTED_STRATEGIES_CACHE="$_SORTED_STRATEGIES"
    fi
}

# Parse replay spec "name@ver,name@ver" into newline-separated lists.
# Sets _REPLAY_STRATEGIES (names) and _REPLAY_VERSIONS (name=version pairs).
_parse_replay_spec () {
    _REPLAY_STRATEGIES=""
    _REPLAY_VERSIONS=""
    if [[ -z "$_OPT_replay" ]]; then return; fi
    local _remaining="$_OPT_replay"
    while [[ -n "$_remaining" ]]; do
        local _entry="${_remaining%%,*}"
        if [[ "$_remaining" == *,* ]]; then
            _remaining="${_remaining#*,}"
        else
            _remaining=""
        fi
        local _rname="${_entry%%@*}"
        _REPLAY_STRATEGIES+="$_rname"$'\n'
        # Preserve version if present (name@version)
        if [[ "$_entry" == *"@"* ]]; then
            local _rver="${_entry#*@}"
            _REPLAY_VERSIONS+="${_rname}=${_rver}"$'\n'
        fi
    done
}

# Check replay version match for a strategy.
# Warns on stderr if the installed version differs from the replay spec.
_check_replay_version () {
    local strategy_name="$1" installed_version="$2"
    if [[ -z "$_REPLAY_VERSIONS" ]]; then return; fi
    local _rv_line
    while IFS= read -r _rv_line; do
        [[ -z "$_rv_line" ]] && continue
        local _rv_name="${_rv_line%%=*}"
        local _rv_ver="${_rv_line#*=}"
        if [[ "$_rv_name" == "$strategy_name" && -n "$_rv_ver" ]]; then
            if [[ "$_rv_ver" != "$installed_version" ]]; then
                _log_warn "Replay: strategy '$strategy_name' version mismatch (requested: $_rv_ver, installed: $installed_version)"
            fi
            return
        fi
    done <<< "$_REPLAY_VERSIONS"
}

# Run custom delimiter as inline strategy.
# Modifies globals: output, strategies_matched, matched_strategies, total_fields.
_run_custom_delimiter () {
    if [[ -z "$_OPT_delimiter" ]]; then return; fi
    local delim_result="" line key value

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        if [[ "$line" == *"$_OPT_delimiter"* ]]; then
            key="${line%%"$_OPT_delimiter"*}"
            value="${line#*"$_OPT_delimiter"}"
            _clean_field "$key"; key="$_CLEANED"
            _clean_value "$value"; value="$_CLEANED"
            [[ -z "$key" || -z "$value" ]] && continue
            delim_result+="${key} ${value}"$'\n'
        fi
    done <<< "$text"

    if [[ -n "$delim_result" ]]; then
        delim_result="${delim_result%$'\n'}"
        store "$delim_result" "STRAT-custom-delimiter"
        strategies_matched=$((strategies_matched + 1))
        if [[ -n "$matched_strategies" ]]; then matched_strategies+=","; fi
        matched_strategies+="custom-delimiter@1.0"  # pseudo-strategy, no file version
        _count_lines "$delim_result"
        total_fields=$((total_fields + _LINE_COUNT))
        _log_debug "Custom delimiter '${_OPT_delimiter}': extracted $_LINE_COUNT fields"
    fi
}

# Check whether a strategy should be run given current filters.
# Returns: 0 if should proceed, 1 if should skip
# Reads globals: _OPT_replay, _REPLAY_STRATEGIES, _OPT_strategy
# Params: $1=strategy_name
_should_run_strategy () {
    local strategy_name="$1"
    if [[ -n "$_OPT_replay" ]]; then
        if [[ $'\n'"$_REPLAY_STRATEGIES"$'\n' != *$'\n'"$strategy_name"$'\n'* ]]; then
            return 1
        fi
    fi
    if [[ -n "$_OPT_strategy" && "$strategy_name" != "$_OPT_strategy" ]]; then
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# BOUNDED DETECTION SAMPLE (perf, very large inputs).
#
# Detection used to hand every detector the WHOLE input, and most detectors
# walk it line by line in bash: a 10 MB table spent ~240 s just rejecting
# ~245 strategies before the winner ran. Above _FR_SAMPLE_BYTES the detectors
# instead see a SAMPLE — the first _FR_SAMPLE_HEAD lines (at most
# _FR_SAMPLE_HEAD_BYTES) plus the last _FR_SAMPLE_TAIL lines (at most
# _FR_SAMPLE_TAIL_BYTES) — whole lines only, newline-joined exactly as
# `$(…)` would hand them over. A strategy that ACCEPTS the sample is then
# re-run on the full text (_detect_strategy), so the confidence that is
# reported and compared to the threshold is always the full-text one, and a
# strategy the full text rejects falls through to the next candidate exactly
# as before. Sampling can therefore only change a winner by making an earlier
# strategy REJECT a sample it would have accepted in full; the corpus proofs
# (see tests/test_detect_sample.sh + CHANGELOG) measure that.
#
# Never sampled (the full text is used):
#   * inputs at or below _FR_SAMPLE_BYTES (every corpus input — they top out
#     near 2 KB — so ordinary captures are untouched);
#   * for the DOCUMENT-GRAMMAR strategies (_FR_DOC_STRATEGIES: json,
#     json-array, jsonl, xml, har, yaml, toml; a plugin strategy that parses
#     whole documents adds its name there) when the first non-blank byte is
#     `{`, `[` or `<`: cutting a document in the middle turns a valid one into
#     an invalid one. Every OTHER detector screens the sample of such an input
#     too (and is re-confirmed on the full text): under confidence ranking the
#     ~135 tool-specific detectors all run, and walking a 10 MB JSON document
#     in bash cost them ~74 s together;
#   * inputs where head + tail would already cover every line, or where the
#     head budget cannot hold even one whole line.
# Knobs (internal, like _FR_BIG_BYTES): export _FR_SAMPLE_BYTES=0 samples
# every input (how the equivalence proofs force it), =-1 disables sampling.
# The sample applies to EVERY detector's input, so it is independent of how
# the winner is chosen (priority order today, confidence ranking tomorrow):
# whatever the selection, a candidate's confidence is its full-text one.
# ---------------------------------------------------------------------------
_FR_SAMPLE_BYTES="${_FR_SAMPLE_BYTES:-32768}"
_FR_SAMPLE_HEAD="${_FR_SAMPLE_HEAD:-120}"
_FR_SAMPLE_TAIL="${_FR_SAMPLE_TAIL:-40}"
_FR_SAMPLE_HEAD_BYTES="${_FR_SAMPLE_HEAD_BYTES:-16384}"
_FR_SAMPLE_TAIL_BYTES="${_FR_SAMPLE_TAIL_BYTES:-4096}"
_FR_DOC_STRATEGIES="${_FR_DOC_STRATEGIES:- json json-array jsonl xml har yaml toml }"
# SAMPLE SLACK. A detector that decides on a SHARE of the lines it sees ("at
# least 60% of lines are label: value", "decline when one token count covers
# 60% of lines") can land on the wrong side of its threshold on the sample
# when the full text sits just on the other side — a false REJECT, which
# would drop a candidate the full text accepts (pkg-config vs deno-info: the
# sample's modal share was exactly 60%, the full text's 59%). Loosening the
# SAMPLE screen can never add a wrong winner, because the full-text run alone
# decides — it can only cost a full-text detect. So while a detector screens
# the sample, _FR_SLACK holds _FR_SAMPLE_SLACK percentage points (else it is
# 0), and every share threshold over the whole text widens by it in the
# accepting direction:
#     needed to accept:  [[ $(( a * 100 / n )) -ge $(( 60 - ${_FR_SLACK:-0} )) ]]
#     reason to decline: [[ $(( a * 100 / n )) -ge $(( 60 + ${_FR_SLACK:-0} )) ]]
# A share over a fixed head window (the first 40 / 60 lines) needs none — the
# sample's head is the full text's head. A new share-threshold detector must
# follow the same rule (extract/README.md "Very large inputs").
# _FR_DET_SAMPLE is 1 during the same screen, for a detector whose check is
# only meaningful on the whole text (it may skip it on the sample: the screen
# can only get looser, the full-text run still decides).
_FR_SAMPLE_SLACK="${_FR_SAMPLE_SLACK:-15}"
[[ "$_FR_SAMPLE_SLACK" =~ ^[0-9]+$ ]] || _FR_SAMPLE_SLACK=15
_FR_SLACK=0
_FR_DET_SAMPLE=0
_DET_SAMPLED=0
_DET_DOC=0
_DET_TEXT=""

# _detect_sample_build — set _DET_TEXT (what the detectors see) and
# _DET_SAMPLED (1 when it is a proper sample of $text) for the current input.
_detect_sample_build () {
    _DET_SAMPLED=0
    _DET_DOC=0
    _DET_TEXT=""
    [[ "$_FR_SAMPLE_BYTES" =~ ^[0-9]+$ ]] || return 0
    (( ${#text} > _FR_SAMPLE_BYTES )) || return 0
    # first non-blank byte (walked, not `${text#"${text%%[![:space:]]*}"}`:
    # that copies the whole big text to read one character)
    local _li=0
    while [[ "${text:_li:1}" == [[:space:]] ]]; do _li=$((_li + 1)); done
    case "${text:_li:1}" in
        '') return 0 ;;
        '{'|'['|'<') _DET_DOC=1 ;;
    esac
    local _s
    _s="$(cat <<< "$text" | awk -v H="$_FR_SAMPLE_HEAD" -v T="$_FR_SAMPLE_TAIL" \
            -v HB="$_FR_SAMPLE_HEAD_BYTES" -v TB="$_FR_SAMPLE_TAIL_BYTES" '
        # head: a contiguous run of whole lines from line 1 within H lines/HB bytes
        !hstop {
            if (NR <= H && hb + length($0) + 1 <= HB) { hd[NR] = $0; hb += length($0) + 1; nh = NR; next }
            hstop = 1
        }
        # tail: a ring of the last T lines
        T > 0 { rg[NR % T] = $0 }
        END {
            if (nh == 0) exit 0                   # no whole line fits: do not sample
            # tail lines, walking back from the end within T lines / TB bytes
            nt = 0; tb = 0
            for (i = NR; i > nh && nt < T; i--) {
                l = rg[i % T]
                if (tb + length(l) + 1 > TB) break
                tb += length(l) + 1; nt++
            }
            if (nh + nt >= NR) exit 0             # head + tail cover it all
            printf "S"
            for (i = 1; i <= nh; i++) printf "\n%s", hd[i]
            for (i = NR - nt + 1; i <= NR; i++) printf "\n%s", rg[i % T]
        }')" || return 0
    [[ "$_s" == S$'\n'* ]] || return 0
    _s="${_s#S$'\n'}"
    # $(...) semantics: the detectors used to see text without trailing newlines
    _s="${_s%"${_s##*[!$'\n']}"}"
    [[ -n "$_s" ]] || return 0
    _DET_TEXT="$_s"
    _DET_SAMPLED=1
}

# ---------------------------------------------------------------------------
# FILE LANE (perf, very large inputs).
#
# Every expansion of a big bash variable costs time proportional to its size
# (bash copies and quote-scans the string: ~15 ns/byte — a 27 MB `output`
# costs ~0.4 s per mention), and the result of a 10 MB capture used to make a
# dozen such trips: `$(strategy_extract …)`, _count_lines, the truncation
# guard, store, dedup, the prefix strip and the formatter each took the text
# as an argument and handed a new copy back. Above _FR_LANE_BYTES the result
# instead goes to a FILE and stays there: strategy_extract writes it, and the
# count, the truncation guard and store read it; store appends to a lane
# output file in place of the `output` variable. Every step runs the same awk
# program as its BIG-variable twin, so the bytes are identical.
#
# At the end of run_auto_strategies the lane output is copied back into
# `output` (byte for byte) unless the caller set _XL_KEEP=1 — only the plain
# single-file `-f tsv` path does (see _xl_can_keep / _xl_finalize), where dedup,
# the prefix strip and the TSV formatter then run file to file too.
# Knob: export _FR_LANE_BYTES=0 routes every input through the lane (how its
# equivalence is proven over the corpus); -1 disables it.
# ---------------------------------------------------------------------------
_FR_LANE_BYTES="${_FR_LANE_BYTES:-65536}"
_XL_OUT=""
_XL_DIR=""
_XL_KEEP=0

# _xl_begin — open the lane for the current input when it is big enough
# (its files live in the private scratch directory, see _fr_scratch).
_xl_begin () {
    _XL_OUT=""
    [[ "$_FR_LANE_BYTES" =~ ^[0-9]+$ ]] || return 0
    (( ${#text} > _FR_LANE_BYTES )) || return 0
    _fr_scratch || return 0
    _XL_DIR="$_FR_SCRATCH"
    _XL_OUT="$_XL_DIR/lane.output"
    : > "$_XL_OUT"
}

# _xl_materialize — copy the lane output into `output` (exactly: it is a run
# of newline-terminated lines, as the variable form would have been) and
# close the lane.
_xl_materialize () {
    [[ -n "$_XL_OUT" ]] || return 0
    local _xm
    _xm="$(cat "$_XL_OUT"; printf .)"
    output+="${_xm%.}"
    _XL_OUT=""
}

# _xl_has_content FILE — does FILE hold a non-empty line?
_xl_has_content () {
    awk 'length($0) { f = 1; exit } END { exit !f }' "$1"
}

# Run strategy detection phase.
# Returns: 0 if strategy detected (or replay/no-detect), 1 if should skip
# Sets: _STRATEGY_CONFIDENCE (via strategy_detect)
# Modifies globals: near_miss_strategies
# Params: $1=strategy_name, $2=strategy_priority
_detect_strategy () {
    local strategy_name="$1" strategy_priority="$2"
    if [[ -n "$_OPT_replay" ]]; then
        return 0
    fi
    if ! type -t strategy_detect &>/dev/null; then
        return 0
    fi
    _STRATEGY_CONFIDENCE=50
    _STRATEGY_CONFIDENCE_REASON=""
    # Cleared before each detect so a per-tool report name set by one strategy
    # (columnar-specs) never leaks to the next strategy's dispatch record.
    _STRATEGY_REPORT_NAME=""
    local _det_screen="${_DET_SAMPLED:-0}"
    if [[ "$_det_screen" -eq 1 && "${_DET_DOC:-0}" -eq 1 ]]; then
        # A document-shaped input: grammar strategies see it whole.
        if [[ "$_FR_DOC_STRATEGIES" == *" $strategy_name "* ]]; then
            _det_screen=0
        fi
    fi
    if [[ "$_det_screen" -eq 1 ]]; then
        # Large input: screen on the bounded sample, then confirm on the full
        # text (see _detect_sample_build) — the full-text run decides and sets
        # the confidence (and any detect→extract state) exactly as before.
        # _FR_SLACK tells a share-threshold detector it is screening a
        # sample (see SAMPLE SLACK above); the full-text run below sees 0.
        local _det_rc=0
        _FR_SLACK="$_FR_SAMPLE_SLACK"; _FR_DET_SAMPLE=1
        strategy_detect "$_DET_TEXT" "${_STATE_filename:-}" "${_STATE_encoding_hint:-}" || _det_rc=$?
        _FR_SLACK=0; _FR_DET_SAMPLE=0
        if [[ $_det_rc -ne 0 ]]; then
            _log_debug "Strategy '$strategy_name' (p${strategy_priority}): not applicable (sample)"
            return 1
        fi
        _STRATEGY_CONFIDENCE=50
        _STRATEGY_CONFIDENCE_REASON=""
        _STRATEGY_REPORT_NAME=""
    fi
    if ! strategy_detect "$text" "${_STATE_filename:-}" "${_STATE_encoding_hint:-}"; then
        _log_debug "Strategy '$strategy_name' (p${strategy_priority}): not applicable"
        return 1
    fi
    # Clamp confidence to valid range 0–100
    if [[ $_STRATEGY_CONFIDENCE -lt 0 ]]; then
        _log_debug "Strategy '$strategy_name': confidence $_STRATEGY_CONFIDENCE clamped to 0"
        _STRATEGY_CONFIDENCE=0
    elif [[ $_STRATEGY_CONFIDENCE -gt 100 ]]; then
        _log_debug "Strategy '$strategy_name': confidence $_STRATEGY_CONFIDENCE clamped to 100"
        _STRATEGY_CONFIDENCE=100
    fi
    if [[ $_STRATEGY_CONFIDENCE -lt $_OPT_min_confidence ]]; then
        _log_debug "Strategy '$strategy_name': confidence $_STRATEGY_CONFIDENCE below threshold $_OPT_min_confidence"
        [[ -n "$near_miss_strategies" ]] && near_miss_strategies+=", "
        near_miss_strategies+="${strategy_name}(c${_STRATEGY_CONFIDENCE})"
        return 1
    fi
    local _reason_info=""
    if [[ -n "$_STRATEGY_CONFIDENCE_REASON" ]]; then
        _reason_info=" reason='$_STRATEGY_CONFIDENCE_REASON'"
    fi
    _log_debug "Strategy '$strategy_name' (p${strategy_priority}, c${_STRATEGY_CONFIDENCE}${_reason_info}): detected as applicable"
    return 0
}

# TRUNCATION GUARD. A strategy that detects confidently, claims the whole
# input, and then emits a fraction of it is the worst failure mode the engine
# has: the loss is silent, and the held-out benchmark showed it three times in
# fifty inputs (git log --stat 40 lines in / 3 fields out, java -XshowSettings
# 24 / 2, apt-cache policy 14 / 4). The parse LOOKS fine — it is just missing
# most of the input.
#
# The tell is cheap to compute and needs no new parsing logic: the parse is
# much SMALLER than its input, and most input lines left no trace in it. Both
# conditions matter. Small-but-covering is legitimate (a wide table emits many
# fields per line, a summary strategy condenses); large-but-partial is the
# aligned-table norm (headers and rules drop). Only small AND blind is
# rejected — the claim is withdrawn and the next strategy in priority order
# gets its turn, exactly as if this one had produced nothing.
#
# Hint-routed strategies are exempt (_TG_EXEMPT): a hint row is explicit
# routing knowledge, and second-guessing it here would make hints unreliable
# as an override. `-s NAME` is exempt for the same reason.
#
# Returns 0 (truncated — reject) only when all gates agree; 1 otherwise.
_parse_is_truncated () {
    local _res="$1" _m="$2" _strat="${3:-}" _resf="${4:-}"
    [[ "${_TG_EXEMPT:-0}" -eq 1 ]] && return 1
    [[ -n "$_OPT_strategy" || -n "$_OPT_replay" ]] && return 1
    # A structured-grammar parser is AUTHORITATIVE about its own format: JSON
    # and YAML legitimately compress (a brace/bracket line carries no data,
    # a nested path folds many lines into one field), and rejecting the only
    # strategy that understands the format leaves EMPTY output — strictly
    # worse than anything it could have been protecting against. caddy-adapt
    # (nested JSON, one leaf) went from parsed to nothing that way.
    case "$_strat" in
        json|yaml|xml|toml) return 1 ;;
    esac
    # Non-blank input lines, cached per input (reset in run_auto_strategies).
    if [[ -z "${_TG_NB_LINES:-}" ]]; then
        _TG_NB_LINES=$(cat <<< "$text" | grep -c '[^ \t]' || true)
    fi
    # Too small to call, or the parse is not small relative to the input.
    [[ "$_TG_NB_LINES" -ge 8 ]] || return 1
    [[ $((_m * 3)) -lt "$_TG_NB_LINES" ]] || return 1
    # Line coverage: an input line is COVERED when more than half its tokens
    # appear somewhere in the parse (names count — a header word promoted to a
    # column name survived). Tokens compare case-folded with edge punctuation
    # stripped, split on underscore as well as whitespace because the engine
    # encodes value-internal spaces as `_` — the same normalisation the parse
    # scorer uses, for the same symmetry reasons.
    local _cov
    local _tg_prog='
        function norm(s) {
            gsub(/^[^A-Za-z0-9]+/, "", s)
            gsub(/[^A-Za-z0-9]+$/, "", s)
            return tolower(s)
        }
        NR == FNR {
            # Output side splits on DOTS as well: a folded field name
            # (`apps.http.servers.srv0`) still vouches for the input lines
            # that carried each component. The input side keeps dots so a
            # literal dotted value must survive whole to count.
            n = split($0, a, /[ \t_.]+/)
            for (i = 1; i <= n; i++) { t = norm(a[i]); if (t != "") seen[t] = 1 }
            next
        }
        {
            n = split($0, a, /[ \t_]+/)
            sig = 0; hit = 0
            for (i = 1; i <= n; i++) {
                t = norm(a[i])
                if (t != "") { sig++; if (t in seen) hit++ }
            }
            if (sig == 0) next
            nl++
            if (hit * 2 > sig) cov++
        }
        END { if (nl == 0) print 100; else printf "%d\n", (cov * 100) / nl }
    '
    if [[ -n "$_resf" ]]; then
        # file lane: the result is already a file
        _cov=$(awk "$_tg_prog" "$_resf" <(printf '%s\n' "$text"))
    else
        _cov=$(awk "$_tg_prog" <(printf '%s\n' "$_res") <(printf '%s\n' "$text"))
    fi
    [[ "$_cov" =~ ^[0-9]+$ ]] || return 1
    _TG_LAST_COVERAGE="$_cov"
    [[ "$_cov" -lt 50 ]]
}

# Run strategy extraction and store results.
# Returns: 0 to continue loop, 2 to break (early exit)
# Modifies globals: output (via store), strategies_matched, matched_strategies,
#   total_fields, near_miss_strategies
# Params: $1=strategy_name, $2=strategy_version
_extract_and_store () {
    local strategy_name="$1" strategy_version="$2"
    if ! type -t strategy_extract &>/dev/null; then
        _log_debug "Strategy '$strategy_name': no strategy_extract function"
        return 0
    fi
    [[ $_OPT_profile -eq 1 ]] && local _prof_start=$SECONDS
    local result _ext_rc=0 _xl_res=""
    if [[ -n "${_XL_OUT:-}" ]]; then
        # FILE LANE: the result goes to a file (a `( … )` subshell with -e
        # cleared, exactly as the `$( … )` form runs it) and stays there.
        _xl_res="$_XL_DIR/lane.result"
        ( set +e; strategy_extract "$text" "${_STATE_filename:-}" "${_STATE_encoding_hint:-}" ) > "$_xl_res" || _ext_rc=$?
        result=""
        _xl_has_content "$_xl_res" && result=1
    else
        result=$(strategy_extract "$text" "${_STATE_filename:-}" "${_STATE_encoding_hint:-}") || _ext_rc=$?
    fi
    if [[ $_ext_rc -ne 0 ]]; then
        _log_debug "Strategy '$strategy_name': strategy_extract exited with code $_ext_rc"
    fi
    if [[ $_OPT_profile -eq 1 ]]; then
        local _prof_elapsed=$(( SECONDS - _prof_start ))
        echo "[profile] Strategy '$strategy_name': ${_prof_elapsed}s" >&2
    fi
    if [[ -n "$result" ]]; then
        if [[ -n "$_xl_res" ]]; then
            _LINE_COUNT=$(awk '$0 != "" { n++ } END { print n + 0 }' "$_xl_res")
        else
            _count_lines "$result"
        fi
        if _parse_is_truncated "$result" "$_LINE_COUNT" "$strategy_name" "$_xl_res"; then
            _log_debug "Strategy '$strategy_name': truncation guard rejected claim ($_LINE_COUNT fields from $_TG_NB_LINES lines, ${_TG_LAST_COVERAGE}% line coverage)"
            [[ -n "$near_miss_strategies" ]] && near_miss_strategies+=", "
            near_miss_strategies+="${strategy_name}(truncated)"
            return 0
        fi
        # A strategy may report a more specific name than its file name — the
        # data-driven `columnar-specs` engine reports the matched TOOL name so
        # each tool keeps its own dataset identity instead of collapsing to
        # `columnar-specs`. Falls back to the file's strategy name.
        local report_name="${_STRATEGY_REPORT_NAME:-$strategy_name}"
        if [[ -n "$_xl_res" ]]; then
            _store_file "$_xl_res" "STRAT-${report_name}"
        else
            store "$result" "STRAT-${report_name}"
        fi
        strategies_matched=$((strategies_matched + 1))
        # ENV-200: record the first strategy that produced output (the dispatch
        # winner) + its confidence, for the opt-in --emit-meta line.
        if [[ -z "${_WINNER_NAME:-}" ]]; then
            _WINNER_NAME="$report_name"
            _WINNER_CONF="${_STRATEGY_CONFIDENCE:-0}"
        fi
        [[ -n "$matched_strategies" ]] && matched_strategies+=","
        matched_strategies+="${report_name}@${strategy_version:-0}"
        # _LINE_COUNT still holds this result's count from the guard above.
        total_fields=$((total_fields + _LINE_COUNT))
        _log_debug "Strategy '$strategy_name': extracted $_LINE_COUNT fields"
        if [[ $_OPT_first_match -eq 1 ]]; then
            _log_debug "--first-match: stopping after '$strategy_name'"
            return 2
        fi
        if [[ $_OPT_max_strategies -gt 0 && $strategies_matched -ge $_OPT_max_strategies ]]; then
            _log_debug "--max-strategies $_OPT_max_strategies reached"
            return 2
        fi
    else
        _log_debug "Strategy '$strategy_name': no fields extracted"
        [[ -n "$near_miss_strategies" ]] && near_miss_strategies+=", "
        near_miss_strategies+="${strategy_name}(empty)"
    fi
    return 0
}

# Run auto-detect or single-strategy extraction.
# Sets globals: output, matched_strategies, near_miss_strategies, strategies_tried, etc.
# A file-lane run (see _xl_begin) leaves its output in `output` like any other
# run, unless the caller asked to keep it in the lane file (_XL_KEEP=1).
# CONFIDENCE CEILINGS (perf, with --rank confidence). A strategy's ceiling is
# the highest _STRATEGY_CONFIDENCE its detect can ever set: its
# `## Confidence-Max: N` header when it computes a score, else the largest
# literal it assigns (and 50, the default _detect_strategy starts from). A
# computed assignment without the header makes the ceiling 100 — never pruned.
# Plugin strategies are scanned the same way. Cached per file per process.
declare -gA _CEIL_CACHE=()
_strategy_ceiling () {
    local f="$1"
    if [[ -z "${_CEIL_CACHE[$f]+x}" ]]; then
        _CEIL_CACHE[$f]="$(awk '
            /^## Confidence-Max:/ { hdr = $3 + 0; have = 1 }
            {
                line = $0; sub(/^[ \t]+/, "", line)
                if (line ~ /^#/) next
                while ((i = index(line, "_STRATEGY_CONFIDENCE=")) > 0) {
                    rest = substr(line, i + 21)
                    if (match(rest, /^[0-9]+/)) {
                        v = substr(rest, 1, RLENGTH) + 0; if (v > mx) mx = v
                    } else computed = 1
                    line = rest
                }
            }
            END {
                if (have) { print hdr; exit }
                if (computed) { print 100; exit }
                print (mx > 50 ? mx : 50)
            }' "$f" 2>/dev/null)"
        [[ "${_CEIL_CACHE[$f]}" =~ ^[0-9]+$ ]] || _CEIL_CACHE[$f]=100
    fi
    _CEIL="${_CEIL_CACHE[$f]}"
}

run_auto_strategies () {
    local _ras_rc=0
    _run_auto_strategies_body || _ras_rc=$?
    if [[ -n "${_XL_OUT:-}" && "${_XL_KEEP:-0}" -ne 1 ]]; then
        _xl_materialize
    fi
    return $_ras_rc
}

_run_auto_strategies_body () {
    if [[ ! -d "$STRATEGIES_DIR" ]]; then
        _log_error "Strategies directory not found: $STRATEGIES_DIR"
        exit 1
    fi

    output=""
    matched_strategies=""
    near_miss_strategies=""
    strategies_tried=0
    strategies_matched=0
    total_fields=0
    # Truncation-guard per-input cache: the non-blank line count is a property
    # of THIS input, and batch mode reuses the process across inputs.
    _TG_NB_LINES=""
    _TG_LAST_COVERAGE=""
    # Bounded detection sample for very large inputs (per input: batch mode
    # reuses the process). Pinned/replayed runs skip detection-by-sample.
    _DET_SAMPLED=0; _DET_TEXT=""
    if [[ -z "$_OPT_strategy" && -z "$_OPT_replay" ]]; then
        _detect_sample_build
    fi
    _xl_begin

    # Collect strategy directories
    _collect_strategy_dirs
    local strategy_dirs=("${_STRATEGY_DIRS[@]}")

    _resolve_strategy_list "${strategy_dirs[@]}"
    if [[ -z "$_SORTED_STRATEGIES" ]]; then
        _log_debug "No strategies found in: ${strategy_dirs[*]}"
        return 0
    fi
    _parse_replay_spec
    _run_custom_delimiter

    # Declarative hint fast-path (auto-detect runs only; --strategy and
    # --replay pin their own strategy set).
    if [[ -z "$_OPT_strategy" && -z "$_OPT_replay" ]]; then
        local _hint_rc=0
        _run_hint_strategy || _hint_rc=$?
        if [[ $_hint_rc -eq 2 ]]; then
            return 0
        fi
    fi

    # ENV-135: total count for progress display. Below the 20-strategy
    # threshold the work is fast enough that progress would be noise; we
    # leave the helper armed but skip ticking. (`--progress` overrides
    # the threshold by leaving _eas_progress_threshold unchecked.)
    local _eas_total
    _eas_total=$(printf '%s\n' "$_SORTED_STRATEGIES" | grep -c '^.')
    local _eas_show_progress=0
    if envoy_progress_active; then
        if [[ "${ENVOY_PROGRESS_OPT_IN:-0}" == "1" || "$_eas_total" -ge 20 ]]; then
            _eas_show_progress=1
        fi
    fi

    local strategy_version strategy_file strategy_name strategy_priority _eas_rc

    # PERF: one private temp file for source-time stderr, reused across every
    # strategy in this run, instead of an mktemp subprocess per strategy (the
    # detection loop sources dozens of strategies — that was ~60 mktemp spawns
    # per invocation). Same symlink-safe umask-077 mktemp as before, just hoisted.
    local _old_umask _src_tmpf
    _old_umask=$(umask); umask 077
    _src_tmpf=$(mktemp "${TMPDIR:-/tmp}/mfe_src_err.XXXXXX") || _src_tmpf=""
    umask "$_old_umask"

    # RANKING (--rank confidence, the default). Phase 1 runs EVERY eligible
    # detector and records each match as a candidate; phase 2 tries the
    # candidates best-first — highest confidence, ties by priority, then by
    # strategy name (LC_ALL=C) — extracting until the strategy cap is hit. A
    # candidate that extracts nothing (or trips the truncation guard) simply
    # yields to the next one, so the winner always has output. Confidence is
    # therefore a RANKING signal, calibrated per the "Confidence rubric" in
    # extract/README.md. `--rank priority` keeps the historical single pass:
    # the first strategy in priority order whose detect passes and whose
    # extract produces output. --strategy / --replay pin their own set and
    # always use the single pass.
    local _eas_rank=1 _eas_cands="" _ck _pk
    [[ "${_OPT_rank:-confidence}" == priority || -n "$_OPT_strategy" || -n "$_OPT_replay" ]] && _eas_rank=0
    # PRUNING (exact). When only the single best candidate is wanted
    # (--max-strategies 1 / --first-match, which is how provost calls the
    # engine), a detector whose CEILING (see _strategy_ceiling) cannot beat the
    # best confidence seen so far is skipped without being sourced: the loop
    # walks priority order, so a later strategy that merely TIES the best
    # loses the tie anyway. If the top candidate then fails to extract, the
    # whole pass is redone without pruning (_EAS_NOPRUNE), so the result is
    # always exactly the unpruned ranking. This is what keeps a 10 MB JSON
    # document fast: once json-array scores 85, no generic parser (<= 80)
    # walks the text.
    local _eas_prune=0 _eas_pruned=0 _eas_best=-1
    if [[ $_eas_rank -eq 1 && "${_EAS_NOPRUNE:-0}" -ne 1 ]] \
       && [[ $_OPT_first_match -eq 1 || $_OPT_max_strategies -eq 1 ]]; then
        _eas_prune=1
    fi

    while IFS='|' read -r _priority strategy_version strategy_file; do
        [[ -z "$strategy_file" ]] && continue

        strategy_name="${strategy_file##*/}"
        strategy_name="${strategy_name%.sh}"
        strategy_priority="${_priority#0}"
        strategy_priority="${strategy_priority:-99}"
        strategies_tried=$((strategies_tried + 1))

        # ENV-135: emit progress *before* sourcing/running the strategy
        # so the user sees "what's running" rather than "what just
        # finished". The helper handles TTY vs non-TTY format internally.
        if [[ "$_eas_show_progress" -eq 1 ]]; then
            envoy_progress_tick "$strategies_tried" "$_eas_total" "$strategy_name"
        fi

        _should_run_strategy "$strategy_name" || continue

        if [[ $_eas_prune -eq 1 && $_eas_best -ge 0 ]]; then
            _strategy_ceiling "$strategy_file"
            if (( _CEIL <= _eas_best )); then
                _eas_pruned=$((_eas_pruned + 1))
                continue
            fi
        fi

        # Check for deprecated strategy
        read_strategy_metadata "$strategy_file"
        if [[ -n "$_META_DEPRECATED" ]]; then
            if [[ -n "$_OPT_strategy" && "$strategy_name" == "$_OPT_strategy" ]]; then
                # Explicitly requested: warn but continue
                _log_warn "Strategy '$strategy_name' is deprecated: $_META_DEPRECATED"
            else
                # Not explicitly requested: skip
                _log_debug "Skipping deprecated strategy '$strategy_name': $_META_DEPRECATED"
                continue
            fi
        fi

        # Check replay version compatibility
        if [[ -n "$_OPT_replay" ]]; then
            _check_replay_version "$strategy_name" "$strategy_version"
        fi

        # Capture source-time stderr into the reused private temp file (see the
        # umask-077 mktemp hoisted above the loop). If it couldn't be created,
        # fall back to discarding stderr rather than spawning a per-strategy one.
        # The cached loader only pays the file read + parse ONCE per process;
        # every later pass (each batch input) reinstates one-line shims.
        if [[ -n "$_src_tmpf" ]]; then
            if ! _source_strategy_cached "$strategy_file" "$_src_tmpf"; then
                _log_warn "Failed to source strategy '$strategy_name', skipping"
                [[ -s "$_src_tmpf" ]] && _log_debug "Source error: $(cat "$_src_tmpf")"
                : > "$_src_tmpf"
                continue
            fi
            [[ -s "$_src_tmpf" ]] && _log_debug "Source warnings for '$strategy_name': $(cat "$_src_tmpf")"
            : > "$_src_tmpf"
        else
            if ! _source_strategy_cached "$strategy_file" /dev/null; then
                _log_warn "Failed to source strategy '$strategy_name', skipping"
                continue
            fi
        fi

        if ! _detect_strategy "$strategy_name" "$strategy_priority"; then
            # No _strat_* helper sweep (see _source_strategy_cached): every
            # load re-defines its file's own functions, and the old
            # `< <(declare -F)` sweep cost a fork per strategy per input.
            unset -f strategy_detect strategy_extract 2>/dev/null
            unset _arr 2>/dev/null
            continue
        fi

        if [[ $_eas_rank -eq 1 ]]; then
            # Sort key: (100 - confidence) ASC, priority ASC, name ASC — all
            # fixed-width so one plain LC_ALL=C sort orders the three keys.
            _ck="000$((100 - _STRATEGY_CONFIDENCE))"
            _pk="000${_priority}"
            _eas_cands+="${_ck: -3}|${_pk: -3}|${strategy_name}|${strategy_version}|${strategy_file}"$'\n'
            (( _STRATEGY_CONFIDENCE > _eas_best )) && _eas_best=$_STRATEGY_CONFIDENCE
            unset -f strategy_detect strategy_extract 2>/dev/null
            unset _arr 2>/dev/null
            continue
        fi

        _eas_rc=0
        _extract_and_store "$strategy_name" "$strategy_version" || _eas_rc=$?
        unset -f strategy_detect strategy_extract 2>/dev/null
        unset _arr 2>/dev/null
        if [[ $_eas_rc -eq 2 ]]; then break; fi
    done <<< "$_SORTED_STRATEGIES"

    if [[ $_eas_rank -eq 1 && -n "$_eas_cands" ]]; then
        # One sort fork per input is the only process the ranking adds.
        _eas_cands="$(printf '%s' "$_eas_cands" | LC_ALL=C sort -t'|' -k1,1 -k2,2 -k3,3)"
        if [[ $_OPT_debug -eq 1 ]]; then
            local _dbg_c="" _dbg_l
            while IFS='|' read -r _ck _pk _dbg_l _; do
                _dbg_c+="${_dbg_c:+, }${_dbg_l}(c$((100 - 10#$_ck)))"
            done <<< "$_eas_cands"
            _log_debug "Ranked candidates: $_dbg_c"
        fi
        local _eas_redo=0
        while IFS='|' read -r _ck _pk strategy_name strategy_version strategy_file; do
            [[ -z "$strategy_file" ]] && continue
            strategy_priority="$((10#$_pk))"
            _source_strategy_cached "$strategy_file" /dev/null || continue
            # Re-run detect: it restores the per-strategy state extract reads
            # (report name, detect-time globals) and the confidence itself.
            # Only the candidates actually tried pay it — normally just one.
            if ! _detect_strategy "$strategy_name" "$strategy_priority"; then
                unset -f strategy_detect strategy_extract 2>/dev/null
                unset _arr 2>/dev/null
                continue
            fi
            _eas_rc=0
            _extract_and_store "$strategy_name" "$strategy_version" || _eas_rc=$?
            unset -f strategy_detect strategy_extract 2>/dev/null
            unset _arr 2>/dev/null
            if [[ $_eas_rc -eq 2 ]]; then break; fi
            # The top candidate yielded nothing. With detectors pruned, one of
            # them might outrank whatever comes next: redo the pass unpruned.
            if [[ $_eas_pruned -gt 0 ]]; then _eas_redo=1; break; fi
        done <<< "$_eas_cands"
        if [[ $_eas_redo -eq 1 ]]; then
            [[ -n "$_src_tmpf" ]] && rm -f "$_src_tmpf"
            _log_debug "Top candidate failed after pruning $_eas_pruned detector(s): redoing unpruned"
            local _eas_rrc=0
            _EAS_NOPRUNE=1 _run_auto_strategies_body || _eas_rrc=$?
            return $_eas_rrc
        fi
    fi
    [[ -n "$_src_tmpf" ]] && rm -f "$_src_tmpf"
    return 0
}

# Explain mode: detect-only dry run showing which strategies match and why.
# Prints a table of strategy name, priority, confidence, and reason.
run_explain_mode () {
    if [[ ! -d "$STRATEGIES_DIR" ]]; then
        _log_error "Strategies directory not found: $STRATEGIES_DIR"
        exit 1
    fi

    _collect_strategy_dirs
    local strategy_dirs=("${_STRATEGY_DIRS[@]}")

    _resolve_strategy_list "${strategy_dirs[@]}"
    if [[ -z "$_SORTED_STRATEGIES" ]]; then
        echo "No strategies found."
        return 0
    fi

    local matched=0 tested=0 skipped=0
    local match_lines="" miss_lines=""

    local strategy_version strategy_file strategy_name strategy_priority

    while IFS='|' read -r _priority strategy_version strategy_file; do
        [[ -z "$strategy_file" ]] && continue

        strategy_name="${strategy_file##*/}"
        strategy_name="${strategy_name%.sh}"
        strategy_priority="${_priority#0}"
        strategy_priority="${strategy_priority:-99}"
        tested=$((tested + 1))

        _should_run_strategy "$strategy_name" || { skipped=$((skipped + 1)); continue; }

        read_strategy_metadata "$strategy_file"
        if [[ -n "$_META_DEPRECATED" ]]; then
            miss_lines="${miss_lines}$(printf '%-7s  %-30s  %4s  %4s  %s' 'DEPR' "$strategy_name" "$strategy_priority" '--' "deprecated: $_META_DEPRECATED")"$'\n'
            skipped=$((skipped + 1))
            continue
        fi

        # ENV-160: mktemp + umask 077 instead of the predictable
        # `${TMPDIR:-/tmp}/_mfe_explain.$$` (symlink-attack vector).
        local _old_umask _src_tmpf
        _old_umask=$(umask); umask 077
        _src_tmpf=$(mktemp "${TMPDIR:-/tmp}/mfe_explain.XXXXXX") || { umask "$_old_umask"; continue; }
        umask "$_old_umask"
        if ! source "$strategy_file" 2>"$_src_tmpf"; then
            miss_lines="${miss_lines}$(printf '%-7s  %-30s  %4s  %4s  %s' 'ERR' "$strategy_name" "$strategy_priority" '--' 'source error')"$'\n'
            rm -f "$_src_tmpf"
            continue
        fi
        rm -f "$_src_tmpf"

        if ! type -t strategy_detect &>/dev/null; then
            unset -f strategy_detect strategy_extract 2>/dev/null
            continue
        fi

        _STRATEGY_CONFIDENCE=50
        _STRATEGY_CONFIDENCE_REASON=""
        if strategy_detect "$text" "${_STATE_filename:-}" "${_STATE_encoding_hint:-}"; then
            [[ $_STRATEGY_CONFIDENCE -lt 0 ]] && _STRATEGY_CONFIDENCE=0
            [[ $_STRATEGY_CONFIDENCE -gt 100 ]] && _STRATEGY_CONFIDENCE=100
            local reason="${_STRATEGY_CONFIDENCE_REASON:-detected}"
            # Sort key first (confidence, priority, name) — the order ranked
            # detection tries the candidates in; cut off before printing.
            match_lines="${match_lines}${_STRATEGY_CONFIDENCE}|${strategy_priority}|${strategy_name}|$(printf '%-7s  %-30s  %4s  %4s  %s' 'MATCH' "$strategy_name" "$strategy_priority" "$_STRATEGY_CONFIDENCE" "$reason")"$'\n'
            matched=$((matched + 1))
        else
            miss_lines="${miss_lines}$(printf '%-7s  %-30s  %4s  %4s  %s' 'MISS' "$strategy_name" "$strategy_priority" '0' 'not applicable')"$'\n'
        fi

        unset -f strategy_detect strategy_extract 2>/dev/null
        while IFS= read -r _ _ _post_fn; do
            case "$_post_fn" in _strat_*) unset -f "$_post_fn" 2>/dev/null ;; esac
        done < <(declare -F)
        unset _arr 2>/dev/null
    done <<< "$_SORTED_STRATEGIES"

    # Print header
    printf '%-7s  %-30s  %4s  %4s  %s\n' "STATUS" "STRATEGY" "PRI" "CONF" "REASON"
    printf '%-7s  %-30s  %4s  %4s  %s\n' "------" "--------" "---" "----" "------"

    # Matches first, in RANK order — confidence desc, then priority, then
    # strategy name (LC_ALL=C), exactly as ranked detection tries them (the
    # first whose extract yields output wins; a hints.tsv row, if one
    # matches, is tried before all of them) — then misses.
    if [[ -n "$match_lines" ]]; then
        printf '%s' "$match_lines" | LC_ALL=C sort -t'|' -k1,1nr -k2,2n -k3,3 | cut -d'|' -f4-
    fi
    if [[ -n "$miss_lines" ]]; then
        printf '%s' "$miss_lines"
    fi

    echo ""
    echo "Tested: $tested  Matched: $matched  Skipped: $skipped"
}
