#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Dispatch functions for envoy-extract
##
## Stream mode, batch mode, post-processing pipeline, and output routing.
## All functions read/write envoy-extract globals directly (no argument passing).
## Dependencies: _log.sh, _helpers.sh, _postprocess.sh, _format.sh,
##               _discovery.sh, _autotune.sh, _interactive.sh
################################################################################

# Stream mode: read stdin line-by-line, apply strategy_extract, emit JSON Lines.
# Expects: _OPT_strategy, _OPT_format already validated by caller.
# Exits the process after completing (early-exit path, not a normal return).
run_stream_mode () {
    if [[ -z "$_OPT_strategy" ]]; then
        _log_error "--stream requires --strategy"
        exit 1
    fi
    if [[ -n "${file:-}" ]]; then
        _log_error "--stream reads from stdin only"
        exit 1
    fi

    # Find and source the strategy
    if ! find_strategy_file "$_OPT_strategy"; then
        _log_error "Strategy not found: $_OPT_strategy"
        exit 1
    fi

    if ! source "$_FOUND_STRATEGY_FILE" 2>/dev/null; then
        _log_error "Failed to source strategy: $_OPT_strategy"
        exit 1
    fi

    # ENV-019: when --record-boundary is set, accumulate input lines into a
    # buffer and flush as a single record when the boundary regex matches.
    # Without the flag, preserve the original line-per-record behavior.
    local boundary="${_OPT_record_boundary:-}"
    local buf="" __sm_result __sm_clean __sm_sline
    local line

    _sm_emit () {
        # Emit the currently-buffered record. Uses _sm_* temp globals to avoid
        # trampling caller-local names such as 'line' in format_json.
        local _text="$1"
        [[ -z "$_text" ]] && return
        __sm_result=""
        if type -t strategy_extract &>/dev/null; then
            __sm_result=$(strategy_extract "$_text")
        fi
        [[ -z "$__sm_result" ]] && return
        __sm_clean=""
        while IFS= read -r __sm_sline; do
            strip_strat_prefix "$__sm_sline"
            __sm_clean+="$_STRIPPED_LINE"$'\n'
        done <<< "$__sm_result"
        __sm_clean="${__sm_clean%$'\n'}"
        format_json "$__sm_clean"
    }

    if [[ -n "$boundary" ]]; then
        while IFS= read -r line; do
            if [[ "$line" =~ $boundary ]]; then
                # Boundary is a start-of-record marker; flush previous buffer first
                if [[ -n "$buf" ]]; then
                    _sm_emit "$buf"
                fi
                buf="$line"
            else
                if [[ -n "$buf" ]]; then
                    buf+=$'\n'"$line"
                else
                    buf="$line"
                fi
            fi
        done
        # Flush trailing buffer on EOF
        if [[ -n "$buf" ]]; then
            _sm_emit "$buf"
        fi
    else
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            _sm_emit "$line"
        done
    fi
    exit 0
}

# Batch mode: read file paths from stdin (one per line), process each file,
# and emit one JSON Lines record per file: {"file": "path", "fields": {...}}.
# Skips binary files and missing files with a warning.
# When --batch-summary is set, emits an additional summary JSON object at the end.
# Exits the process when done (early-exit path, not a normal return).
run_batch_mode () {
    # Redirect stdout to file if --output is set
    if [[ -n "$_OPT_output" ]]; then
        if ! exec > "$_OPT_output"; then
            _log_error "Cannot open output file: $_OPT_output (check path and permissions)"
            exit 1
        fi
    fi

    local _bfile _bsize _bbytes _bclean _bfields _bany=0

    # Summary tracking (used when --batch-summary is set)
    local _bs_total=0
    local _bs_total_fields=0
    local _bs_files_processed=""
    local _bs_files_failed=""
    # Associative arrays for strategy counts and per-file field names
    # ENV-182: explicitly initialize to an empty associative array
    # (not just declare). Bash 4.x with `set -u` aborts on
    # `"${!_bs_strategy_counts[@]}"` expansion of an unassigned-keys
    # assoc array; the empty initializer is the documented fix.
    declare -A _bs_strategy_counts=()
    local -a _bs_all_field_names_per_file=()

    # --batch-out: per-input result files instead of JSON Lines.
    if [[ -n "$_OPT_batch_out" ]]; then
        if ! mkdir -p "$_OPT_batch_out" 2>/dev/null; then
            _log_error "--batch-out: cannot create directory: $_OPT_batch_out"
            exit 1
        fi
    fi

    while IFS= read -r _bfile; do
        [[ -z "$_bfile" ]] && continue

        if [[ ! -f "$_bfile" ]]; then
            _log_warn "batch: file not found: $_bfile"
            if [[ $_OPT_batch_summary -eq 1 ]]; then
                _json_escape "$_bfile"
                if [[ -n "$_bs_files_failed" ]]; then
                    _bs_files_failed+=","
                fi
                _bs_files_failed+="\"${_ESCAPED}\""
            fi
            continue
        fi

        # Size check
        _bsize=$(wc -c < "$_bfile")
        if [[ $_bsize -gt $_OPT_max_input_size ]]; then
            _log_warn "batch: file too large (${_bsize} bytes, max ${_OPT_max_input_size}): $_bfile"
            if [[ $_OPT_batch_summary -eq 1 ]]; then
                _json_escape "$_bfile"
                if [[ -n "$_bs_files_failed" ]]; then
                    _bs_files_failed+=","
                fi
                _bs_files_failed+="\"${_ESCAPED}\""
            fi
            continue
        fi

        # Read content
        text=$(<"$_bfile")

        # Binary detection: count NUL-free bytes straight from the file (as the
        # single-file path does). Comparing the size with what `$(<file)` read
        # also counted the trailing newlines `$(...)` strips, so a text file
        # ending in 3+ newlines was skipped as binary.
        _bbytes=$(tr -d '\0' < "$_bfile" | wc -c)
        if [[ $((_bsize - _bbytes)) -gt 0 ]]; then
            _log_warn "batch: binary file skipped: $_bfile"
            if [[ $_OPT_batch_summary -eq 1 ]]; then
                _json_escape "$_bfile"
                if [[ -n "$_bs_files_failed" ]]; then
                    _bs_files_failed+=","
                fi
                _bs_files_failed+="\"${_ESCAPED}\""
            fi
            continue
        fi

        # Same normalisation the single-file path applies (ANSI strip,
        # line-terminator/space mapping, leading-chrome strip, …) so a file
        # extracts IDENTICALLY in batch and alone.
        preprocess_input_text

        # Set per-file state globals
        file="$_bfile"
        _STATE_filename="$_bfile"
        _STATE_encoding_hint=""
        case "${_bfile##*.}" in
            json|yaml|yml|xml|csv|tsv|ini|toml|hcl) _STATE_encoding_hint="utf-8" ;;
        esac
        _CLEAN_TEXT_CACHE=""
        _CLEAN_TEXT_DONE=0
        # The winner record is only-set-if-empty (ENV-200), so without this
        # reset every file after the first would report the FIRST file's
        # winning strategy in its .meta -- a cross-file leak the JSON Lines
        # path never noticed because it doesn't emit the winner.
        _WINNER_NAME=""
        _WINNER_CONF=0

        # Run strategies (auto only; --chain and --replay are excluded by conflicts)
        run_auto_strategies

        # Post-processing: dedup and rename (skip auto-tune, aggregate, interactive)
        if [[ $_OPT_no_dedup -eq 0 && -n "$output" ]]; then
            local _b_pre="$output"
            output=$(deduplicate_output "$output")
            if [[ -z "$output" && -n "$_b_pre" ]]; then
                output="$_b_pre"
            fi
        fi
        if [[ -n "$_OPT_rename" && -n "$output" ]]; then
            output=$(apply_renames "$output" "$_OPT_rename")
        fi

        # --batch-out: write <name>.wide (formatted like the single-file -f
        # path: STRAT- prefixes stripped, then the -f formatter) and
        # <name>.meta (the --emit-meta line), then move on -- no JSON Lines.
        if [[ -n "$_OPT_batch_out" ]]; then
            local _bo_name; _bo_name="$(basename "$_bfile")"
            _bo_name="${_bo_name%.txt}"
            local _bo_fields=""
            if [[ -n "$output" ]]; then
                _fr_strip_prefix_lines "$output"; _bo_fields="$_FR_STRIPPED"
            fi
            {
                if [[ -n "$_bo_fields" ]]; then
                    case "$_OPT_format" in
                        json)        format_json "$_bo_fields" ;;
                        json-nested) format_json_nested "$_bo_fields" ;;
                        csv)         format_csv "$_bo_fields" ;;
                        tsv)         format_tsv "$_bo_fields" ;;
                        plain)       format_plain "$_bo_fields" ;;
                        yaml)        format_yaml "$_bo_fields" ;;
                        xml)         format_xml "$_bo_fields" ;;
                    esac
                fi
            } > "$_OPT_batch_out/$_bo_name.wide"
            printf '__EXTRACT_META__\t%s\t%s\n' "${_WINNER_NAME:-}" "${_WINNER_CONF:-0}" \
                > "$_OPT_batch_out/$_bo_name.meta"
            _bany=1
            continue
        fi

        # Build fields JSON object from extracted output
        _bfields="{}"
        local _bs_file_field_names=""
        local _bs_file_field_count=0
        if [[ -n "$output" ]]; then
            _bclean=""
            while IFS= read -r _bl; do
                [[ -z "$_bl" ]] && continue
                strip_strat_prefix "$_bl"
                _bclean+="$_STRIPPED_LINE"$'\n'
                # Track field names for summary
                if [[ $_OPT_batch_summary -eq 1 ]]; then
                    local _bfname="${_STRIPPED_LINE%% *}"
                    if [[ -n "$_bs_file_field_names" ]]; then
                        _bs_file_field_names+=$'\n'
                    fi
                    _bs_file_field_names+="$_bfname"
                    _bs_file_field_count=$((_bs_file_field_count + 1))
                fi
            done <<< "$output"
            _bclean="${_bclean%$'\n'}"
            [[ -n "$_bclean" ]] && _bfields=$(format_json "$_bclean")
        fi

        # Emit JSON Lines record
        _json_escape "$_bfile"
        echo "{\"file\": \"${_ESCAPED}\", \"fields\": ${_bfields}}"
        _bany=1

        # Track summary data
        if [[ $_OPT_batch_summary -eq 1 ]]; then
            _bs_total=$((_bs_total + 1))
            _bs_total_fields=$((_bs_total_fields + _bs_file_field_count))

            # Track file name
            _json_escape "$_bfile"
            if [[ -n "$_bs_files_processed" ]]; then
                _bs_files_processed+=","
            fi
            _bs_files_processed+="\"${_ESCAPED}\""

            # Track strategies used (from matched_strategies global, e.g. "json@1.0,colons@1.0")
            if [[ -n "${matched_strategies:-}" ]]; then
                local _bs_ms_rest="$matched_strategies"
                while [[ -n "$_bs_ms_rest" ]]; do
                    local _bs_ms_one="${_bs_ms_rest%%,*}"
                    local _bs_sname="${_bs_ms_one%%@*}"
                    if [[ -n "$_bs_sname" ]]; then
                        local _bs_prev="${_bs_strategy_counts[$_bs_sname]:-0}"
                        _bs_strategy_counts[$_bs_sname]=$((_bs_prev + 1))
                    fi
                    if [[ "$_bs_ms_rest" == *,* ]]; then
                        _bs_ms_rest="${_bs_ms_rest#*,}"
                    else
                        _bs_ms_rest=""
                    fi
                done
            fi

            # Track field names per file for common_fields computation
            _bs_all_field_names_per_file+=("$_bs_file_field_names")
        fi
    done

    if [[ $_bany -eq 0 ]]; then
        _log_warn "batch: no files processed."
    fi

    # Emit summary if requested
    if [[ $_OPT_batch_summary -eq 1 ]]; then
        _batch_emit_summary
    fi

    exit 0
}

