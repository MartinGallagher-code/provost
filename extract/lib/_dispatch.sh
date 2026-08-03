#!/bin/bash
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

        # Binary detection (below) needs the RAW text; the shared
        # normalisation pipeline runs right after it.
        _bbytes=$(printf '%s' "$text" | wc -c)
        if [[ $((_bsize - _bbytes)) -gt 2 ]]; then
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
                while IFS= read -r _bl; do
                    [[ -z "$_bl" ]] && continue
                    strip_strat_prefix "$_bl"
                    _bo_fields+="$_STRIPPED_LINE"$'\n'
                done <<< "$output"
                _bo_fields="${_bo_fields%$'\n'}"
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
    if [[ -n "$output" ]]; then
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
        while IFS= read -r _aline; do
            [[ -z "$_aline" ]] && continue
            strip_strat_prefix "$_aline"
            all_fields+="$_STRIPPED_LINE"$'\n'
        done <<< "$output"
        all_fields="${all_fields%$'\n'}"
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

    # One-line extraction summary on TTY (informational, not part of data output)
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
