#!/bin/bash
################################################################################
## Strategy discovery and execution for envoy-extract
##
## Find, load, detect, and run extraction strategies.
## Dependencies: _log.sh, _helpers.sh (_clean_field, _count_lines),
##               _postprocess.sh (store)
################################################################################

# Read strategy metadata from file header (first 15 lines).
# Sets globals: _META_NAME, _META_DESCRIPTION, _META_VERSION, _META_PRIORITY,
#               _META_DEPRECATED
read_strategy_metadata () {
    local filepath="$1"
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
            list+="${_padded: -3}|${_META_VERSION}|${sf}"$'\n'
        done
    done

    # Sort by priority (numeric), then by filename
    echo "${list%$'\n'}" | sort -t'|' -k1,1n -k3,3
}

list_strategies () {
    local strategy_dirs=("$STRATEGIES_DIR")
    local user_dir="${HOME:-/nonexistent}/.mfe/strategies"
    [[ -d "$user_dir" ]] && strategy_dirs+=("$user_dir")
    [[ -n "${_OPT_plugin_dir:-}" && -d "${_OPT_plugin_dir:-}" ]] && strategy_dirs+=("$_OPT_plugin_dir")

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
    local strategy_dirs=("$STRATEGIES_DIR")
    local user_dir="${HOME:-/nonexistent}/.mfe/strategies"
    [[ -d "$user_dir" ]] && strategy_dirs+=("$user_dir")
    [[ -n "${_OPT_plugin_dir:-}" && -d "${_OPT_plugin_dir:-}" ]] && strategy_dirs+=("$_OPT_plugin_dir")

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
    for sdir in "$STRATEGIES_DIR" "${HOME:-/nonexistent}/.mfe/strategies" "${_OPT_plugin_dir:-}"; do
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

# Match the input against hints.tsv.
# Sets _HINT_TOOL and _HINT_STRATEGY on a match. Returns 0 on match, 1 otherwise.
_match_hint () {
    local text="$1"
    _HINT_TOOL="" _HINT_STRATEGY=""
    [[ "${_OPT_no_hints:-0}" -eq 1 ]] && return 1
    [[ -f "${HINTS_FILE:-}" ]] || return 1
    local _mh_first="" _mh_line
    while IFS= read -r _mh_line; do
        [[ -n "${_mh_line//[[:space:]]/}" ]] && { _mh_first="$_mh_line"; break; }
    done <<< "$text"
    local tool mtype pattern strategy _rest
    while IFS=$'\t' read -r tool mtype pattern strategy _rest; do
        [[ -z "$tool" || "$tool" == \#* ]] && continue
        [[ -z "$pattern" || -z "$strategy" ]] && continue
        case "$mtype" in
            prefix)   [[ "$_mh_first" == "$pattern"* ]] || continue ;;
            contains) [[ "$text" == *"$pattern"* ]] || continue ;;
            regex)    [[ "$text" =~ $pattern ]] || continue ;;
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
    read_strategy_metadata "$_FOUND_STRATEGY_FILE"
    if ! source "$_FOUND_STRATEGY_FILE" 2>/dev/null; then
        _log_warn "hint '$_HINT_TOOL': failed to source strategy '$_HINT_STRATEGY'"
        return 1
    fi
    _log_debug "hint '$_HINT_TOOL' matched: forcing strategy '$_HINT_STRATEGY'"
    _STRATEGY_CONFIDENCE=95
    _STRATEGY_REPORT_NAME="$_HINT_TOOL"
    local _had_output_before="$strategies_matched" _rhs_rc=0
    _extract_and_store "$_HINT_STRATEGY" "${_META_VERSION:-0}" || _rhs_rc=$?
    unset -f strategy_detect strategy_extract 2>/dev/null
    while IFS= read -r _ _ _post_fn; do
        case "$_post_fn" in _strat_*) unset -f "$_post_fn" 2>/dev/null ;; esac
    done < <(declare -F)
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
            _clean_field "$value"; value="$_CLEANED"
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
    local result _ext_rc=0
    result=$(strategy_extract "$text" "${_STATE_filename:-}" "${_STATE_encoding_hint:-}") || _ext_rc=$?
    if [[ $_ext_rc -ne 0 ]]; then
        _log_debug "Strategy '$strategy_name': strategy_extract exited with code $_ext_rc"
    fi
    if [[ $_OPT_profile -eq 1 ]]; then
        local _prof_elapsed=$(( SECONDS - _prof_start ))
        echo "[profile] Strategy '$strategy_name': ${_prof_elapsed}s" >&2
    fi
    if [[ -n "$result" ]]; then
        # A strategy may report a more specific name than its file name — the
        # data-driven `columnar-specs` engine reports the matched TOOL name so
        # each tool keeps its own dataset identity instead of collapsing to
        # `columnar-specs`. Falls back to the file's strategy name.
        local report_name="${_STRATEGY_REPORT_NAME:-$strategy_name}"
        store "$result" "STRAT-${report_name}"
        strategies_matched=$((strategies_matched + 1))
        # ENV-200: record the first strategy that produced output (the dispatch
        # winner) + its confidence, for the opt-in --emit-meta line.
        if [[ -z "${_WINNER_NAME:-}" ]]; then
            _WINNER_NAME="$report_name"
            _WINNER_CONF="${_STRATEGY_CONFIDENCE:-0}"
        fi
        [[ -n "$matched_strategies" ]] && matched_strategies+=","
        matched_strategies+="${report_name}@${strategy_version:-0}"
        _count_lines "$result"
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
run_auto_strategies () {
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

    # Collect strategy directories
    local strategy_dirs=("$STRATEGIES_DIR")
    [[ -d "${HOME:-/nonexistent}/.mfe/strategies" ]] && strategy_dirs+=("${HOME:-/nonexistent}/.mfe/strategies")
    [[ -n "$_OPT_plugin_dir" && -d "$_OPT_plugin_dir" ]] && strategy_dirs+=("$_OPT_plugin_dir")

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
        if [[ -n "$_src_tmpf" ]]; then
            if ! source "$strategy_file" 2>"$_src_tmpf"; then
                _log_warn "Failed to source strategy '$strategy_name', skipping"
                [[ -s "$_src_tmpf" ]] && _log_debug "Source error: $(cat "$_src_tmpf")"
                : > "$_src_tmpf"
                continue
            fi
            [[ -s "$_src_tmpf" ]] && _log_debug "Source warnings for '$strategy_name': $(cat "$_src_tmpf")"
            : > "$_src_tmpf"
        else
            if ! source "$strategy_file" 2>/dev/null; then
                _log_warn "Failed to source strategy '$strategy_name', skipping"
                continue
            fi
        fi

        if ! _detect_strategy "$strategy_name" "$strategy_priority"; then
            unset -f strategy_detect strategy_extract 2>/dev/null
            # Clean up _strat_* helper functions (naming convention per HANDOFF.md)
            # Note: < <(declare -F) process substitution is portable.
            while IFS= read -r _ _ _post_fn; do
                case "$_post_fn" in _strat_*) unset -f "$_post_fn" 2>/dev/null ;; esac
            done < <(declare -F)
            unset _arr 2>/dev/null
            continue
        fi

        _eas_rc=0
        _extract_and_store "$strategy_name" "$strategy_version" || _eas_rc=$?
        unset -f strategy_detect strategy_extract 2>/dev/null
        # Clean up _strat_* helper functions (naming convention per HANDOFF.md)
        while IFS= read -r _ _ _post_fn; do
            case "$_post_fn" in _strat_*) unset -f "$_post_fn" 2>/dev/null ;; esac
        done < <(declare -F)
        unset _arr 2>/dev/null
        if [[ $_eas_rc -eq 2 ]]; then break; fi
    done <<< "$_SORTED_STRATEGIES"
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

    local strategy_dirs=("$STRATEGIES_DIR")
    [[ -d "${HOME:-/nonexistent}/.mfe/strategies" ]] && strategy_dirs+=("${HOME:-/nonexistent}/.mfe/strategies")
    [[ -n "$_OPT_plugin_dir" && -d "$_OPT_plugin_dir" ]] && strategy_dirs+=("$_OPT_plugin_dir")

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
            match_lines="${match_lines}$(printf '%-7s  %-30s  %4s  %4s  %s' 'MATCH' "$strategy_name" "$strategy_priority" "$_STRATEGY_CONFIDENCE" "$reason")"$'\n'
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

    # Matches first (sorted by confidence desc), then misses
    if [[ -n "$match_lines" ]]; then
        printf '%s' "$match_lines" | sort -t'(' -k1,1r
    fi
    if [[ -n "$miss_lines" ]]; then
        printf '%s' "$miss_lines"
    fi

    echo ""
    echo "Tested: $tested  Matched: $matched  Skipped: $skipped"
}