# Emit the batch summary JSON object.
# Uses variables from run_batch_mode's scope (called within that function context).
_batch_emit_summary () {
    local _sum_json=""
    _sum_json="{\"_summary\": true"
    _sum_json+=", \"total_files\": ${_bs_total}"
    _sum_json+=", \"total_fields\": ${_bs_total_fields}"

    # strategies_used object — guarded against empty-array iteration
    # for portability with bash 4.x under `set -u` (ENV-182).
    local _sum_strats="{"
    local _sum_sfirst=1
    if [[ ${#_bs_strategy_counts[@]} -gt 0 ]]; then
        local _skey
        for _skey in "${!_bs_strategy_counts[@]}"; do
            if [[ $_sum_sfirst -eq 1 ]]; then
                _sum_sfirst=0
            else
                _sum_strats+=", "
            fi
            _json_escape "$_skey"
            _sum_strats+="\"${_ESCAPED}\": ${_bs_strategy_counts[$_skey]}"
        done
    fi
    _sum_strats+="}"
    _sum_json+=", \"strategies_used\": ${_sum_strats}"

    # common_fields: field names that appear in ALL processed files
    local _sum_common="[]"
    if [[ $_bs_total -gt 0 && ${#_bs_all_field_names_per_file[@]} -gt 0 ]]; then
        # Start with field names from first file, intersect with each subsequent file
        local _cf_result=""
        _cf_result="${_bs_all_field_names_per_file[0]}"

        local _fi
        for (( _fi=1; _fi<${#_bs_all_field_names_per_file[@]}; _fi++ )); do
            local _cf_next="${_bs_all_field_names_per_file[$_fi]}"
            local _cf_intersect=""
            local _cf_name
            while IFS= read -r _cf_name; do
                [[ -z "$_cf_name" ]] && continue
                # Check if this field name exists in _cf_next
                local _cf_found=0
                local _cf_check
                while IFS= read -r _cf_check; do
                    if [[ "$_cf_check" == "$_cf_name" ]]; then
                        _cf_found=1
                        break
                    fi
                done <<< "$_cf_next"
                if [[ $_cf_found -eq 1 ]]; then
                    if [[ -n "$_cf_intersect" ]]; then
                        _cf_intersect+=$'\n'
                    fi
                    _cf_intersect+="$_cf_name"
                fi
            done <<< "$_cf_result"
            _cf_result="$_cf_intersect"
        done

        # Build JSON array from common field names
        if [[ -n "$_cf_result" ]]; then
            _sum_common="["
            local _cf_first=1
            local _cf_item
            while IFS= read -r _cf_item; do
                [[ -z "$_cf_item" ]] && continue
                if [[ $_cf_first -eq 1 ]]; then
                    _cf_first=0
                else
                    _sum_common+=", "
                fi
                _json_escape "$_cf_item"
                _sum_common+="\"${_ESCAPED}\""
            done <<< "$_cf_result"
            _sum_common+="]"
        fi
    fi
    _sum_json+=", \"common_fields\": ${_sum_common}"

    # files_processed array
    _sum_json+=", \"files_processed\": [${_bs_files_processed}]"

    # files_failed array
    _sum_json+=", \"files_failed\": [${_bs_files_failed}]"

    _sum_json+="}"
    echo "$_sum_json"
}

# _xl_can_keep — may the single-file run keep a file-lane result in its file
# (see _xl_begin) through post-processing and output? Only in the plain
# configuration provost uses (`-f tsv`, no field selection, no rename /
# pattern / exclude / aggregate / sort / count / names / raw / cmdline /
# interactive / quiet / verbose / auto-tune), where _xl_finalize is exactly
# run_postprocess + run_output_mode. Anything else takes the variable path.
_xl_can_keep () {
    [[ "$_OPT_format" == tsv && $_OPT_format_explicit -eq 1 ]] || return 1
    [[ $_OPT_auto_tune -eq 0 && -z "$_OPT_chain" && $_OPT_multi -eq 0 ]] || return 1
    [[ -z "$_OPT_rename" && -z "$_OPT_field_pattern" && ${#_OPT_exclude_fields[@]} -eq 0 ]] || return 1
    [[ $_OPT_aggregate -eq 0 && $_OPT_verbose -eq 0 && $_OPT_raw -eq 0 && -z "${fields:-}" ]] || return 1
    [[ $_OPT_cmdline -eq 0 && $_OPT_count -eq 0 && $_OPT_names -eq 0 && $_OPT_sort -eq 0 ]] || return 1
    [[ $_OPT_interactive -eq 0 && $_OPT_quiet -eq 0 ]] || return 1
    return 0
}

# _xl_finalize — run_postprocess + run_output_mode for a kept file-lane
# result, file to file: dedup (_dedup_pipe), the prefix strip (_fr_strip_awk)
# and the TSV formatter (_format_tsv_awk) are the very filters the BIG
# variable paths run, so the output is byte-identical.
_xl_finalize () {
    local _f="$_XL_OUT"
    _XL_OUT=""
    # --- run_postprocess (auto-tune is off in this configuration) ---
    if [[ $_OPT_no_dedup -eq 0 ]] && _xl_has_content "$_f"; then
        _dedup_pipe "$_f" > "$_XL_DIR/lane.dedup"
        if _xl_has_content "$_XL_DIR/lane.dedup"; then
            _f="$_XL_DIR/lane.dedup"
        else
            _log_debug "Deduplication produced empty output; using raw output"
        fi
    fi
    if [[ $_OPT_verbose -eq 1 || $_OPT_debug -eq 1 ]]; then
        _log_info "Strategies: ${strategies_tried:-0} tried, ${strategies_matched:-0} matched, ${total_fields:-0} fields extracted"
    fi
    # --- run_output_mode (-f tsv, all fields) ---
    if ! _xl_has_content "$_f"; then
        output=""            # the no-fields exits, exactly as run_output_mode takes them
        run_output_mode
        return 0
    fi
    if [[ -n "$_OPT_output" ]]; then
        if ! exec > "$_OPT_output"; then
            _log_error "Cannot open output file: $_OPT_output (check path and permissions)"
            exit 1
        fi
    fi
    _fr_strip_awk < "$_f" | _format_tsv_awk
    _output_tty_summary
}

# Post-processing pipeline: dedup, rename, aggregate, verbose summary.
# Reads/modifies: output, _OPT_*, matched_strategies, near_miss_strategies, etc.
run_postprocess () {
    # Auto-tune (noop if _OPT_auto_tune=0)
    run_auto_tune

    # Deduplicate fields across strategies (unless --no-dedup)
    if [[ $_OPT_no_dedup -eq 0 && -n "$output" ]]; then
        local _pre_dedup="$output"
        output=$(deduplicate_output "$output")
        if [[ -z "$output" && -n "$_pre_dedup" ]]; then
            _log_debug "Deduplication produced empty output; using raw output"
            output="$_pre_dedup"
        fi
    fi

    # Apply field renames
    if [[ -n "$_OPT_rename" && -n "$output" ]]; then
        output=$(apply_renames "$output" "$_OPT_rename")
    fi

    # Apply field pattern filter (--field-pattern)
    if [[ -n "$_OPT_field_pattern" && -n "$output" ]]; then
        output=$(apply_field_pattern "$output" "$_OPT_field_pattern")
    fi

    # Apply field exclusions (--exclude-field)
    if [[ ${#_OPT_exclude_fields[@]} -gt 0 && -n "$output" ]]; then
        output=$(apply_exclude_fields "$output")
    fi

    # Apply aggregation
    if [[ $_OPT_aggregate -eq 1 && -n "$output" ]]; then
        local agg_result
        agg_result=$(aggregate_output "$output")
        if [[ -n "$agg_result" ]]; then
            output="$agg_result"
        elif [[ $_OPT_debug -eq 1 || $_OPT_verbose -eq 1 ]]; then
            _log_info "--aggregate: no repeated numeric fields found"
        fi
    fi

    # Verbose/debug summary
    if [[ $_OPT_verbose -eq 1 || $_OPT_debug -eq 1 ]]; then
        _log_info "Strategies: ${strategies_tried:-0} tried, ${strategies_matched:-0} matched, ${total_fields:-0} fields extracted"
    fi

    # Field provenance: show per-strategy field counts in verbose mode (single-pass)
    if [[ $_OPT_verbose -eq 1 && -n "$output" && -n "${matched_strategies:-}" ]]; then
        local _prov
        _prov=$(printf '%s\n' "$output" | awk -F'[\t:]' '
            /^STRAT-/ { sub(/^STRAT-/, "", $1); counts[$1]++ }
            END { for (s in counts) printf "%s (%d)\n", s, counts[s] }
        ' | sort | paste -sd', ' -)
        [[ -n "$_prov" ]] && _log_info "Fields by strategy: $_prov"
    fi
}

# Output mode: apply field selection, sorting, interactive selection, and format routing.
# Expects: output, fields, _OPT_* globals set by caller.
# Exits the process when done.
run_output_mode () {
    # Exit if no output was produced
    local _has_content=0
    if [[ -n "$output" && "${output:0:1}" != $'\n' ]]; then
        # (first line non-empty: the answer without feeding the whole output
        # through a here-string — seconds on a 10 MB capture)
        _has_content=1
    elif [[ -n "$output" ]]; then
        while IFS= read -r _oline; do
            if [[ -n "$_oline" ]]; then _has_content=1; break; fi
        done <<< "$output"
    fi
    if [[ $_has_content -eq 0 ]]; then
        if [[ $_OPT_quiet -eq 1 ]]; then
            exit 1
        fi
        _log_warn "No fields extracted."
        if [[ -n "${near_miss_strategies:-}" ]]; then
            _log_info "Near-miss strategies: $near_miss_strategies"
            _log_info "Try: --min-confidence 0 or --strategy <name>"
        fi
        if [[ $_OPT_verbose -eq 1 || $_OPT_debug -eq 1 ]]; then
            if [[ "${text:-}" == *'{'* || "${text:-}" == *'['* ]]; then
                _log_info "Input may contain JSON; try: --strategy json"
            fi
            if [[ "${text:-}" == *:* ]]; then
                _log_info "Input has colon patterns; try: --strategy colons or --strategy yaml"
            fi
            if [[ "${text:-}" == *=* ]]; then
                _log_info "Input has equals signs; try: --strategy equals or --strategy ini"
            fi
        fi
        exit 0
    fi

    # Quiet mode: just exit 0 (fields were found)
    if [[ $_OPT_quiet -eq 1 ]]; then
        exit 0
    fi

    # Export fully-qualified command line if requested.
    # ENV-182: pre-fix the strategies / file / fields fragments were
    # embedded inside single quotes with no escape — a value
    # containing `'` (e.g. file path "it's a name.txt") produced a
    # broken / injection-prone command that a user might paste into
    # a shell. We now shell-quote each piece via `printf '%q'` so the
    # emitted line round-trips correctly through bash word-splitting.
    if [[ $_OPT_cmdline -eq 1 ]]; then
        local _qstrats _qfile _qfields cmd
        _qstrats=$(printf '%q' "$matched_strategies")
        cmd="mfe --replay ${_qstrats}"
        if [[ -n "${file:-}" ]]; then
            _qfile=$(printf '%q' "$file")
            cmd+=" ${_qfile}"
        fi
        if [[ -n "${fields:-}" ]]; then
            _qfields=$(printf '%q' "$fields")
            cmd+=" ${_qfields}"
        fi
        echo "$cmd"
        exit 0
    fi

    # Count mode: output number of fields
    if [[ $_OPT_count -eq 1 ]]; then
        local _cnt=0
        while IFS= read -r _cline; do
            [[ -n "$_cline" ]] && _cnt=$((_cnt + 1))
        done <<< "$output"
        echo "$_cnt"
        exit 0
    fi

    # Names mode: output field names only
    if [[ $_OPT_names -eq 1 ]]; then
        while IFS= read -r _nline; do
            [[ -z "$_nline" ]] && continue
            strip_strat_prefix "$_nline"
            echo "${_STRIPPED_LINE%% *}"
        done <<< "$output"
        exit 0
    fi

    # Apply --sort: sort output lines by field name (after STRAT prefix)
    if [[ $_OPT_sort -eq 1 && -n "$output" ]]; then
        local _sort_input=""
        while IFS= read -r _srtline; do
            [[ -z "$_srtline" ]] && continue
            strip_strat_prefix "$_srtline"
            local _sort_key="${_STRIPPED_LINE%% *}"
            _sort_input+="${_sort_key}	${_srtline}"$'\n'
        done <<< "$output"
        output=$(echo "${_sort_input%$'\n'}" | sort -t$'\t' -k1,1 | while IFS=$'\t' read -r _sk _sv; do echo "$_sv"; done)
    fi

    # Interactive field selection (before output)
    if [[ $_OPT_interactive -eq 1 && $_has_content -eq 1 ]]; then
        _SELECTED_FIELDS=""
        _interactive_select "$output"
        if [[ -n "$_SELECTED_FIELDS" ]]; then
            fields="$_SELECTED_FIELDS"
        else
            _log_warn "No fields selected."
            exit 0
        fi
    fi

    # Redirect stdout to file if --output is set
    if [[ -n "$_OPT_output" ]]; then
        if ! exec > "$_OPT_output"; then
            _log_error "Cannot open output file: $_OPT_output (check path and permissions)"
            exit 1
        fi
    fi

    # Smart default: when stdout is piped (not a TTY) and no format was
    # explicitly set, default to JSON instead of display table.
    # This makes `mfe data.json | jq` work without needing `-f json`.
    if [[ $_OPT_format_explicit -eq 0 ]] && ! [[ -t 1 ]]; then
        _OPT_format_explicit=1
    fi

    # Display results
    if [[ $_OPT_raw -eq 1 ]]; then
        while IFS= read -r _rline; do
            [[ -z "$_rline" ]] && continue
            echo "$_rline"
        done <<< "$output"
    elif [[ -n "${fields:-}" ]]; then
        local filtered
        filtered=$(filter_fields "$output" "$fields")
        case "$_OPT_format" in
            json)        format_json "$filtered" ;;
            json-nested) format_json_nested "$filtered" ;;
            csv)         format_csv "$filtered" ;;
            tsv)         format_tsv "$filtered" ;;
            plain)       format_plain "$filtered" ;;
            yaml)        format_yaml "$filtered" ;;
            xml)         format_xml "$filtered" ;;
        esac
    elif [[ $_OPT_format_explicit -eq 1 ]]; then
        local all_fields=""
        _fr_strip_prefix_lines "$output"; all_fields="$_FR_STRIPPED"
        case "$_OPT_format" in
            json)        format_json "$all_fields" ;;
            json-nested) format_json_nested "$all_fields" ;;
            csv)         format_csv "$all_fields" ;;
            tsv)         format_tsv "$all_fields" ;;
            plain)       format_plain "$all_fields" ;;
            yaml)        format_yaml "$all_fields" ;;
            xml)         format_xml "$all_fields" ;;
        esac
    else
        display "$output"
    fi

    _output_tty_summary
}

# One-line extraction summary on TTY (informational, not part of data output)
_output_tty_summary () {
    if [[ -t 2 ]] && [[ $_OPT_quiet -eq 0 ]] && [[ $_OPT_count -eq 0 ]] && [[ $_OPT_names -eq 0 ]]; then
        local _sum_fields="${total_fields:-0}"
        local _sum_strats="${strategies_matched:-0}"
        local _sum_tried="${strategies_tried:-0}"
        local _sum_names="${matched_strategies:-}"
        if [[ $_sum_fields -gt 0 ]]; then
            # Show friendly strategy names (strip @version)
            local _sum_display
            _sum_display=$(echo "$_sum_names" | sed 's/@[^,]*//g; s/,/, /g')
            _log_info "Extracted ${_sum_fields} fields via ${_sum_strats}/${_sum_tried} strategies (${_sum_display})"
        fi
    fi
}

# ---------------------------------------------------------------------------
# run_multi_mode — MULTI-DATASET extraction (--multi).
#
# The one-winner model keeps exactly one dataset per input, but some reports
# genuinely hold SEVERAL: iostat prints an avg-cpu kv block AND a Device
# table; kubectl describe holds kv plus two tables. The reviewer's design
# note (2026-08-03): "an input may deserve MULTIPLE outputs — a key/value in
# the same input with a table."
#
# Model: split the (already preprocessed) input on blank-line boundaries into
# blocks; find each block's would-be winner by a detect-only pass over the
# priority-sorted strategy list; group CONSECUTIVE blocks that detect the same
# strategy (a block detecting nothing joins the group before it, so banners
# and stray chrome ride along; blank-line record streams — block-records —
# re-form because their blocks all detect alike); then run the FULL extraction
# pipeline (hints, auto-detection, dedup) on each group independently.
#
# Output contract (stdout): per surviving group, one separator line
#   __DATASET__<TAB>n<TAB>strategy<TAB>confidence
# followed by that group's fields in the -f format. Groups whose extraction
# yields nothing are skipped. Errors/logging stay on stderr as usual.
#
# NOT wired into the provost capture pipeline: a capture stores ONE dataset by
# invariant (meta.tsv, captures/<id>/). Adopting multi-dataset captures is a
# deliberate follow-up (see docs/0003-multi-dataset.md).
# ---------------------------------------------------------------------------

# Detect-only winner for "$1" -> _MULTI_DET (strategy name). Returns 1 if no
# strategy detects. Mirrors run_auto_strategies' filters (generic dirs,
# deprecation, _should_run_strategy, --min-confidence) without extracting,
# and its candidate order: under --rank confidence (the default) every
# detector runs and the highest confidence wins (ties: priority, then name —
# the list is already in that order, so the first strict maximum is kept);
# under --rank priority the first detecting strategy wins. The name only
# GROUPS blocks — each group is then extracted by run_auto_strategies, which
# falls through an empty extract; detect-only cannot, so a block whose top
# candidate would extract nothing still groups under that name.
_multi_detect_name () {
    local btext="$1"
    _MULTI_DET=""
    local _priority strategy_version strategy_file strategy_name _md_best=-1
    local _md_rank=1
    [[ "${_OPT_rank:-confidence}" == priority ]] && _md_rank=0
    while IFS='|' read -r _priority strategy_version strategy_file; do
        [[ -z "$strategy_file" ]] && continue
        strategy_name="${strategy_file##*/}"
        strategy_name="${strategy_name%.sh}"
        _should_run_strategy "$strategy_name" || continue
        read_strategy_metadata "$strategy_file"
        [[ -n "$_META_DEPRECATED" ]] && continue
        _source_strategy_cached "$strategy_file" /dev/null || continue
        _STRATEGY_CONFIDENCE=50
        if strategy_detect "$btext" "${_STATE_filename:-}" "${_STATE_encoding_hint:-}" >/dev/null 2>&1; then
            if [[ $_md_rank -eq 0 ]]; then
                _MULTI_DET="$strategy_name"
                unset -f strategy_detect strategy_extract 2>/dev/null
                return 0
            fi
            if [[ $_STRATEGY_CONFIDENCE -ge ${_OPT_min_confidence:-0} && $_STRATEGY_CONFIDENCE -gt $_md_best ]]; then
                _md_best=$_STRATEGY_CONFIDENCE
                _MULTI_DET="$strategy_name"
            fi
        fi
        unset -f strategy_detect strategy_extract 2>/dev/null
    done <<< "$_SORTED_STRATEGIES"
    [[ -n "$_MULTI_DET" ]]
}

run_multi_mode () {
    # Resolve the strategy list once for the detect-only pass (the per-group
    # run_auto_strategies calls resolve again from cache — cheap).
    _collect_strategy_dirs
    local strategy_dirs=("${_STRATEGY_DIRS[@]}")
    _resolve_strategy_list "${strategy_dirs[@]}"
    if [[ -z "$_SORTED_STRATEGIES" ]]; then
        _log_error "No strategies found."
        return 1
    fi

    # Blank-line blocks, then a secondary split on COMMENT RUNS. Blank lines are
    # not the only boundary: `/proc/slabinfo` puts a `# name <active_objs> …`
    # legend directly above its table with no blank line between, and that
    # legend is neither part of the table nor a table of its own. A maximal run
    # of `#`-led lines therefore splits its block into [before][comments][after],
    # and the comment run is marked so it is kept VERBATIM rather than
    # force-fitted to a parser.
    #
    # A bare `Header:` over an indented body (kubectl describe's `Conditions:` /
    # `Events:`) is deliberately NOT a boundary — see the "sections" note in
    # docs/0003-multi-dataset.md: splitting there pre-empts whole-input
    # strategies that were written to handle the sections together, and
    # measurably degrades that parse.
    local -a blocks=() block_istext=()
    local block="" line
    # A RULE LINE (`--------`, `========`, `----  |  ----`) is a boundary too,
    # and is never data: the reviewer on 7z-benchmark — "a dividing line should
    # never be part of a row; it indicates that summarization is happening
    # below, which means a third dataset" — and on artillery-report, "rows
    # should not contain just -------'s". Such a line splits its block and is
    # dropped. Column pipes and spaces are ignored when testing, so a ruled
    # two-column separator counts as one rule.
    _multi_is_rule () {
        local s="${1//[[:space:]|]/}"
        [[ ${#s} -ge 3 && -z "${s//[-=_~*+]/}" ]]
    }

    # A COUNT PREAMBLE is its own dataset, not the first row of the table below
    # it — the reviewer on cargo-test-summary: "'running 44 tests' is a separate
    # take", and on atlantis-status: "'Ran plan for 2 projects' should be a
    # separate data set". Both were landing as a ragged first row.
    #
    # Two conditions together, so an ordinary HEADER row is never mistaken for
    # one. (a) The line announces a count: >=3 tokens, at least one a bare
    # integer and at least two purely alphabetic — `running 3 tests`,
    # `Ran Plan for 2 projects:`. A header like `Device r/s w/s` or
    # `NAME STATUS` carries no number and is thus excluded. (b) Every line below
    # shares one lead signature (first token, digits collapsed) that differs
    # from the first line's — `test`/`test`/`test` under `running`, `#.`/`#.`
    # under `Ran`. A real table's data rows lead with varied names, so a header
    # over them fails (b) as well.
    # A digit RUN collapses to a single `#`, not one `#` per digit: otherwise
    # `192.168.1.1` and `192.168.1.10` — the same shape, one octet a character
    # longer — come out as different signatures and no table of addresses ever
    # looks uniform.
    _multi_lead_sig () {
        local t="${1#"${1%%[![:space:]]*}"}"
        t="${t%%[[:space:]]*}"
        local o="" i c prev=""
        for ((i = 0; i < ${#t}; i++)); do
            c="${t:i:1}"
            case "$c" in
                [0-9]) [[ "$prev" == "#" ]] || o+="#"; prev="#" ;;
                *)     o+="$c"; prev="$c" ;;
            esac
        done
        printf '%s' "$o"
    }
    _multi_is_count_preamble () {
        local l="$1" nint=0 nalpha=0 ntok=0 tok
        # A preamble is PROSE — single-spaced. A column-aligned header row is
        # separated by 2+ spaces, so `TOP 3 PODS   STATUS` is excluded here even
        # though it carries a number and alphabetic words.
        [[ "${l#"${l%%[![:space:]]*}"}" == *"  "* ]] && return 1
        for tok in $l; do
            ntok=$((ntok + 1))
            if [[ "$tok" =~ ^[0-9]+$ ]]; then nint=$((nint + 1))
            elif [[ "$tok" =~ ^[A-Za-z]+:?$ ]]; then nalpha=$((nalpha + 1)); fi
        done
        [[ $ntok -ge 3 && $nint -ge 1 && $nalpha -ge 2 ]]
    }
    _multi_push_block () {
        local b="${1%$'\n'}" cur="" incomment=-1 l is
        [[ -z "${b//[[:space:]]/}" ]] && return 0
        while IFS= read -r l || [[ -n "$l" ]]; do
            if _multi_is_rule "$l"; then
                if [[ -n "$cur" ]]; then
                    blocks+=("${cur%$'\n'}")
                    block_istext+=("$([[ $incomment -eq 1 ]] && echo 1 || echo 0)")
                    cur=""
                fi
                incomment=-1
                continue
            fi
            if [[ "${l#"${l%%[![:space:]]*}"}" == \#* ]]; then is=1; else is=0; fi
            if [[ $incomment -ne -1 && $is -ne $incomment && -n "$cur" ]]; then
                blocks+=("${cur%$'\n'}"); block_istext+=("$incomment"); cur=""
            fi
            incomment=$is
            cur+="$l"$'\n'
        done <<< "$b"
        if [[ -n "$cur" ]]; then
            blocks+=("${cur%$'\n'}"); block_istext+=("$([[ $incomment -eq 1 ]] && echo 1 || echo 0)")
        fi
    }
    # Peel a count preamble off the front of a block before pushing it.
    #
    # NOT generalised to an N-line prose run, though that is the obvious next
    # step and it was tried: on arp-scan it peels `Interface: …` and `Starting
    # arp-scan 1.9.7 with 256 hosts` correctly, and then the host table STOPS
    # PARSING PROPERLY, because the `arp-scan` columnar spec detects on the
    # literal string `arp-scan` — which lives in the preamble that was just
    # peeled off. The table falls back to aligned-columns with A/B/C/D headings
    # and `Netgear Inc.` split across two cells. The score prefers it anyway
    # (7097 vs 6842: two recovered lines outweigh the damage), so the score is
    # not the guard here. The real fix is to let per-block detection see the
    # whole input as context, which is a bigger change than a boundary rule.
    _multi_push_outer () {
        local b="${1%$'\n'}"
        [[ -z "${b//[[:space:]]/}" ]] && return 0
        local -a ls=()
        local l
        while IFS= read -r l || [[ -n "$l" ]]; do ls+=("$l"); done <<< "$b"
        if [[ ${#ls[@]} -ge 3 ]] && _multi_is_count_preamble "${ls[0]}"; then
            local sig0 sig1 j uniform=1
            sig0="$(_multi_lead_sig "${ls[0]}")"
            sig1="$(_multi_lead_sig "${ls[1]}")"
            for ((j = 2; j < ${#ls[@]}; j++)); do
                [[ "$(_multi_lead_sig "${ls[$j]}")" == "$sig1" ]] || { uniform=0; break; }
            done
            if [[ $uniform -eq 1 && "$sig0" != "$sig1" ]]; then
                _multi_push_block "${ls[0]}"
                local rest="" k
                for ((k = 1; k < ${#ls[@]}; k++)); do rest+="${ls[$k]}"$'\n'; done
                _multi_push_block "$rest"
                return 0
            fi
        fi
        _multi_push_block "$b"
    }
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ -z "${line//[[:space:]]/}" ]]; then
            [[ -n "$block" ]] && _multi_push_outer "$block"
            block=""
            continue
        fi
        block+="$line"$'\n'
    done <<< "$text"
    [[ -n "$block" ]] && _multi_push_outer "$block"
    [[ ${#blocks[@]} -eq 0 ]] && { _log_warn "multi: empty input."; return 0; }

    # Group consecutive same-winner blocks — but only when they also share
    # SHAPE (modal token count ±1). Same-name alone is too coarse: iostat's
    # avg-cpu block and its Device table both detect aligned-columns, yet they
    # are different datasets (6-7 vs 16 tokens per row) — merging them lets
    # the bigger table swallow the kv block. A record STREAM's blocks (colons
    # kv records, block-records) share both name and shape and re-form; a
    # table split by a stray blank line likewise. A nameless block joins the
    # open group (leading chrome opens a nameless group the first named block
    # adopts).
    local -a group_text=() group_name=() group_shape=() group_istext=()
    local gi=-1 bname bshape b bi
    # Grouping is a FUNCTION so a candidate variant (see the comment-as-header
    # candidate below) can re-group a different block list through exactly the
    # same rules, rather than duplicating them.
    #
    # $1 is the SHAPE TOLERANCE — how far two blocks' modal token counts may
    # differ and still re-form into one dataset. Neither value is right in
    # general, so both are tried and scored: 1 keeps a record stream together
    # when one record carries an extra field, but it also welds `iostat`'s
    # 6-column avg-cpu block onto its 5-column Device table and labels the
    # Device header with avg-cpu's column names. 0 keeps those apart but
    # shatters the ragged record stream.
    local _group_tol=1
    _multi_group_blocks () {
    _group_tol="${1:-1}"
    group_text=(); group_name=(); group_shape=(); group_istext=(); gi=-1
    for ((bi = 0; bi < ${#blocks[@]}; bi++)); do
        b="${blocks[$bi]}"
        # A comment run is its own group and never merges with data either side:
        # it is context to keep, not a record set to parse.
        if [[ "${block_istext[$bi]}" -eq 1 ]]; then
            gi=$((gi + 1))
            group_text[$gi]="$b"; group_name[$gi]="text"; group_shape[$gi]=0
            group_istext[$gi]=1
            continue
        fi
        if _multi_detect_name "$b"; then bname="$_MULTI_DET"; else bname=""; fi
        # modal token count of the block's non-blank lines
        bshape=$(printf '%s\n' "$b" | awk 'NF { c[NF]++ } END { best=0; m=0; for (k in c) if (c[k] > best || (c[k] == best && k+0 < m)) { best=c[k]; m=k+0 } print m }')
        local _shape_ok=0
        if [[ $gi -ge 0 ]]; then
            local _gs="${group_shape[$gi]:-0}"
            local _d=$((bshape - _gs)); [[ $_d -lt 0 ]] && _d=$((-_d))
            [[ $_d -le $_group_tol ]] && _shape_ok=1
        fi
        # A comment group never adopts the data that follows it.
        if [[ $gi -ge 0 && "${group_istext[$gi]:-0}" -eq 0 && \
              ( -z "$bname" || ( "$bname" == "${group_name[$gi]}" && $_shape_ok -eq 1 ) || -z "${group_name[$gi]}" ) ]]; then
            group_text[$gi]+=$'\n\n'"$b"
            if [[ -z "${group_name[$gi]}" ]]; then
                group_name[$gi]="$bname"
                group_shape[$gi]="$bshape"
            fi
        else
            gi=$((gi + 1))
            group_text[$gi]="$b"
            group_name[$gi]="$bname"
            group_shape[$gi]="$bshape"
            group_istext[$gi]=0
        fi
    done
    }
    _multi_group_blocks 1

    # --- candidate scoring -------------------------------------------------
    # Extraction is now separated from emission so competing SEGMENTATIONS can
    # be parsed, scored, and only then have the winner printed. Splitting is a
    # search, not a commitment: the whole input always competes against the
    # split, because neither is right in general (see _score.sh).
    _multi_extract_into () {
        # $1 = array-name prefix; extracts every group into <prefix>_name/
        # <prefix>_conf/<prefix>_fields and sets <prefix>_n.
        local _p="$1" _i _n=0
        for ((_i = 0; _i <= gi; _i++)); do
            text="${group_text[$_i]}"
            if [[ "${group_istext[$_i]:-0}" -eq 1 ]]; then
                # ONE ROW PER LINE, not one COLUMN per line. Flat `lineN`
                # fields melt to an N-column single-row table, so a three-line
                # comment run rendered as three columns headed `line1 line2
                # line3` — the reviewer, six times over: "should have the
                # value, not just line1". Entry-prefixed records melt the way
                # every other dataset does, to a `text` column with a row per
                # line, which is also the only shape that stays readable when
                # the run is long.
                # A comment run whose every line is `# key: value` is not prose
                # at all — it is a kv block that happens to be commented out.
                # `age-keygen` writes its metadata that way: "Dataset 1:
                # key/value. Keys = Created, and public key". Kept verbatim it
                # loses the structure the reviewer can see plainly.
                local _t_out="" _t_line _t_n=0 _kv_out="" _kv_n=0 _kv_all=1 _kv_k _kv_v
                while IFS= read -r _t_line || [[ -n "$_t_line" ]]; do
                    [[ -z "${_t_line//[[:space:]]/}" ]] && continue
                    _t_n=$((_t_n + 1))
                    _t_out+="entry${_t_n}.text ${_t_line}"$'\n'
                    local _kv_s="${_t_line#"${_t_line%%[![:space:]]*}"}"
                    _kv_s="${_kv_s#\#}"
                    _kv_s="${_kv_s#"${_kv_s%%[![:space:]]*}"}"
                    if [[ "$_kv_s" =~ ^([A-Za-z][A-Za-z0-9_\ -]*):\ +(.+)$ ]]; then
                        _kv_k="${BASH_REMATCH[1]}"; _kv_v="${BASH_REMATCH[2]}"
                        _kv_n=$((_kv_n + 1))
                        _kv_out+="entry${_kv_n}.key ${_kv_k}"$'\n'
                        _kv_out+="entry${_kv_n}.value ${_kv_v}"$'\n'
                    else
                        _kv_all=0
                    fi
                done <<< "$text"
                [[ $_t_n -gt 0 ]] || continue
                if [[ $_kv_all -eq 1 && $_kv_n -ge 2 ]]; then
                    _kv_out+="total_entries ${_kv_n}"$'\n'
                    eval "${_p}_name[$_n]=commented-kv; ${_p}_conf[$_n]=90"
                    eval "${_p}_fields[$_n]=\"\${_kv_out%\$'\\n'}\""
                    _n=$((_n + 1))
                    continue
                fi
                _t_out+="total_entries ${_t_n}"$'\n'
                eval "${_p}_name[$_n]=text; ${_p}_conf[$_n]=100"
                eval "${_p}_fields[$_n]=\"\${_t_out%\$'\\n'}\""
                _n=$((_n + 1))
                continue
            fi
            _CLEAN_TEXT_CACHE=""; _CLEAN_TEXT_DONE=0
            _WINNER_NAME=""; _WINNER_CONF=0
            output=""
            run_auto_strategies
            if [[ $_OPT_no_dedup -eq 0 && -n "$output" ]]; then
                local _m_pre="$output"
                output=$(deduplicate_output "$output")
                [[ -z "$output" && -n "$_m_pre" ]] && output="$_m_pre"
            fi
            [[ -n "$output" ]] || continue
            local _m_fields="" _m_line
            while IFS= read -r _m_line; do
                [[ -z "$_m_line" ]] && continue
                strip_strat_prefix "$_m_line"
                _m_fields+="$_STRIPPED_LINE"$'\n'
            done <<< "$output"
            eval "${_p}_name[$_n]=\"\${_WINNER_NAME:-}\"; ${_p}_conf[$_n]=\"\${_WINNER_CONF:-0}\""
            eval "${_p}_fields[$_n]=\"\${_m_fields%\$'\\n'}\""
            _n=$((_n + 1))
        done
        eval "${_p}_n=$_n"
    }

    local _whole_text="$text"
    local -a blocks_saved=("${blocks[@]}") istext_saved=("${block_istext[@]}")
    local -a split_name=() split_conf=() split_fields=() split_n=0
    local -a whole_name=() whole_conf=() whole_fields=() whole_n=0
    local -a group_text_saved=() group_name_saved=() group_istext_saved=()
    local _gi_saved=$gi

    _multi_extract_into split
    group_text_saved=("${group_text[@]}")
    group_name_saved=("${group_name[@]}")
    group_istext_saved=("${group_istext[@]:-}")

    # CANDIDATE 1b: the same split with the shape tolerance turned off, so two
    # adjacent blocks re-form only when their rows are the SAME width.
    local -a strict_name=() strict_conf=() strict_fields=() strict_n=0
    _multi_group_blocks 0
    local _strict_gi=$gi
    if [[ $_strict_gi -ne $_gi_saved ]]; then
        _multi_extract_into strict
    fi
    blocks=("${blocks_saved[@]}"); block_istext=("${istext_saved[@]}")
    group_text=("${group_text_saved[@]}")
    group_name=("${group_name_saved[@]}")
    group_istext=("${group_istext_saved[@]}")
    gi=$_gi_saved

    # The rival candidate: no split at all.
    gi=0
    group_text=("$_whole_text"); group_name=(""); group_istext=(0)
    _multi_extract_into whole
    gi=$_gi_saved

    # Namespace each dataset's field names before concatenating, so the
    # `entryN.` prefixes the ragged-row check groups on cannot collide between
    # datasets (every dataset restarts at entry1).
    _multi_ns () { printf '%s\n' "$2" | sed "s/^/d$1_/"; }
    # CANDIDATE 3: a ONE-LINE block folded in as the following block's HEADER,
    # instead of standing as a dataset of its own. The reviewer on aureport:
    # "set 2 is the headers for set 3"; and again on bq-ls, cloc-summary,
    # btrfs-qgroup-show, aureport-login, ansible-galaxy-collection-list, all
    # the same sentence. A RULE LINE between a header and its rows is what
    # separates them — `--------- ---------` reads as a boundary — so the
    # header ends up alone and the table below comes out `A`/`B`/`C`.
    #
    # This was twice implemented as an unconditional rule and twice reverted,
    # because prepending a line that does not actually name the columns shifts
    # every value one place. So the fold is both GUARDED (field counts must
    # agree) and SCORED (it still has to beat the plain split). Where the input
    # is nothing BUT header + table candidate 2 already covers it — the
    # whole-input parse reads the header by itself; candidate 3 is what keeps
    # that available on a COMPOUND input, where taking the whole input would
    # lose the other sections.
    local -a hdr_name=() hdr_conf=() hdr_fields=() hdr_n=0
    local _have_hdr=0 _hj
    local -a _hblocks=() _histext=()
    for ((_hj = 0; _hj < ${#blocks_saved[@]}; _hj++)); do
        # Any single-line block is a header candidate, `#`-commented or not,
        # provided the block below it holds at least two rows to be a header TO.
        if [[ $((_hj + 1)) -lt ${#blocks_saved[@]} && "${istext_saved[$_hj+1]}" -eq 0 ]] &&
           [[ "$(printf '%s\n' "${blocks_saved[$_hj]}" | grep -c .)" -eq 1 ]] &&
           [[ "$(printf '%s\n' "${blocks_saved[$_hj+1]}" | grep -c .)" -ge 2 ]]; then
            local _cb="${blocks_saved[$_hj]}"
            _cb="${_cb#"${_cb%%[![:space:]]*}"}"; _cb="${_cb#\#}"
            _cb="${_cb#"${_cb%%[![:space:]]*}"}"
            # Field counts must agree, or the fold mislabels every value:
            # aureport's `# date time acct host term exe success event` names 8
            # columns for 9-field rows, so every name would land one place off.
            local _hn _rn
            _hn=$(printf '%s\n' "$_cb" | awk '{ print NF }')
            _rn=$(printf '%s\n' "${blocks_saved[$_hj+1]}" | awk 'NF { c[NF]++ } END { best=0; m=0; for (k in c) if (c[k] > best || (c[k] == best && k+0 < m)) { best=c[k]; m=k+0 } print m+0 }')
            # One exception, and only one: a legend is allowed to omit a leading
            # ROW ORDINAL, because that column is generated rather than named
            # (`1.`/`2.` down aureport's first column). Only when EVERY row
            # starts with one, and it gets an explicit name rather than a blank.
            if [[ "${_hn:-0}" -gt 1 && $((_rn - _hn)) -eq 1 ]] &&
               printf '%s\n' "${blocks_saved[$_hj+1]}" |
                 awk 'NF && $1 !~ /^[0-9]+[.)]?$/ { bad = 1 } END { exit (bad ? 1 : 0) }'; then
                _cb="num $_cb"
                _hn=$((_hn + 1))
            fi
            if [[ -n "${_cb//[[:space:]]/}" && "${_hn:-0}" -gt 1 && "${_hn:-0}" -eq "${_rn:-0}" ]]; then
                blocks_saved[$_hj+1]="${_cb}"$'\n'"${blocks_saved[$_hj+1]}"
                _have_hdr=1
                continue
            fi
        fi
        _hblocks+=("${blocks_saved[$_hj]}"); _histext+=("${istext_saved[$_hj]}")
    done
    if [[ $_have_hdr -eq 1 ]]; then
        blocks=("${_hblocks[@]}"); block_istext=("${_histext[@]}")
        _multi_group_blocks
        _multi_extract_into hdr
        gi=$_gi_saved
    fi

    local _cat_split="" _cat_whole="" _cat_hdr="" _q
    for ((_q = 0; _q < split_n; _q++)); do _cat_split+="$(_multi_ns "$_q" "${split_fields[$_q]}")"$'\n'; done
    for ((_q = 0; _q < whole_n; _q++)); do _cat_whole+="$(_multi_ns "$_q" "${whole_fields[$_q]}")"$'\n'; done
    for ((_q = 0; _q < hdr_n;   _q++)); do _cat_hdr+="$(_multi_ns "$_q" "${hdr_fields[$_q]}")"$'\n'; done
    local _cat_strict=""
    for ((_q = 0; _q < strict_n; _q++)); do _cat_strict+="$(_multi_ns "$_q" "${strict_fields[$_q]}")"$'\n'; done
    local _sc_split=0 _sc_whole=0 _sc_hdr=-1 _sc_strict=-1
    _score_parse "$_whole_text" "$_cat_split" "$split_n"; _sc_split=$_SCORE
    _score_parse "$_whole_text" "$_cat_whole" "$whole_n"; _sc_whole=$_SCORE
    if [[ $hdr_n -gt 0 ]]; then
        _score_parse "$_whole_text" "$_cat_hdr" "$hdr_n"; _sc_hdr=$_SCORE
    fi
    if [[ $strict_n -gt 0 ]]; then
        _score_parse "$_whole_text" "$_cat_strict" "$strict_n"; _sc_strict=$_SCORE
    fi
    _log_debug "multi: candidate scores — split($split_n)=$_sc_split strict($strict_n)=$_sc_strict whole($whole_n)=$_sc_whole hdr($hdr_n)=$_sc_hdr"

    # The boundary rules PROPOSED this split; the score only VETOES it when the
    # whole-input parse is MATERIALLY better — more than _MULTI_VETO_MARGIN
    # (2%) ahead. A near-tie keeps the split, because the rules that produced it
    # (a rule line, a comment run, a count preamble) are themselves evidence
    # about the input, and because a margin of a few points out of 10000 is
    # noise in a heuristic score, not a finding. kubectl describe clears the
    # margin by 600; cargo bench differs by 18.
    local -a win_name=() win_conf=() win_fields=()
    local win_n=0
    local _MULTI_VETO_MARGIN=200
    # The strict grouping and the header fold are both REFINEMENTS of the split,
    # so they compete for the split slot first, and the winner of that then
    # faces the whole-input veto. Each only needs to TIE: given equal coverage
    # and tidiness, not welding two differently-shaped blocks together, and
    # naming a column from a header the input supplied, are the better parses.
    if [[ $strict_n -gt 0 && $_sc_strict -ge $_sc_split ]]; then
        split_name=("${strict_name[@]}"); split_conf=("${strict_conf[@]}")
        split_fields=("${strict_fields[@]}"); split_n=$strict_n; _sc_split=$_sc_strict
        _log_debug "multi: strict grouping wins the split slot"
    fi
    if [[ $hdr_n -gt 0 && $_sc_hdr -ge $_sc_split ]]; then
        split_name=("${hdr_name[@]}"); split_conf=("${hdr_conf[@]}")
        split_fields=("${hdr_fields[@]}"); split_n=$hdr_n; _sc_split=$_sc_hdr
        _log_debug "multi: header fold wins the split slot"
    fi
    # EXACT TIE, AND EVERY PIECE OF THE SPLIT TOO SMALL TO HAVE BEEN CHECKED:
    # take the whole. A split can reach a perfect score by CHEATING the
    # ragged-row check — that check needs three entries to call a shape, so
    # shattering a record stream into pieces of one or two entries each escapes
    # it completely. apk-info-a did exactly that, tying 10000 with the clean
    # single-dataset parse and taking it on the keep-the-split rule.
    #
    # Broken on CONFIDENCE, which the score itself ignores. Every strategy
    # reports how sure it was, and a hint-routed or bespoke match is far
    # stronger evidence than a generic fallback — so when two segmentations are
    # indistinguishable by coverage and tidiness, the one the engine was surer
    # of is the better answer. apk-info-a: whole is its own strategy at 95, the
    # split is pkg-config/text-lines/aligned-columns averaging 64. The
    # under-naming legend goes the other way and keeps its split, 85 to 70,
    # which is what stops this rule from resurrecting the mislabelled parse
    # that the score cannot see is wrong.
    local _tie_favours_whole=0
    if [[ $_sc_whole -eq $_sc_split && $whole_n -gt 0 && $whole_n -lt $split_n ]]; then
        local _q2 _cs=0 _cw=0
        for ((_q2 = 0; _q2 < split_n; _q2++)); do _cs=$((_cs + ${split_conf[$_q2]:-0})); done
        for ((_q2 = 0; _q2 < whole_n; _q2++)); do _cw=$((_cw + ${whole_conf[$_q2]:-0})); done
        # Higher mean confidence wins. On an EXACT confidence tie as well,
        # fewer datasets wins — but only if that confidence is high, because
        # equal-and-weak means neither parse is understood and the split's
        # boundaries are still the better evidence. The two cases sit either
        # side of the line: btrfs-filesystem-show ties at 88, the same bespoke
        # strategy reading either the whole input or one filesystem block, and
        # the reviewer wants it merged; checkov-summary ties at 35, generic
        # `colons` on both halves, and its summary line and its finding record
        # are genuinely two things.
        if [[ $((_cw * split_n)) -gt $((_cs * whole_n)) ]]; then
            _tie_favours_whole=1
        elif [[ $((_cw * split_n)) -eq $((_cs * whole_n)) && $((_cw / whole_n)) -ge 80 ]]; then
            _tie_favours_whole=1
        fi
    fi
    if [[ $split_n -gt 0 && $((_sc_whole - _sc_split)) -le $_MULTI_VETO_MARGIN && $_tie_favours_whole -eq 0 ]]; then
        win_name=("${split_name[@]}"); win_conf=("${split_conf[@]}")
        win_fields=("${split_fields[@]}"); win_n=$split_n
    elif [[ $whole_n -gt 0 ]]; then
        win_name=("${whole_name[@]}"); win_conf=("${whole_conf[@]}")
        win_fields=("${whole_fields[@]}"); win_n=$whole_n
    else
        win_name=("${split_name[@]:-}"); win_conf=("${split_conf[@]:-}")
        win_fields=("${split_fields[@]:-}"); win_n=$split_n
    fi

    # Emit the winner.
    local i ds=0
    for ((i = 0; i < win_n; i++)); do
        ds=$((ds + 1))
        printf '__DATASET__\t%d\t%s\t%s\n' "$ds" "${win_name[$i]}" "${win_conf[$i]}"
        local _m_fields="${win_fields[$i]}"
        case "$_OPT_format" in
            json)        format_json "$_m_fields" ;;
            json-nested) format_json_nested "$_m_fields" ;;
            csv)         format_csv "$_m_fields" ;;
            tsv)         format_tsv "$_m_fields" ;;
            plain)       format_plain "$_m_fields" ;;
            yaml)        format_yaml "$_m_fields" ;;
            xml)         format_xml "$_m_fields" ;;
            *)           format_plain "$_m_fields" ;;
        esac
    done
    [[ $ds -eq 0 ]] && _log_warn "multi: no dataset extracted."
    return 0
}
