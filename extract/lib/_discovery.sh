#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Strategy discovery and execution for provost-extract
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
# build_strategy_list): the bundled tree, then the per-user strategies dir
# ${XDG_CONFIG_HOME:-~/.config}/provost/strategies (when it exists), then
# --plugin-dir (when set and it exists). The single definition of the search
# path — every caller used to spell it out inline.
_collect_strategy_dirs () {
    _STRATEGY_DIRS=("$STRATEGIES_DIR")
    local _user_dir="${XDG_CONFIG_HOME:-${HOME:-/nonexistent}/.config}/provost/strategies"
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
        # `${TMPDIR:-/tmp}/provost_src_err.$$` (symlink-attack vector).
        local _old_umask _src_tmpf
        _old_umask=$(umask); umask 077
        _src_tmpf=$(mktemp "${TMPDIR:-/tmp}/provost_src_err.XXXXXX") || { umask "$_old_umask"; exit 1; }
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
# The first matching row whose target can run wins (see the --generic skip).
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
        # Under --generic a bespoke target cannot run, so the row is passed
        # over and a LATER matching row may still route the input: a tool
        # can carry a bespoke routing row for full mode followed by a generic
        # pin for --generic (lsusb -v).
        if [[ "${_OPT_generic:-0}" -eq 1 ]] && find_strategy_file "$strategy" \
           && ! _is_generic_strategy_file "$_FOUND_STRATEGY_FILE"; then
            continue
        fi
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
# _FR_SAMPLE_HEAD_BYTES), MIDDLE WINDOWS, and the last _FR_SAMPLE_TAIL lines
# (at most _FR_SAMPLE_TAIL_BYTES) — whole lines only, in file order,
# newline-joined exactly as `$(…)` would hand them over. A strategy that ACCEPTS the sample is then
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
#   * inputs where head + windows + tail would already cover every line, or
#     where the head budget cannot hold even one whole line.
# MIDDLE WINDOWS (so evidence that lies only mid-input is not hidden from a
# detector that needs it): contiguous blocks of whole lines — a header and
# the rows under it stay together — each at most _FR_SAMPLE_WIN lines /
# _FR_SAMPLE_WIN_BYTES bytes, never overlapping one another or the tail:
#   * EVEN windows: _FR_SAMPLE_MID of them, opening at the first line at or
#     past evenly spaced byte offsets over the body (a representative slice
#     of a uniform body; keeps share-threshold screens honest);
#   * NOVEL windows: up to _FR_SAMPLE_NOVEL of them, opening where a line
#     SHAPE (first non-blank byte class, field-count bucket, indent, which of
#     : = , | TAB occur) first appears after the head — a section, a table or
#     a record block that only starts mid-input. A novel window opens up to
#     _FR_SAMPLE_LEAD lines early (its title / header row) and stretches to
#     at most 2 x _FR_SAMPLE_WIN lines while new shapes keep coming.
#   Every junction joins WHOLE records, following the structure the head
#   shows (group lines over indented children / blank-separated records):
#   an even window apart from the sample waits for a record start, a window
#   that runs out of lines finishes the record in hand, and the tail backs up
#   to its record's start — so a junction never glues one group's line to
#   another group's children (a duplicate key to group-children).
#   The sample is a SUPERSET of the head + tail one, so any detector that
#   counts evidence lines only sees more; a uniform 10 MB body adds the
#   even windows alone (the shapes are all in the head). One awk pass, no
#   lines stored but the sample. _FR_SAMPLE_MID=0 _FR_SAMPLE_NOVEL=0 restores
#   the head + tail sample.
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
_FR_SAMPLE_MID="${_FR_SAMPLE_MID:-4}"
_FR_SAMPLE_NOVEL="${_FR_SAMPLE_NOVEL:-4}"
_FR_SAMPLE_WIN="${_FR_SAMPLE_WIN:-16}"
_FR_SAMPLE_WIN_BYTES="${_FR_SAMPLE_WIN_BYTES:-2048}"
_FR_SAMPLE_LEAD="${_FR_SAMPLE_LEAD:-2}"
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
            -v HB="$_FR_SAMPLE_HEAD_BYTES" -v TB="$_FR_SAMPLE_TAIL_BYTES" \
            -v M="$_FR_SAMPLE_MID" -v N="$_FR_SAMPLE_NOVEL" -v L="$_FR_SAMPLE_WIN" \
            -v WB="$_FR_SAMPLE_WIN_BYTES" -v P="$_FR_SAMPLE_LEAD" -v B="$(( ${#text} + 1 ))" '
        # line shape (for NOVEL windows), as one number: the class of the
        # first non-blank byte (lower / upper / digit / which punctuation), a
        # field-count bucket, indented or not, and which of : = , | TAB occur
        # (plain regex tests and arithmetic: mawk does them ~2x faster than
        # index() or building a string key)
        function shape(   c, n) {
            if (NF == 0) return 0
            c = substr($1, 1, 1)
            if (c ~ /[a-z]/) c = 1; else if (c ~ /[A-Z]/) c = 2; else if (c ~ /[0-9]/) c = 3
            else c = 4 + index("!\"#$%&()*+,-./;<=>?@[\\]^_`{|}~", c)
            n = NF; if (n > 8) n = 4; else if (n > 5) n = 3; else if (n > 3) n = 2; else n = (n > 1)
            return c * 320 + n * 64 + ($0 ~ /^[ \t]/) * 32 + ($0 ~ /:/) * 16 + ($0 ~ /=/) * 8 \
                   + ($0 ~ /,/) * 4 + ($0 ~ /\|/) * 2 + ($0 ~ /\t/)
        }
        function blank(s) { return s !~ /[^ \t\r]/ }
        function cont(s) { return s ~ /^[ \t]/ && s ~ /[^ \t\r]/ }   # indented, not blank
        function add(s, n) { nw++; wl[nw] = s; wn[nw] = n; wb += length(s) + 1; wlen++; ls = n }
        BEGIN { if (P > 3) P = 3; W = (M > 0 || N > 0); R = T + L + 1 }
        # head: a contiguous run of whole lines from line 1 within H lines/HB bytes
        !hstop {
            if (NR <= H && hb + length($0) + 1 <= HB) {
                hd[NR] = $0; hb += length($0) + 1; nh = NR
                if (W) {
                    if (N > 0) seen[shape()] = 1
                    # the record structure the junction rules follow, read
                    # off the head: group lines over indented children
                    # (hier), records separated by blank lines (blk)
                    if (blank($0)) { if (nbs) gap = 1 }
                    else { if (gap) blk = 1; nbs = 1; if (cont($0)) hi = 1; else top = 1 }
                }
                next
            }
            hstop = 1; hier = hi && top
            # EVEN windows open at the first line at or past each of M byte
            # offsets: 0, 1/M, 2/M ... of the way from the end of the head to
            # the end (the first one continues the head, so a table that
            # starts there brings more rows)
            for (k = 1; k <= M; k++) tg[k] = hb + (k - 1) * (B - hb) / M
            ek = 1; cum = hb; ls = nh
        }
        # middle windows: contiguous runs of whole lines (L lines / WB bytes
        # each), never overlapping one another; ls = last line sampled
        nh > 0 && W {
            took = 0
            if (cap > 0) {
                if (wb + length($0) + 1 <= WB) {
                    add($0, NR); cap--; took = 1
                    if (N > 0) {
                        s = shape()
                        # a shape first met inside a window stretches it (to
                        # at most 2*L lines) so the block it opens comes too
                        if (!(s in seen)) {
                            seen[s] = 1
                            if (cap < int(L / 2)) cap = int(L / 2)
                            if (cap > 2 * L - wlen) cap = 2 * L - wlen
                        }
                    }
                    if (cap == 0) ext = 1
                } else cap = 0
            } else if (ext) {
                # a window that ran out of lines finishes the record in hand
                # (its indented children / up to the blank line ending it),
                # within 2*L lines and WB bytes: junctions join whole records
                if (wlen < 2 * L && wb + length($0) + 1 <= WB \
                    && ((hier && cont($0)) || (blk && !blank(wl[nw])))) {
                    add($0, NR); took = 1
                    if (N > 0) seen[shape()] = 1
                } else ext = 0
            }
            if (!took) {
                st = 0
                if (ek <= M && cum >= tg[ek]) {
                    st = 1
                    while (ek <= M && cum >= tg[ek]) ek++
                }
                if (N > 0) {
                    s = shape()
                    if (!(s in seen)) {
                        seen[s] = 1
                        if (!st && nn < N) { st = 2; nn++ }
                    }
                }
                # an EVEN window apart from the sample so far waits (at most
                # L lines) for a record start: not a blank line, not an
                # indented child line of hierarchical text
                if (st == 1 || (st == 0 && pend)) {
                    if (NR > ls + 1 && pw < L && (blank($0) || (hier && cont($0)))) { pend = 1; pw++; st = 0 }
                    else st = 1
                }
                if (st && L > 0 && length($0) + 1 <= WB) {
                    wb = 0; wlen = 0; cap = L; pend = 0; pw = 0
                    # opening early (lines no window holds yet): a NOVEL
                    # window takes up to P lines above (title / header row;
                    # in hierarchical text, back to the group line of an
                    # indented novel line, else none); an EVEN one goes back
                    # to a blank line within P lines, so a record starts whole
                    ld = 0
                    if (st == 2) {
                        if (!hier) ld = P
                        else if (cont($0)) for (k = 1; k <= P; k++)
                            if (NR - k > ls && !cont(pv[(NR - k) % 4]) && !blank(pv[(NR - k) % 4])) { ld = k; break }
                    } else for (k = P; k >= 1; k--)
                        if (NR - k > ls && blank(pv[(NR - k) % 4])) { ld = k; break }
                    for (k = ld; k >= 1; k--) {
                        if (NR - k <= ls || cap < 2) continue
                        if (wb + length(pv[(NR - k) % 4]) + 1 + length($0) + 1 > WB) continue
                        add(pv[(NR - k) % 4], NR - k); cap--
                    }
                    add($0, NR); cap--
                    if (cap == 0) ext = 1
                }
            }
            pv[NR % 4] = $0
            cum += length($0) + 1
        }
        # tail: a ring of the last T lines (+ L + 1 above them, for the
        # record-start rule below)
        T > 0 { rg[NR % R] = $0 }
        END {
            if (nh == 0) exit 0                   # no whole line fits: do not sample
            # tail lines, walking back from the end within T lines / TB bytes
            nt = 0; tb = 0
            for (i = NR; i > nh && nt < T; i--) {
                l = rg[i % R]
                if (tb + length(l) + 1 > TB) break
                tb += length(l) + 1; nt++
            }
            # with windows on, the tail starts a record whole too: back to the
            # group line above indented children (hier), or to the blank line
            # above a blank-separated record (blk) — within the ring / bytes
            ot = nt
            if (W && nt > 0) {
                j = NR - nt + 1; want = 0
                if (hier && cont(rg[j % R])) want = 1
                else if (blk && !blank(rg[j % R])) want = 2
                x = tb
                if (want) for (i = j - 1; i > nh && i > NR - R; i--) {
                    l = rg[i % R]
                    if (x + length(l) + 1 > TB) break
                    x += length(l) + 1
                    if ((want == 1 && !cont(l) && !blank(l)) || (want == 2 && blank(l))) { nt = NR - i + 1; tb = x; break }
                }
            }
            # window lines the tail already carries are dropped
            while (nw > 0 && wn[nw] > NR - nt) nw--
            if (nh + nw + nt >= NR) exit 0        # the sample would be every line
            # (a blank line a window or the tail added at a junction is left
            # out when the line before it in the sample is blank already)
            printf "S"
            for (i = 1; i <= nh; i++) printf "\n%s", hd[i]
            pb = blank(hd[nh]); pn = nh
            for (i = 1; i <= nw; i++) {
                if (pb && wn[i] != pn + 1 && blank(wl[i])) continue
                printf "\n%s", wl[i]; pb = blank(wl[i]); pn = wn[i]
            }
            for (i = NR - nt + 1; i <= NR; i++) {
                if (pb && i != pn + 1 && i <= NR - ot && blank(rg[i % R])) continue
                printf "\n%s", rg[i % R]; pb = blank(rg[i % R]); pn = i
            }
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

# LINE COVERAGE — the second quality signal next to confidence.
#
# Confidence says how sure a detector is that it recognises the input; it
# says nothing about how MUCH of the input the extract kept. A strategy that
# recognises one section of a multi-section report (a `--version` banner over
# five algorithm lists, the scalar lines of an env dump over its path lists)
# claims the whole input at full confidence and silently drops the rest, and
# the truncation guard cannot see it when the kept part is wide.
#
# Coverage = the share of the input's non-blank lines that contributed to the
# parse. A line CONTRIBUTED when more than half of its significant tokens
# appear somewhere in the parse (field names count: a header word promoted to
# a column name survived). Tokens split at blanks and at the structural
# punctuation `= : , ; |`, quotes, brackets and `_` — so `KEY=value`,
# `key:value`, `a,b` and `_`-joined names split the same way on both sides —
# with edge punctuation stripped, case-folded; paths, URLs, dotted versions
# and dashed names stay WHOLE, so a dropped `/home/dev/.conda/envs` is not
# vouched for by `home`, `dev` and `envs` elsewhere. Two allowances for parses
# that legitimately cut a token: the parse side also offers each `.` / `/` /
# `-` part of its tokens (a folded `apps.http.servers` name, a
# `Summary.Requests/sec` column), and a dashed input token counts when every
# dash part is present (`glibc-2.34-60.el9` split into name and version). A
# token is SIGNIFICANT when it holds a letter or is at least 3 characters
# long: a dropped `colorama==0.4.6` must not pass on its `0` / `4` / `6`; a
# line of nothing but short numbers is judged on all of them. Lines without a
# single token (rules, box glyphs) and lines the tool marks as comments
# (first non-blank byte `#` or `;`) are not counted.
#
# It is a cheap set test — one awk pass over parse + input, no parsing — so
# it can only OVER-estimate: a dropped line whose words all occur elsewhere
# in the parse counts as covered. Low coverage is therefore conclusive.
#
# Measured on inputs up to _FR_COV_BYTES (128 KB; a token set of a 10 MB
# capture costs seconds, and the reports this exists for are small). Above
# it — or for an empty parse — _COV is "" (not measured), which nothing
# treats as low. Sets _COV (0-100 or ""), _COV_LINES (lines counted) and
# _COV_HIT (lines covered).
_FR_COV_BYTES="${_FR_COV_BYTES:-131072}"
[[ "$_FR_COV_BYTES" =~ ^-?[0-9]+$ ]] || _FR_COV_BYTES=131072
_FR_CONS_AWK='
    # ---- COLUMN-TYPE CONSISTENCY (parse side only) ----
    # ctype(v): one letter per cell — E empty/null, I integer, D decimal,
    # N number with a unit (size, rate, duration, percent, 1,234), T date /
    # time / datetime / clock duration, A IP / CIDR / MAC / host:port,
    # H hex / hash / uuid, V version, P path / URL, F flag, O digits and
    # punctuation (`8,1`, `0:0`), W word (one token), X text (several
    # tokens), R rule / box-art debris; Q (dotted quad: IPv4 or version)
    # and U (dotted date or calendar version) count for both readings.
    function ctype(v,   lv, n, i, t, dt, anyd) {
        sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v)
        if (v == "") return "E"
        lv = tolower(v)
        if (lv ~ /^(-+|n\/a|na|none|null|nil|<none>|\(none\)|<nil>|\?|unknown|undefined|\*)$/) return "E"
        # rule / box-art debris: no letter or digit, and a run of 3 of one
        # punctuation byte or any non-ASCII byte (`-----+----`, `│`, `├─`)
        if (lv !~ /[a-z0-9]/ && (lv ~ /[^ -~]/ || lv ~ /(--|==|__|\+\+|~~|\*\*|\.\.|##)[-=_+~*.#]/)) return "R"
        if (index(lv, " ") == 0 && index(lv, "\t") == 0) return ctok(lv)
        # several tokens: a date / time written in words and numbers
        n = split(lv, _ct, /[ \t]+/); dt = 1; anyd = 0
        for (i = 1; i <= n; i++) {
            t = _ct[i]; sub(/,$/, "", t)
            if (t ~ _RE_MON || t ~ _RE_WDAY || t ~ _RE_TIME || t ~ _RE_DATE || t ~ _RE_DTIME) { anyd = 1; continue }
            if (t ~ /^[0-9]+$/ && length(t) <= 4) continue
            if (t ~ /^(am|pm|utc|gmt|z|[a-z][a-z]?[sd]t|[-+][0-9][0-9]:?[0-9][0-9])$/) continue
            dt = 0; break
        }
        if (dt && anyd) return "T"
        # a number and its unit: `12 kB`, `30 ms`, `5 days`, `2 weeks ago`
        if (lv ~ _RE_NUMSP) return (lv ~ / (ago|from now)$/ ? "T" : "N")
        return "X"
    }
    function ctok(t) {
        if (t ~ /^[-+]?[0-9]+$/) return "I"
        if (t ~ /^[-+]?([0-9]+\.[0-9]*|\.[0-9]+)(e[-+]?[0-9]+)?$/) return "D"
        # dotted numbers: 3 parts are a version, or (a 4-digit year at one
        # end) a date or a calendar version; 4 parts an IPv4 or a version
        if (t ~ /^[0-9]+\.[0-9]+\.[0-9]+$/)
            return (t ~ /^([0-9][0-9][0-9][0-9]\.[0-9][0-9]?\.[0-9][0-9]?|[0-9][0-9]?\.[0-9][0-9]?\.[0-9][0-9][0-9][0-9])$/ ? "U" : "V")
        if (t ~ _RE_TIME || t ~ _RE_DATE || t ~ _RE_DTIME || t ~ _RE_MON || t ~ _RE_WDAY || t ~ _RE_MONDAY) return "T"
        if (t ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) return (ip4ok(t) ? "Q" : "V")
        if (t ~ _RE_IP4) return (ip4ok(t) ? "A" : "W")
        if (t ~ _RE_MAC || t ~ _RE_HOSTPORT) return "A"
        if (index(t, ":") && t ~ _RE_IP6) return "A"
        if (t ~ /^0x[0-9a-f]+$/ || (length(t) >= 7 && t ~ /^[0-9a-f]+$/ && t ~ /[a-f]/ && t ~ /[0-9]/) || t ~ _RE_UUID) return "H"
        if (t ~ _RE_NUM) return "N"
        if (t ~ _RE_VER) return "V"
        if (t ~ /^(\/|~\/|~$|\.\.?\/|[a-z]:\\|\\\\)/ || index(t, "://")) return "P"
        if (t ~ /^(yes|no|true|false|on|off|y|n|t|f|enabled|disabled|\+|ok)$/) return "F"
        # digits and punctuation that are no number, date or address
        # (`8,1`, `0:0`, a date cut short as `2026-10-`)
        if (t !~ /[a-z]/ && t ~ /[0-9]/) return "O"
        return "W"
    }
    # every octet of a dotted quad is at most 255
    function ip4ok(t,   q, k, j) {
        sub(/[\/:].*$/, "", t); k = split(t, q, ".")
        for (j = 1; j <= k; j++) if (q[j] + 0 > 255) return 0
        return 1
    }
    function cons_init(   u, mon, wday) {
        u = "[a-z%][a-z]?[a-z]?[a-z]?"
        # a number, its unit, and more duration parts (`1h30m`, `2d3h`)
        _RE_NUM = "^[-+]?[$]?([0-9]+(,[0-9][0-9][0-9])*(\\.[0-9]+)?|\\.[0-9]+)(" u ")?([0-9]+(\\.[0-9]+)?(ms|us|ns|[wdhms]))*(/" u ")?$"
        _RE_NUMSP = "^[-+]?[0-9]+(,[0-9][0-9][0-9])*(\\.[0-9]+)? (%|[kmgtpe]i?b?|bytes?|blocks?|pages?|[kmg]?hz|[kmg]?bps|x|[nuµm]?s|secs?|seconds?|mins?|minutes?|hrs?|hours?|days?|weeks?|months?|yrs?|years?)(/" u ")?( ago| from now)?$"
        mon = "(jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)"
        wday = "(mon|tue|tues|wed|thu|thur|thurs|fri|sat|sun)"
        _RE_MON = "^" mon "[a-z]*\\.?$"
        _RE_WDAY = "^" wday "[a-z]*,?$"
        _RE_MONDAY = "^" mon "[0-9][0-9]?$"
        _RE_TIME = "^([0-9]+-)?[0-9]+:[0-5][0-9](:[0-5][0-9])?([.,][0-9]+)?(am|pm|z)?$"
        _RE_DATE = "^([0-9][0-9][0-9][0-9][-/][0-9][0-9]?[-/][0-9][0-9]?|[0-9][0-9]?[-/][0-9][0-9]?[-/][0-9][0-9]([0-9][0-9])?|[0-9][0-9]?[-/ ]" mon "[a-z]*[-/ ][0-9][0-9]([0-9][0-9])?)$"
        _RE_DTIME = "^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9][t_][0-9][0-9]:[0-9][0-9](:[0-9][0-9])?([.,][0-9]+)?(z|[-+][0-9][0-9]:?[0-9][0-9])?$"
        _RE_IP4 = "^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+(/[0-9]+|:[0-9*]+)?$"
        _RE_IP6 = "^\\[?[0-9a-f]*:[0-9a-f:]*:[0-9a-f.]*(%[a-z0-9]+)?\\]?(/[0-9]+|:[0-9*]+)?$"
        _RE_MAC = "^[0-9a-f][0-9a-f][:-][0-9a-f][0-9a-f][:-][0-9a-f][0-9a-f][:-][0-9a-f][0-9a-f][:-][0-9a-f][0-9a-f][:-][0-9a-f][0-9a-f]$"
        _RE_HOSTPORT = "^(\\*|\\[[0-9a-f:]*\\]|[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+):([0-9]+|\\*)$"
        _RE_UUID = "^[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]-[0-9a-f][0-9a-f][0-9a-f][0-9a-f]-[0-9a-f-]+$"
        _RE_VER = "^v?[0-9]+(:[0-9]+)?(\\.[0-9]+)+([-+~._#a-z0-9]*)?(/v?[0-9]+(\\.[0-9]+)+)?$|^v[0-9]+$|^[0-9]+(\\.[0-9]+)*[-+~](rc|beta|alpha|dev|pre|post|git|el|fc|ubuntu|deb|r)[a-z0-9._~+-]*$"
        _CONS_INIT = 1
    }
    # one parse line: `<label><N>.<field> value` is a cell of column
    # <label>.<field>; anything else (scalars, total_entries) is skipped
    function cons_line(s,   p, k, v, t, i) {
        if (!_CONS_INIT) cons_init()
        if (!match(s, /^[A-Za-z][A-Za-z_]*[0-9]+\./)) return
        p = substr(s, 1, RLENGTH - 1)
        if (!(p in _crec)) { _crec[p] = 1; _cnrec++ }
        sub(/[0-9]+$/, "", p)
        k = substr(s, RLENGTH + 1)
        if ((i = index(k, " ")) > 0) { v = substr(k, i + 1); k = substr(k, 1, i - 1) } else v = ""
        k = p "." k
        t = ctype(v)
        if (t == "E") return
        if (v ~ /[A-Za-z][A-Za-z]/) { _fv[++_fn] = v; _fk[_fn] = k }
        if (!(k in _cn)) { _cn[k] = 0; _ck[++_cnk] = k }
        _cn[k]++
        if (t == "R") return
        if (t == "X") { _cx[k]++; _cf[k, "id"]++; return }
        if (t == "I") { _cf[k, "num"]++; _cf[k, "ver"]++; _cf[k, "hex"]++ }
        else if (t == "D") { _cf[k, "num"]++; _cf[k, "ver"]++ }
        else if (t == "N") _cf[k, "num"]++
        else if (t == "T") _cf[k, "time"]++
        else if (t == "A") _cf[k, "addr"]++
        else if (t == "Q") { _cf[k, "addr"]++; _cf[k, "ver"]++ }
        else if (t == "U") { _cf[k, "time"]++; _cf[k, "ver"]++ }
        else if (t == "H") { _cf[k, "hex"]++; _cf[k, "id"]++ }
        else if (t == "V") { _cf[k, "ver"]++; _cf[k, "id"]++ }
        else if (t == "O") _cf[k, "sym"]++
        else _cf[k, "id"]++
    }
    # one input line: its alphanumeric runs (case-folded) are what a parse
    # cell may hold
    function cons_input(s,   n, j) {
        _cons_inp = 1
        if (_fn == 0) return
        n = split(tolower(s), _ci, /[^a-z0-9]+/)
        for (j = 1; j <= n; j++) if (_ci[j] != "") _it[_ci[j]] = 1
    }
    # a FRAGMENT: a cell holding a word the input never prints whole — the
    # second half of a fixed-column cut through `boost-algorithm` (`lgorithm`)
    # — i.e. an alphanumeric run of 3+ bytes, with a letter, that is no
    # alphanumeric run of the input
    function cons_frag(   i, n, j) {
        for (i = 1; i <= _fn; i++) {
            n = split(tolower(_fv[i]), _ci, /[^a-z0-9]+/)
            for (j = 1; j <= n; j++)
                if (length(_ci[j]) >= 3 && _ci[j] ~ /[a-z]/ && !(_ci[j] in _it)) { _cfr[_fk[i]]++; break }
        }
    }
    # cons_want(name): the type family a column name promises, if any
    function cons_want(nm,   n, j, w) {
        n = split(nm, _cw, /[^a-z%]+/)
        for (j = 1; j <= n; j++) {
            w = _cw[j]
            if (w ~ /^(version|ver)$/) return "ver"
            if (w ~ /^(size|bytes|pid|ppid|uid|gid|rss|vsz|mtu|%cpu|%mem|cpu%|mem%|use%|percent|ratio)$/) return "num"
            if (w ~ /^(date|time|timestamp|created|modified|updated|started)$/) return "time"
        }
        return ""
    }
    # -> "score judged_columns inconsistent_columns judged_cells signature records",
    # the signature listing each clearly typed column as name=family; score "-" when no
    # column can be judged (fewer than 3 filled cells, free text, or a
    # value column of a key/value list)
    function cons_result(   j, k, n, b, bf, f, nm, tot, hit, nc, nbad, sig, sf, sb) {
        tot = 0; hit = 0; nc = 0; nbad = 0
        if (_fn > 0 && _cons_inp) cons_frag()
        # pass 1: each judged column: its best family; families that clearly
        # type some column
        for (j = 1; j <= _cnk; j++) {
            k = _ck[j]; n = _cn[k]
            if (n < 3) continue
            nm = tolower(k); sub(/^[^.]*\./, "", nm); sub(/^.*\./, "", nm)
            if (nm ~ /^(value|values|val|data|setting|content|contents|text|message|msg|description|desc|detail|details|comment|comments|note|notes|line|raw|output|info|summary|title|args|arguments|command|cmd)$/) continue
            b = 0; bf = ""
            if ((k, "num") in _cf && _cf[k, "num"] > b) { b = _cf[k, "num"]; bf = "num" }
            if ((k, "ver") in _cf && _cf[k, "ver"] > b) { b = _cf[k, "ver"]; bf = "ver" }
            if ((k, "hex") in _cf && _cf[k, "hex"] > b) { b = _cf[k, "hex"]; bf = "hex" }
            if ((k, "time") in _cf && _cf[k, "time"] > b) { b = _cf[k, "time"]; bf = "time" }
            if ((k, "addr") in _cf && _cf[k, "addr"] > b) { b = _cf[k, "addr"]; bf = "addr" }
            if ((k, "id") in _cf && _cf[k, "id"] > b) { b = _cf[k, "id"]; bf = "id" }
            if ((k, "sym") in _cf && _cf[k, "sym"] > b) { b = _cf[k, "sym"]; bf = "sym" }
            _jb[k] = b; _jf[k] = bf; _jn[k] = nm; _jk[++_jkn] = k
            if (b * 10 >= n * 8) _dom[bf] = 1
            # signature: the most specific family that types 80% of the
            # column (a version column with one stray cell is `ver`, not
            # the identifier family that also counts versions)
            sf = ""; sb = 0
            if ((k, "num") in _cf && _cf[k, "num"] > sb) { sb = _cf[k, "num"]; sf = "num" }
            if ((k, "ver") in _cf && _cf[k, "ver"] > sb) { sb = _cf[k, "ver"]; sf = "ver" }
            if ((k, "hex") in _cf && _cf[k, "hex"] > sb) { sb = _cf[k, "hex"]; sf = "hex" }
            if ((k, "time") in _cf && _cf[k, "time"] > sb) { sb = _cf[k, "time"]; sf = "time" }
            if ((k, "addr") in _cf && _cf[k, "addr"] > sb) { sb = _cf[k, "addr"]; sf = "addr" }
            if ((k, "sym") in _cf && _cf[k, "sym"] > sb) { sb = _cf[k, "sym"]; sf = "sym" }
            if (sb * 10 < n * 8) sf = (bf == "id" && b * 10 >= n * 8) ? "id" : ""
            if (sf != "") sig = sig (sig == "" ? "" : ",") nm "=" sf
        }
        # pass 2: a column NAMED for a type (`Version`, `Size`, `Created`)
        # whose cells are of another family, while another column holds that
        # type, is a header shifted against its cells: judged by its name
        for (j = 1; j <= _jkn; j++) {
            k = _jk[j]; n = _cn[k]; b = _jb[k]
            f = cons_want(_jn[k])
            if (f != "" && f != _jf[k] && !(f == "time" && _jf[k] == "num") && (f in _dom))
                b = ((k, f) in _cf) ? _cf[k, f] : 0
            if (k in _cfr) { b -= _cfr[k]; if (b < 0) b = 0 }
            tot += n; hit += b; nc++
            if (b * 10 < n * 8) nbad++
        }
        if (tot == 0) return "- 0 0 0 - " (_cnrec + 0)
        gsub(/[ \t]/, "_", sig)
        return int(hit * 100 / tot) " " nc " " nbad " " tot " " (sig == "" ? "-" : sig) " " (_cnrec + 0)
    }
'
_FR_COV_AWK='
    # tokens: split at blanks and the structural punctuation = : , ; | quotes
    # brackets and _, edge punctuation stripped, case-folded; bytes outside
    # printable ASCII split too (box glyphs, tree art)
    function toks(s,   n, i, m, t) {
        s = tolower(s); gsub(/[^ -~]/, " ", s)
        n = split(s, _raw, /[] \t=:,;|"`()[{}<>_]+/); m = 0
        for (i = 1; i <= n; i++) {
            t = _raw[i]
            gsub(/\047/, "", t)
            if (t == "") continue
            if (t ~ /^[^a-z0-9]/ || t ~ /[^a-z0-9]$/) {
                gsub(/^[^a-z0-9]+/, "", t); gsub(/[^a-z0-9]+$/, "", t)
                if (t == "") continue
            }
            _tok[++m] = t
        }
        return m
    }
    # input token present: whole, or (a dashed compound) every dash part
    function has(t,   k, j) {
        if (t in seen) return 1
        if (index(t, "-") == 0) return 0
        k = split(t, _c, "-")
        for (j = 1; j <= k; j++) if (_c[j] != "" && !(_c[j] in seen)) return 0
        return 1
    }
    function addparts(t, re,   k, j) {
        k = split(t, _d, re)
        for (j = 1; j <= k; j++) if (_d[j] != "") seen[_d[j]] = 1
    }
    NR == FNR {
        cons_line($0)
        n = toks($0)
        for (i = 1; i <= n; i++) {
            t = _tok[i]; seen[t] = 1
            if (t ~ /[-.\/]/) {
                addparts(t, "."); addparts(t, "/"); addparts(t, "-")
                addparts(t, "[-./]")
            }
        }
        next
    }
    {
        # A line the tool itself marks as a comment (`#`, `;`) is chrome, not
        # data a parse owes anything to (the `;;` metadata block of dig).
        cons_input($0)
        if ($0 ~ /^[ \t]*[#;]/) next
        n = toks($0)
        if (n == 0) next
        sig = 0; hit = 0; asig = 0; ahit = 0
        for (i = 1; i <= n; i++) {
            t = _tok[i]; h = has(t)
            asig++; ahit += h
            if (t ~ /[a-z]/ || length(t) >= 3) { sig++; hit += h }
        }
        if (sig == 0) { sig = asig; hit = ahit }
        nl++
        if (hit * 2 > sig) cov++
    }
    END { if (nl == 0) print 100, 0, 0, cons_result(); else printf "%d %d %d %s\n", (cov * 100) / nl, nl, cov + 0, cons_result() }
'
_parse_coverage () {
    local _res="$1" _resf="${2:-}" _pc_out
    _COV=""; _COV_LINES=0; _COV_HIT=0; _CONS=""; _CONS_COLS=0; _CONS_BAD=0; _CONS_CELLS=0; _CONS_SIG="-"; _CONS_RECS=0
    [[ "$_FR_COV_BYTES" -ge 0 ]] || return 0
    (( ${#text} <= _FR_COV_BYTES )) || return 0
    if [[ -n "$_resf" ]]; then
        _pc_out=$(LC_ALL=C awk "$_FR_CONS_AWK$_FR_COV_AWK" "$_resf" <(printf '%s\n' "$text"))
    else
        [[ -n "$_res" ]] || return 0
        _pc_out=$(LC_ALL=C awk "$_FR_CONS_AWK$_FR_COV_AWK" <(printf '%s\n' "$_res") <(printf '%s\n' "$text"))
    fi
    [[ "$_pc_out" =~ ^([0-9]+)\ ([0-9]+)\ ([0-9]+)\ ([0-9]+|-)\ ([0-9]+)\ ([0-9]+)\ ([0-9]+)\ ([^ ]+)\ ([0-9]+)$ ]] || return 0
    _COV="${BASH_REMATCH[1]}"; _COV_LINES="${BASH_REMATCH[2]}"; _COV_HIT="${BASH_REMATCH[3]}"
    _CONS="${BASH_REMATCH[4]}"; _CONS_COLS="${BASH_REMATCH[5]}"; _CONS_BAD="${BASH_REMATCH[6]}"
    _CONS_CELLS="${BASH_REMATCH[7]}"; _CONS_SIG="${BASH_REMATCH[8]}"; _CONS_RECS="${BASH_REMATCH[9]}"
    [[ "$_CONS" == - ]] && _CONS=""
    return 0
}

# COVERAGE HOLD + RESCUE. When only the single best candidate is wanted
# (ranked extraction with --max-strategies 1 / --first-match — how provost
# calls the engine), the first candidate to produce output is not stored at
# once when its line coverage is below _FR_COV_MIN: it is HELD, and the
# RESCUE parsers (_FR_COV_RESCUERS — strategies written to keep every line of
# a multi-section report, which never compete in the ordinary ranking) are
# run on the input. One that covers MATERIALLY more — at least _FR_COV_GAIN
# points above the held claim — wins instead; if none does, the held claim is
# stored exactly as it would have been. So a confident one-section claim
# yields to a parse that keeps the whole report, and an input nothing covers
# better keeps its old winner byte for byte.
#
# Why rescue parsers and not simply the next ranked candidate: every ranked
# generic parser "covers" more than a section-dropping claim by scattering
# tokens over generic columns (aligned-columns, colons, vertical-line all
# reach ~100% on a report they cannot read), and a corpus trial showed such
# swaps make inputs worse, not better. Coverage says THAT lines were dropped,
# not which parse is right; a rescue parser is one whose output is right for
# the shape that drops lines — a lossless key/value table.
#
# Never holds a hint-routed or pinned strategy, a structured grammar
# (json/yaml/xml/toml — authoritative, they fold brace lines and nested
# paths), a catch-all (_FR_COV_CATCHALL: text-lines / line-records keep
# every line already), or a parse of fewer than _FR_COV_MIN_LINES counted
# lines (too small to call). Pruning is unaffected: the held claim is the
# first candidate in rank order to produce output, which no confidence
# ceiling ever prunes, and the rescue does not depend on the other
# candidates — so the outcome is the unpruned ranking's (_EAS_NOPRUNE=1).
_FR_COV_MIN="${_FR_COV_MIN:-60}"
_FR_COV_GAIN="${_FR_COV_GAIN:-25}"
_FR_COV_MIN_LINES="${_FR_COV_MIN_LINES:-6}"
_FR_COV_CATCHALL="${_FR_COV_CATCHALL:- text-lines line-records }"
[[ "$_FR_COV_MIN" =~ ^[0-9]+$ ]] || _FR_COV_MIN=60
[[ "$_FR_COV_GAIN" =~ ^[0-9]+$ ]] || _FR_COV_GAIN=25
[[ "$_FR_COV_MIN_LINES" =~ ^[0-9]+$ ]] || _FR_COV_MIN_LINES=6
_FR_COV_RESCUERS="${_FR_COV_RESCUERS:-kv-report}"
_COV_HOLD_ON=0
_COV_HELD=0

# _cov_hold_wanted STRATEGY [RESULT [RESULT_FILE]] — should this
# (stored-to-be) claim be held?
_cov_hold_wanted () {
    [[ "${_COV_HOLD_ON:-0}" -eq 1 ]] || return 1
    [[ "${_TG_EXEMPT:-0}" -eq 1 ]] && return 1
    [[ -n "$_OPT_strategy" || -n "$_OPT_replay" ]] && return 1
    [[ -n "$_COV" ]] || return 1
    case "$1" in json|yaml|xml|toml) return 1 ;; esac
    [[ "$_FR_COV_CATCHALL" == *" $1 "* ]] && return 1
    [[ "$_COV_LINES" -ge "$_FR_COV_MIN_LINES" ]] || return 1
    [[ "$_COV" -lt "$_FR_COV_MIN" ]] || return 1
    # A BESPOKE strategy (outside delimited/ + structured/, plugins included)
    # is tool-specific knowledge whose output shape is a deliberate summary
    # (systemctl status' unit fields without its journal tail, the InnoDB
    # monitor's counters without their section prose): its coverage is
    # reported, never second-guessed — a bespoke parse that loses data is
    # fixed in the strategy (gnu-version keeps its whole report).
    if find_strategy_file "$1" && ! _is_generic_strategy_file "$_FOUND_STRATEGY_FILE"; then
        _log_debug "Strategy '$1': line coverage ${_COV}% — bespoke, not held"
        return 1
    fi
    # A TABLE keeps its rows: the lines it dropped are a banner, a summary or
    # a second table — another dataset (--multi), not rows a key/value parse
    # could add without flattening the table into text.
    if [[ $# -ge 2 ]] && _cov_is_table "$2" "${3:-}"; then
        _log_debug "Strategy '$1': line coverage ${_COV}% but its parse is a table — not held"
        return 1
    fi
    return 0
}

# _cov_is_table RESULT [RESULT_FILE] — is the parse a TABLE (a record
# stream): at least 3 records (`<label><N>.<field>`) of 2+ fields, one field
# shared by at least 3 of them and by 60% or more — not a generic key/value
# pair list (only key, value, section, group, name … fields), and not a set of
# unrelated blocks (blank-separated sections share no field)?
_FR_COV_TABLE_AWK='
    match($0, /^[A-Za-z]+[0-9]+\./) {
        r = substr($0, 1, RLENGTH - 1); f = substr($0, RLENGTH + 1); sub(/ .*/, "", f)
        if (!((r, f) in seen)) {
            seen[r, f] = 1; nf[r]++; fl[r] = fl[r] SUBSEP f
            if (f !~ /^(key|value|section|group|name|field|label|block|title|text)$/) gen[r] = 1
        }
    }
    END {
        for (r in nf) {
            if (nf[r] < 2 || !(r in gen)) continue
            nrec++; k = split(substr(fl[r], 2), a, SUBSEP)
            for (j = 1; j <= k; j++) cnt[a[j]]++
        }
        best = 0; for (f in cnt) if (cnt[f] > best) best = cnt[f]
        print ((nrec >= 3 && best >= 3 && best * 10 >= nrec * 6) ? "table" : "no")
    }
'
_cov_is_table () {
    local _ct
    if [[ -n "${2:-}" ]]; then
        _ct=$(LC_ALL=C awk "$_FR_COV_TABLE_AWK" "$2")
    else
        _ct=$(printf '%s\n' "$1" | LC_ALL=C awk "$_FR_COV_TABLE_AWK")
    fi
    [[ "$_ct" == table ]]
}

# _cov_replaces STRATEGY — does the rescue parse just extracted beat the held
# claim? It must cover at least _FR_COV_GAIN points more, and its confidence
# must reach min(held confidence, _FR_COV_FLOOR): a rescue parser is held to
# the format-specific tier (kv-report reports 70), never below the claim it
# replaces when that claim is itself weaker.
_FR_COV_FLOOR="${_FR_COV_FLOOR:-70}"
[[ "$_FR_COV_FLOOR" =~ ^[0-9]+$ ]] || _FR_COV_FLOOR=70
_cov_replaces () {
    [[ -n "$_COV" ]] || return 1
    [[ "$_FR_COV_CATCHALL" == *" $1 "* ]] && return 1
    local _floor="$_FR_COV_FLOOR"
    (( _COV_HELD_CONF < _floor )) && _floor="$_COV_HELD_CONF"
    (( ${_STRATEGY_CONFIDENCE:-0} >= _floor )) || return 1
    [[ "$_COV" -ge $((_COV_HELD_PCT + _FR_COV_GAIN)) ]]
}

# _cov_hold RESULT RESULT_FILE STRATEGY REPORT VERSION [KIND] — set the claim
# aside (KIND cov: held for line coverage, the rescue decides; cons: held for
# column-type consistency, the next ranked candidates decide).
_cov_hold () {
    _COV_HELD=1; _COV_HELD_KIND="${6:-cov}"; _COV_HELD_BAD="$_CONS_BAD"
    _COV_HELD_CCOLS="$_CONS_COLS"; _COV_HELD_CELLS="$_CONS_CELLS"; _COV_HELD_SIG="$_CONS_SIG"
    _COV_HELD_RECS="$_CONS_RECS"
    _COV_HELD_STRAT="$3"; _COV_HELD_REPORT="$4"; _COV_HELD_VER="$5"
    _COV_HELD_CONF="${_STRATEGY_CONFIDENCE:-0}"; _COV_HELD_COUNT="$_LINE_COUNT"
    _COV_HELD_PCT="$_COV"; _COV_HELD_CONS="$_CONS"
    _COV_HELD_RES=""; _COV_HELD_FILE=""
    if [[ -n "$2" ]]; then
        _COV_HELD_FILE="$_XL_DIR/lane.held"
        mv -f "$2" "$_COV_HELD_FILE"
    else
        _COV_HELD_RES="$1"
    fi
}

_cov_drop_held () {
    _COV_HELD=0; _COV_HELD_RES=""; _COV_HELD_KIND=""
    [[ -n "${_COV_HELD_FILE:-}" ]] && rm -f "$_COV_HELD_FILE"
    _COV_HELD_FILE=""
}

# _cov_rescue — run each rescue parser (detect with _FR_RESCUE=1, then
# extract; _extract_and_store stores it only when _cov_replaces says it beats
# the held claim). Filters (--generic, --exclude, min confidence) apply as to
# any strategy.
_cov_rescue () {
    local _rs _rs_rc
    for _rs in $_FR_COV_RESCUERS; do
        [[ "${_COV_HELD:-0}" -eq 1 ]] || return 0
        _should_run_strategy "$_rs" || continue
        find_strategy_file "$_rs" || continue
        [[ "${_OPT_generic:-0}" -eq 1 ]] && ! _is_generic_strategy_file "$_FOUND_STRATEGY_FILE" && continue
        read_strategy_metadata "$_FOUND_STRATEGY_FILE"
        [[ -n "$_META_DEPRECATED" ]] && continue
        _source_strategy_cached "$_FOUND_STRATEGY_FILE" /dev/null || continue
        _FR_RESCUE=1
        if _detect_strategy "$_rs" "${_META_PRIORITY:-99}"; then
            _rs_rc=0
            _extract_and_store "$_rs" "${_META_VERSION:-0}" || _rs_rc=$?
        fi
        _FR_RESCUE=0
        unset -f strategy_detect strategy_extract 2>/dev/null
        unset _arr 2>/dev/null
    done
}

# _cov_restore_held — no rescue parse covered materially more: store the
# held claim exactly as it would have been stored when it was extracted.
_cov_restore_held () {
    [[ "${_COV_HELD:-0}" -eq 1 ]] || return 0
    if [[ "$_COV_HELD_KIND" == cons ]]; then
        _log_debug "No candidate types its columns materially better than '${_COV_HELD_STRAT}' (${_COV_HELD_CONS}%): keeping it"
    else
        _log_debug "No rescue parse covers materially more than '${_COV_HELD_STRAT}' (${_COV_HELD_PCT}%): keeping it"
    fi
    _store_winner "$_COV_HELD_RES" "$_COV_HELD_FILE" "$_COV_HELD_STRAT" "$_COV_HELD_REPORT" \
        "$_COV_HELD_VER" "$_COV_HELD_COUNT" "$_COV_HELD_CONF" "$_COV_HELD_PCT" "$_COV_HELD_CONS" || true
    _cov_drop_held
}

# CONSISTENCY YIELD. Coverage catches a parse that DROPS lines; a parse that
# keeps every line but puts values under the wrong headers (a date split over
# three columns, a multi-word name spread over Name / Id / Version, a key:
# value file read as a two-column table) covers ~100%. Column-type
# consistency (_FR_CONS_AWK) sees it: such a parse has columns that hold
# numbers in some rows and words in others. With one winner wanted, the
# first candidate to produce output is HELD when it is a generic parse with
# an inconsistent column and consistency under _FR_CONS_MIN (95); the next
# ranked candidates down to _FR_CONS_WINDOW (20) confidence points below it
# are extracted in rank order, and the first that is
#   - a generic parser (delimited/ + structured/), not a catch-all,
#   - at least _FR_CONS_GAIN (5) points more consistent and itself at
#     _FR_CONS_MIN or more, with fewer inconsistent columns,
#   - keeps at least as many lines (coverage not lower),
#   - is judged on comparable evidence (half the columns, a third of the
#     cells), adds no records, and
#   - does not relabel (a column name both parses use has the same type
#     family in both — _cons_same_labels)
# replaces it; otherwise the held claim is stored byte for byte. A claim held
# for coverage that no rescue replaces is checked the same way.
#
# Why a held claim and not a score: consistency alone favours parses that
# scatter prose over generic columns (every column holds words — perfectly
# "consistent"), the trap the coverage work hit. So it never ranks; it only
# decides between a claim that is visibly inconsistent and a nearby
# candidate that keeps the same lines AND types its columns better. Never
# held: a hint-routed or pinned strategy, a bespoke strategy (tool knowledge;
# lsof's NODE column legitimately holds `TCP` among inode numbers), a
# structured grammar (json / yaml / xml / toml), a catch-all, a parse that
# is not measured (over _FR_COV_BYTES) or has no column with 3+ filled cells.
#
# Exactness: the alternatives are candidates a pruned pass may have skipped,
# so a claim held after pruning has the pruned detectors that could be an
# alternative (generic, not a catch-all, ceiling inside the window) run then,
# and the candidates below it are tried in the unpruned ranking's order (all
# pruned candidates rank below the claim) — the outcome is always the
# unpruned ranking's, without a full redo.
_FR_CONS_MIN="${_FR_CONS_MIN:-95}"
_FR_CONS_GAIN="${_FR_CONS_GAIN:-5}"
_FR_CONS_WINDOW="${_FR_CONS_WINDOW:-20}"
[[ "$_FR_CONS_MIN" =~ ^[0-9]+$ ]] || _FR_CONS_MIN=95
[[ "$_FR_CONS_GAIN" =~ ^[0-9]+$ ]] || _FR_CONS_GAIN=5
[[ "$_FR_CONS_WINDOW" =~ ^[0-9]+$ ]] || _FR_CONS_WINDOW=20
# The hold re-runs detection unpruned and extracts its alternatives: seconds
# on a 100 KB table. It applies up to _FR_CONS_HOLD_BYTES (32 KB, the size
# the detection sample starts at); the measure is reported up to
# _FR_COV_BYTES either way.
_FR_CONS_HOLD_BYTES="${_FR_CONS_HOLD_BYTES:-32768}"
[[ "$_FR_CONS_HOLD_BYTES" =~ ^[0-9]+$ ]] || _FR_CONS_HOLD_BYTES=32768

# _cons_eligible STRATEGY — a generic, non-catch-all strategy (a claim that
# may be held, or an alternative that may replace it)?
_cons_eligible () {
    case "$1" in json|yaml|xml|toml) return 1 ;; esac
    [[ "$_FR_COV_CATCHALL" == *" $1 "* ]] && return 1
    find_strategy_file "$1" && _is_generic_strategy_file "$_FOUND_STRATEGY_FILE"
}

# _cons_hold_wanted STRATEGY — should this (stored-to-be) claim be held for
# its column-type consistency?
_cons_hold_wanted () {
    [[ "${_COV_HOLD_ON:-0}" -eq 1 ]] || return 1
    [[ "${_TG_EXEMPT:-0}" -eq 1 ]] && return 1
    [[ -n "$_OPT_strategy" || -n "$_OPT_replay" ]] && return 1
    [[ -n "$_CONS" && "$_CONS_BAD" -ge 1 ]] || return 1
    [[ "$_CONS" -lt "$_FR_CONS_MIN" ]] || return 1
    (( ${#text} <= _FR_CONS_HOLD_BYTES )) || return 1
    _cons_eligible "$1"
}

# _cons_replaces STRATEGY — does the candidate just extracted beat the claim
# held for consistency?
_cons_replaces () {
    [[ -n "$_CONS" && -n "$_COV" ]] || return 1
    _cons_eligible "$1" || return 1
    [[ "$_CONS" -ge $((_COV_HELD_CONS + _FR_CONS_GAIN)) && "$_CONS" -ge "$_FR_CONS_MIN" ]] || return 1
    [[ "$_CONS_BAD" -lt "$_COV_HELD_BAD" ]] || return 1
    [[ -z "$_COV_HELD_PCT" || "$_COV" -ge "$_COV_HELD_PCT" ]] || return 1
    # judged on comparable evidence: at least half the claim's typed
    # columns and a third of its typed cells (a parse that glues a table
    # into two text columns is "consistent" by having nothing left to type)
    (( _CONS_COLS * 2 >= _COV_HELD_CCOLS && _CONS_CELLS * 3 >= _COV_HELD_CELLS )) || return 1
    # it never adds RECORDS: re-reading the same rows (or gathering
    # key/value pairs into records) is a fix; splitting them further — a
    # rule line, a banner or a multi-line cell turned into rows — is the
    # scatter a consistent-looking parse is made of
    (( _CONS_RECS <= _COV_HELD_RECS )) || return 1
    # and it must not RELABEL: a column both parses name (from the same
    # header) holds the same type family in both — when they disagree on
    # what sits under `Stratum`, one of them has shifted the header against
    # the cells, and nothing says it is the claim
    _cons_same_labels "$_COV_HELD_SIG" "$_CONS_SIG"
}

# _cons_same_labels SIG_A SIG_B — no column name typed differently in the two
# `name=family,…` signatures (see _FR_CONS_AWK).
_cons_same_labels () {
    [[ "$1" == - || "$2" == - ]] && return 0
    local -A _sl=()
    local -a _sa=() _sb=()
    local _e
    IFS=, read -ra _sa <<< "$1"
    IFS=, read -ra _sb <<< "$2"
    for _e in "${_sa[@]}"; do [[ -n "${_e%=*}" ]] && _sl["${_e%=*}"]="${_e##*=}"; done
    for _e in "${_sb[@]}"; do
        [[ -n "${_e%=*}" && -n "${_sl["${_e%=*}"]+x}" && "${_sl["${_e%=*}"]}" != "${_e##*=}" ]] && return 1
    done
    return 0
}

# _store_winner RESULT RESULT_FILE STRATEGY REPORT VERSION FIELDS CONF COV CONS —
# store one claim and record it (matched list, field total, the --emit-meta
# winner). Returns 1 when the strategy cap is reached.
_store_winner () {
    local _sw_res="$1" _sw_file="$2" _sw_strat="$3" _sw_report="$4" _sw_ver="$5"
    local _sw_n="$6" _sw_conf="$7" _sw_cov="$8" _sw_cons="${9:-}"
    if [[ -n "$_sw_file" ]]; then
        _store_file "$_sw_file" "STRAT-${_sw_report}"
    else
        store "$_sw_res" "STRAT-${_sw_report}"
    fi
    strategies_matched=$((strategies_matched + 1))
    # ENV-200: record the first strategy that produced output (the dispatch
    # winner) + its confidence and line coverage, for the opt-in --emit-meta
    # line.
    if [[ -z "${_WINNER_NAME:-}" ]]; then
        _WINNER_NAME="$_sw_report"
        _WINNER_CONF="$_sw_conf"
        _WINNER_COV="$_sw_cov"
        _WINNER_CONS="$_sw_cons"
    fi
    [[ -n "$matched_strategies" ]] && matched_strategies+=","
    matched_strategies+="${_sw_report}@${_sw_ver:-0}"
    total_fields=$((total_fields + _sw_n))
    _log_debug "Strategy '$_sw_strat': extracted $_sw_n fields"
    if [[ $_OPT_first_match -eq 1 ]]; then
        _log_debug "--first-match: stopping after '$_sw_strat'"
        return 1
    fi
    if [[ $_OPT_max_strategies -gt 0 && $strategies_matched -ge $_OPT_max_strategies ]]; then
        _log_debug "--max-strategies $_OPT_max_strategies reached"
        return 1
    fi
    return 0
}

# Run strategy extraction and store results.
# Returns: 0 to continue loop, 2 to break (early exit), 3 = claim HELD for low
# coverage (see COVERAGE HOLD; the caller runs the rescue), 4 = claim HELD for
# low column-type consistency (see CONSISTENCY YIELD; the caller tries the
# next candidates)
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
        _parse_coverage "$result" "$_xl_res"
        _log_debug "Strategy '$strategy_name': line coverage ${_COV:-n/a}${_COV:+% ($_COV_HIT of $_COV_LINES lines)}, type consistency ${_CONS:-n/a}${_CONS:+% ($_CONS_BAD of $_CONS_COLS judged columns inconsistent)}"
        # COVERAGE HOLD (see _cov_hold_wanted): a low-coverage claim is set
        # aside instead of stored, and the rescue parser gets its turn; a
        # rescue parse is stored only when it covers materially more.
        if [[ "${_COV_HELD:-0}" -eq 1 && "$_COV_HELD_KIND" == cons ]]; then
            if ! _cons_replaces "$strategy_name"; then
                _log_debug "Strategy '$strategy_name': does not type its columns materially better than held '${_COV_HELD_STRAT}' (${_CONS:-n/a}% vs ${_COV_HELD_CONS}%)"
                [[ -n "$near_miss_strategies" ]] && near_miss_strategies+=", "
                near_miss_strategies+="${strategy_name}(t${_CONS:-?}%)"
                return 0
            fi
            _log_debug "Strategy '$strategy_name': type consistency ${_CONS}% — replaces held '${_COV_HELD_STRAT}' (${_COV_HELD_CONS}%)"
            [[ -n "$near_miss_strategies" ]] && near_miss_strategies+=", "
            near_miss_strategies+="${_COV_HELD_STRAT}(consistency ${_COV_HELD_CONS}%)"
            _cov_drop_held
        elif [[ "${_COV_HELD:-0}" -eq 1 ]]; then
            if ! _cov_replaces "$strategy_name"; then
                _log_debug "Strategy '$strategy_name': does not cover materially more than held '${_COV_HELD_STRAT}' (${_COV:-n/a}% vs ${_COV_HELD_PCT}%)"
                [[ -n "$near_miss_strategies" ]] && near_miss_strategies+=", "
                near_miss_strategies+="${strategy_name}(c${_COV:-?}%)"
                return 0
            fi
            _log_debug "Strategy '$strategy_name': covers ${_COV}% — replaces held '${_COV_HELD_STRAT}' (${_COV_HELD_PCT}%)"
            [[ -n "$near_miss_strategies" ]] && near_miss_strategies+=", "
            near_miss_strategies+="${_COV_HELD_STRAT}(coverage ${_COV_HELD_PCT}%)"
            _cov_drop_held
        elif _cov_hold_wanted "$strategy_name" "$result" "$_xl_res"; then
            _cov_hold "$result" "$_xl_res" "$strategy_name" "$report_name" "$strategy_version"
            _log_debug "Strategy '$strategy_name': held — line coverage ${_COV}% < ${_FR_COV_MIN}%; trying the rescue parser(s)"
            return 3
        elif _cons_hold_wanted "$strategy_name"; then
            _cov_hold "$result" "$_xl_res" "$strategy_name" "$report_name" "$strategy_version" cons
            _log_debug "Strategy '$strategy_name': held — type consistency ${_CONS}% < ${_FR_CONS_MIN}% (${_CONS_BAD} of ${_CONS_COLS} columns inconsistent); trying the next candidates"
            return 4
        fi
        _store_winner "$result" "$_xl_res" "$strategy_name" "$report_name" "$strategy_version" \
            "$_LINE_COUNT" "${_STRATEGY_CONFIDENCE:-0}" "$_COV" "$_CONS" || return 2
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

# _eas_try_cands LIST — phase 2 of the ranked pass: try the sorted candidate
# lines (key|priority|name|version|file) best first (see RANKING in
# _run_auto_strategies_body, whose locals it shares). Sets _eas_redo (redo
# unpruned), _eas_more (held for consistency after pruning: the caller
# re-detects the pruned alternatives) and _eas_ln (lines consumed).
_eas_try_cands () {
    local _ck _pk
    _eas_ln=0
    while IFS='|' read -r _ck _pk strategy_name strategy_version strategy_file; do
        _eas_ln=$((_eas_ln + 1))
        [[ -z "$strategy_file" ]] && continue
        strategy_priority="$((10#$_pk))"
        if [[ "${_COV_HELD:-0}" -eq 1 && "$_COV_HELD_KIND" == cons ]]; then
            # held for consistency: only the window below it, and only
            # candidates that may replace it, are extracted
            (( 100 - 10#$_ck >= _COV_HELD_CONF - _FR_CONS_WINDOW )) || break
            _cons_eligible "$strategy_name" || continue
        fi
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
        # HELD for low coverage: the rescue decides (pruning cannot matter —
        # the held claim is the first candidate in rank order to produce
        # output, which no ceiling ever prunes, and the rescue parsers are
        # not ranked candidates).
        if [[ $_eas_rc -eq 3 ]]; then
            # The rescue parsers get their turn now; a claim no rescue
            # replaces may still be held for its consistency (below).
            _cov_rescue
            [[ "${_COV_HELD:-0}" -eq 1 ]] || break
            _CONS="$_COV_HELD_CONS"; _CONS_BAD="$_COV_HELD_BAD"
            _cons_hold_wanted "$_COV_HELD_STRAT" || break
            _COV_HELD_KIND=cons; _eas_rc=4
            _log_debug "Strategy '$_COV_HELD_STRAT': still held — type consistency ${_COV_HELD_CONS}% < ${_FR_CONS_MIN}%; trying the next candidates"
        fi
        # HELD for consistency: the alternatives are the candidates below it
        # — some of which a pruned pass skipped (the caller detects those).
        if [[ $_eas_rc -eq 4 && $_eas_pruned -gt 0 ]]; then _eas_more=1; break; fi
        [[ $_eas_rc -eq 4 ]] && continue
        [[ "${_COV_HELD:-0}" -eq 1 && "$_COV_HELD_KIND" == cons ]] && continue
        # The top candidate yielded nothing. With detectors pruned, one of
        # them might outrank whatever comes next: redo the pass unpruned.
        if [[ $_eas_pruned -gt 0 ]]; then _eas_redo=1; break; fi
    done <<< "$1"
    return 0
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
    # Coverage hold state is per pass (a redo starts clean).
    _cov_drop_held; _COV_HOLD_ON=0; _WINNER_COV=""; _WINNER_CONS=""
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
    if provost_progress_active; then
        if [[ "${PROVOST_PROGRESS_OPT_IN:-0}" == "1" || "$_eas_total" -ge 20 ]]; then
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
    _src_tmpf=$(mktemp "${TMPDIR:-/tmp}/provost_src_err.XXXXXX") || _src_tmpf=""
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
    local _eas_prune=0 _eas_pruned=0 _eas_best=-1 _eas_pruned_list=""
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
            provost_progress_tick "$strategies_tried" "$_eas_total" "$strategy_name"
        fi

        _should_run_strategy "$strategy_name" || continue

        if [[ $_eas_prune -eq 1 && $_eas_best -ge 0 ]]; then
            _strategy_ceiling "$strategy_file"
            if (( _CEIL <= _eas_best )); then
                _eas_pruned=$((_eas_pruned + 1))
                _eas_pruned_list+="${_priority}|${strategy_version}|${strategy_file}"$'\n'
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
        # COVERAGE HOLD applies when one winner is wanted (see above).
        if [[ $_OPT_first_match -eq 1 || $_OPT_max_strategies -eq 1 ]]; then
            _COV_HOLD_ON=1
        fi
        local _eas_ln=0 _eas_more=0
        _eas_try_cands "$_eas_cands"
        if [[ $_eas_more -eq 1 ]]; then
            # Held for consistency after pruning: the pruned detectors that
            # could be an alternative (generic, not a catch-all, a ceiling
            # inside the window) are detected now, and every candidate below
            # the claim is tried in the unpruned ranking's order.
            local _eas_rest _eas_extra=""
            _eas_rest="$(printf '%s\n' "$_eas_cands" | tail -n +$((_eas_ln + 1)))"
            while IFS='|' read -r _priority strategy_version strategy_file; do
                [[ -z "$strategy_file" ]] && continue
                strategy_name="${strategy_file##*/}"; strategy_name="${strategy_name%.sh}"
                _is_generic_strategy_file "$strategy_file" || continue
                case "$strategy_name" in json|yaml|xml|toml) continue ;; esac
                [[ "$_FR_COV_CATCHALL" == *" $strategy_name "* ]] && continue
                _strategy_ceiling "$strategy_file"
                (( _CEIL >= _COV_HELD_CONF - _FR_CONS_WINDOW )) || continue
                read_strategy_metadata "$strategy_file"
                [[ -n "$_META_DEPRECATED" ]] && continue
                _source_strategy_cached "$strategy_file" /dev/null || continue
                strategy_priority="${_priority#0}"; strategy_priority="${strategy_priority:-99}"
                if _detect_strategy "$strategy_name" "$strategy_priority"; then
                    _ck="000$((100 - _STRATEGY_CONFIDENCE))"; _pk="000${_priority}"
                    _eas_extra+="${_ck: -3}|${_pk: -3}|${strategy_name}|${strategy_version}|${strategy_file}"$'\n'
                fi
                unset -f strategy_detect strategy_extract 2>/dev/null
                unset _arr 2>/dev/null
            done <<< "$_eas_pruned_list"
            [[ $_OPT_debug -eq 1 ]] && _log_debug "Held for consistency after pruning: pruned alternatives that fire: ${_eas_extra//$'\n'/ }"
            _eas_more=0
            [[ -n "$_eas_rest" ]] && _eas_rest+=$'\n'
            _eas_try_cands "$(printf '%s%s' "$_eas_rest" "$_eas_extra" | LC_ALL=C sort -t'|' -k1,1 -k2,2 -k3,3)"
        fi
        _COV_HOLD_ON=0
        if [[ $_eas_redo -eq 1 ]]; then
            _cov_drop_held
            [[ -n "$_src_tmpf" ]] && rm -f "$_src_tmpf"
            _log_debug "Top candidate failed after pruning $_eas_pruned detector(s): redoing unpruned"
            local _eas_rrc=0
            _EAS_NOPRUNE=1 _run_auto_strategies_body || _eas_rrc=$?
            return $_eas_rrc
        fi
        # A claim still held (no rescue / no consistent alternative replaced
        # it) is stored exactly as it was extracted.
        _cov_restore_held
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
    # the first-ranked candidate that extracts something (for the hold note)
    local _ex_top_conf="" _ex_top_cov="" _ex_top_name="" _ex_top_lines=0 _ex_top_res=""
    local _ex_recs=""   # conf|pri|name|cov|cons|bad|cols|cells per candidate that extracts

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
            miss_lines="${miss_lines}$(printf '%-7s  %-30s  %4s  %4s  %5s  %5s  %s' 'DEPR' "$strategy_name" "$strategy_priority" '--' '-' '-' "deprecated: $_META_DEPRECATED")"$'\n'
            skipped=$((skipped + 1))
            continue
        fi

        # ENV-160: mktemp + umask 077 instead of the predictable
        # `${TMPDIR:-/tmp}/provost_explain.$$` (symlink-attack vector).
        local _old_umask _src_tmpf
        _old_umask=$(umask); umask 077
        _src_tmpf=$(mktemp "${TMPDIR:-/tmp}/provost_explain.XXXXXX") || { umask "$_old_umask"; continue; }
        umask "$_old_umask"
        if ! source "$strategy_file" 2>"$_src_tmpf"; then
            miss_lines="${miss_lines}$(printf '%-7s  %-30s  %4s  %4s  %5s  %5s  %s' 'ERR' "$strategy_name" "$strategy_priority" '--' '-' '-' 'source error')"$'\n'
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
            # LINE COVERAGE of this candidate's extract (see _parse_coverage):
            # explain is a dry run, but a matching candidate's extract is the
            # only way to show how much of the input it would keep.
            local _ex_res _ex_cov="-" _ex_cons="-" _ex_conf="$_STRATEGY_CONFIDENCE"
            _ex_res="$(strategy_extract "$text" "${_STATE_filename:-}" "${_STATE_encoding_hint:-}" 2>/dev/null)" || true
            if [[ -z "${_ex_res//[[:space:]]/}" ]]; then
                _ex_cov="empty"
            else
                _parse_coverage "$_ex_res"
                [[ -n "$_COV" ]] && _ex_cov="${_COV}%"
                [[ -n "$_CONS" ]] && _ex_cons="${_CONS}%"
                _ex_recs+="${_STRATEGY_CONFIDENCE}|${strategy_priority}|${strategy_name}|${_COV}|${_CONS}|${_CONS_BAD}|${_CONS_COLS}|${_CONS_CELLS}|${_CONS_SIG}|${_CONS_RECS}"$'\n'
                [[ -z "$_ex_top_cov" || "$_ex_conf" -gt "$_ex_top_conf" ]] && \
                    { _ex_top_conf="$_ex_conf"; _ex_top_cov="${_COV:--}"; _ex_top_name="$strategy_name"; _ex_top_lines="$_COV_LINES"; _ex_top_res="$_ex_res"; }
            fi
            # Sort key first (confidence, priority, name) — the order ranked
            # detection tries the candidates in; cut off before printing.
            match_lines="${match_lines}${_STRATEGY_CONFIDENCE}|${strategy_priority}|${strategy_name}|$(printf '%-7s  %-30s  %4s  %4s  %5s  %5s  %s' 'MATCH' "$strategy_name" "$strategy_priority" "$_ex_conf" "$_ex_cov" "$_ex_cons" "$reason")"$'\n'
            matched=$((matched + 1))
        else
            miss_lines="${miss_lines}$(printf '%-7s  %-30s  %4s  %4s  %5s  %5s  %s' 'MISS' "$strategy_name" "$strategy_priority" '0' '-' '-' 'not applicable')"$'\n'
        fi

        unset -f strategy_detect strategy_extract 2>/dev/null
        while IFS= read -r _ _ _post_fn; do
            case "$_post_fn" in _strat_*) unset -f "$_post_fn" 2>/dev/null ;; esac
        done < <(declare -F)
        unset _arr 2>/dev/null
    done <<< "$_SORTED_STRATEGIES"

    # Print header (COV = line coverage of the candidate's extract, CONS =
    # its column-type consistency)
    printf '%-7s  %-30s  %4s  %4s  %5s  %5s  %s\n' "STATUS" "STRATEGY" "PRI" "CONF" "COV" "CONS" "REASON"
    printf '%-7s  %-30s  %4s  %4s  %5s  %5s  %s\n' "------" "--------" "---" "----" "---" "----" "------"

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
    # COVERAGE HOLD preview: the top candidate (by confidence) to extract
    # something, when its coverage is low, is held and the rescue parsers run.
    if [[ "$_ex_top_cov" =~ ^[0-9]+$ ]]; then
        _COV="$_ex_top_cov"; _COV_LINES="$_ex_top_lines"; _COV_HOLD_ON=1; _TG_EXEMPT=0
        if _cov_hold_wanted "$_ex_top_name" && _cov_is_table "$_ex_top_res"; then
            echo "Coverage: '$_ex_top_name' keeps ${_ex_top_cov}% of the input lines (< ${_FR_COV_MIN}%), but its parse is a table: kept (the rest may be another dataset — --multi)."
        elif _cov_hold_wanted "$_ex_top_name"; then
            echo "Coverage: '$_ex_top_name' keeps ${_ex_top_cov}% of the input lines (< ${_FR_COV_MIN}%): held; rescue parsers:"
            local _rs _rs_cov
            for _rs in $_FR_COV_RESCUERS; do
                find_strategy_file "$_rs" || continue
                source "$_FOUND_STRATEGY_FILE" 2>/dev/null || continue
                _FR_RESCUE=1; _STRATEGY_CONFIDENCE=50; _rs_cov="does not apply"
                if strategy_detect "$text" "${_STATE_filename:-}" "${_STATE_encoding_hint:-}"; then
                    _parse_coverage "$(strategy_extract "$text" "${_STATE_filename:-}" "${_STATE_encoding_hint:-}" 2>/dev/null)"
                    if [[ -n "$_COV" && "$_COV" -ge $((_ex_top_cov + _FR_COV_GAIN)) ]]; then
                        _rs_cov="keeps ${_COV}% — REPLACES '$_ex_top_name'"
                    else
                        _rs_cov="keeps ${_COV:-?}% — not ${_FR_COV_GAIN} points more; '$_ex_top_name' stays"
                    fi
                fi
                _FR_RESCUE=0
                echo "  $_rs: $_rs_cov"
                unset -f strategy_detect strategy_extract 2>/dev/null
            done
        fi
        _COV_HOLD_ON=0
    fi
    # CONSISTENCY YIELD preview: the first candidate in rank order to extract
    # something, when it is held for its column-type consistency, and the
    # candidate that would replace it (see _cons_hold_wanted).
    if [[ -n "$_ex_recs" ]]; then
        local _xr _xc _xp _xn _xv _xs _xb _xl _xe _xg _xq _held=""
        while IFS='|' read -r _xc _xp _xn _xv _xs _xb _xl _xe _xg _xq; do
            [[ -n "$_xn" ]] || continue
            _COV="$_xv"; _CONS="$_xs"; _CONS_BAD="$_xb"; _CONS_COLS="$_xl"; _CONS_CELLS="$_xe"; _CONS_SIG="$_xg"; _CONS_RECS="$_xq"
            if [[ -z "$_held" ]]; then
                _COV_HOLD_ON=1; _TG_EXEMPT=0
                _cons_hold_wanted "$_xn" || { _COV_HOLD_ON=0; break; }
                _COV_HOLD_ON=0
                _held="$_xn"; _COV_HELD_CONF="$_xc"; _COV_HELD_CONS="$_xs"; _COV_HELD_BAD="$_xb"
                _COV_HELD_PCT="$_xv"; _COV_HELD_CCOLS="$_xl"; _COV_HELD_CELLS="$_xe"; _COV_HELD_SIG="$_xg"; _COV_HELD_RECS="$_xq"
                echo "Consistency: '$_held' types ${_xs}% of its cells consistently (< ${_FR_CONS_MIN}%, ${_xb} of ${_xl} columns mixed): held; candidates within ${_FR_CONS_WINDOW} points:"
                continue
            fi
            (( _xc >= _COV_HELD_CONF - _FR_CONS_WINDOW )) || break
            _cons_eligible "$_xn" || continue
            if _cons_replaces "$_xn"; then
                echo "  $_xn: ${_xs:-?}% consistent, coverage ${_xv:-?}% — REPLACES '$_held'"
                _held=""; break
            fi
            if [[ -n "$_xs" ]] && (( _xq > _COV_HELD_RECS )); then
                echo "  $_xn: ${_xs:-?}% consistent, coverage ${_xv:-?}% — splits the rows further (${_xq} records, not ${_COV_HELD_RECS}): does not replace it"
            elif [[ -n "$_xs" ]] && ! _cons_same_labels "$_COV_HELD_SIG" "$_xg"; then
                echo "  $_xn: ${_xs:-?}% consistent, coverage ${_xv:-?}% — types a column of the same name differently (relabels it): does not replace it"
            else
                echo "  $_xn: ${_xs:-?}% consistent, coverage ${_xv:-?}% — does not replace it"
            fi
        done < <(printf '%s' "$_ex_recs" | LC_ALL=C sort -t'|' -k1,1nr -k2,2n -k3,3)
        [[ -n "$_held" ]] && echo "  (no candidate replaces it; '$_held' stays)"
    fi
}
