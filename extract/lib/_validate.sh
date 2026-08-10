#!/bin/bash
################################################################################
## Strategy validation for envoy-extract
##
## Validate strategy files for required functions, metadata headers,
## sample paths, naming conventions, and version format.
## Dependencies: _log.sh, _discovery.sh (read_strategy_metadata, build_strategy_list)
################################################################################

# Validate a single strategy file.
# Prints PASS/FAIL lines to stdout. Returns 0 if all checks pass, 1 otherwise.
validate_strategy () {
    local filepath="$1"
    local _v_errors=0

    if [[ ! -f "$filepath" ]]; then
        echo "FAIL: File not found: $filepath"
        return 1
    fi

    local fname="${filepath##*/}"
    fname="${fname%.sh}"

    # Check 1: Required metadata headers
    read_strategy_metadata "$filepath"

    if [[ -n "$_META_NAME" ]]; then
        echo "PASS: Has ## Name: header ($_META_NAME)"
    else
        echo "FAIL: Missing ## Name: header"
        _v_errors=$((_v_errors + 1))
    fi

    if [[ -n "$_META_DESCRIPTION" ]]; then
        echo "PASS: Has ## Description: header"
    else
        echo "FAIL: Missing ## Description: header"
        _v_errors=$((_v_errors + 1))
    fi

    if [[ "$_META_VERSION" != "0" ]]; then
        echo "PASS: Has ## Version: header ($_META_VERSION)"
    else
        echo "FAIL: Missing ## Version: header"
        _v_errors=$((_v_errors + 1))
    fi

    # 99 is the DEFAULT priority as well as a legal one to declare, so
    # `_META_PRIORITY == 99` cannot tell a missing header from a deliberate
    # one — it reported "Missing ## Priority:" about files that plainly have
    # the line. Ask the file.
    if grep -qE '^##[[:space:]]*Priority:[[:space:]]*[0-9]+' "$filepath"; then
        echo "PASS: Has ## Priority: header ($_META_PRIORITY)"
    else
        echo "FAIL: Missing ## Priority: header (defaulting to 99)"
        _v_errors=$((_v_errors + 1))
    fi

    # Check 2: Version format (N.N)
    if [[ "$_META_VERSION" =~ ^[0-9]+\.[0-9]+$ ]]; then
        echo "PASS: Version format is valid"
    else
        echo "FAIL: Version format should be N.N (got: $_META_VERSION)"
        _v_errors=$((_v_errors + 1))
    fi

    # Check 3: Filename matches ## Name: header
    if [[ -n "$_META_NAME" ]]; then
        if [[ "$_META_NAME" == "$fname" ]]; then
            echo "PASS: Filename matches ## Name: header"
        else
            echo "FAIL: Filename '$fname' does not match ## Name: '$_META_NAME'"
            _v_errors=$((_v_errors + 1))
        fi
    fi

    # Check 4: Required functions exist (must be actual function definitions,
    # not comments or strings containing the function name)
    local _v_has_detect=0 _v_has_extract=0
    local _v_line _v_trimmed
    while IFS= read -r _v_line; do
        # Strip leading whitespace for matching
        _v_trimmed="${_v_line#"${_v_line%%[![:space:]]*}"}"
        # Skip comment lines
        case "$_v_trimmed" in '#'*) continue ;; esac
        case "$_v_trimmed" in
            'strategy_detect'*'()'*|'strategy_detect '*'('*|'function strategy_detect'*) _v_has_detect=1 ;;
            'strategy_extract'*'()'*|'strategy_extract '*'('*|'function strategy_extract'*) _v_has_extract=1 ;;
        esac
    done < "$filepath"

    if [[ $_v_has_detect -eq 1 ]]; then
        echo "PASS: Has strategy_detect function"
    else
        echo "FAIL: Missing strategy_detect function"
        _v_errors=$((_v_errors + 1))
    fi

    if [[ $_v_has_extract -eq 1 ]]; then
        echo "PASS: Has strategy_extract function"
    else
        echo "FAIL: Missing strategy_extract function"
        _v_errors=$((_v_errors + 1))
    fi

    # Check 5: ## Sample: header and path exists
    local _v_sample=""
    local _v_n=0
    while IFS= read -r _v_line; do
        _v_n=$((_v_n + 1))
        [[ $_v_n -gt 15 ]] && break
        case "$_v_line" in
            '## Sample: '*)
                _v_sample="${_v_line#'## Sample: '}"
                break
                ;;
        esac
    done < "$filepath"

    if [[ -n "$_v_sample" ]]; then
        echo "PASS: Has ## Sample: header ($_v_sample)"
        # Check if sample path exists relative to samples dir
        local _v_samples_dir="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/samples"
        if [[ -f "$_v_samples_dir/$_v_sample" ]]; then
            echo "PASS: Sample file exists"
        else
            echo "WARN: Sample file not found: $_v_sample"
        fi
    else
        echo "WARN: Missing ## Sample: header"
    fi

    # Check 6: Syntax check (bash -n)
    if bash -n "$filepath" 2>/dev/null; then
        echo "PASS: Syntax check (bash -n)"
    else
        echo "FAIL: Syntax error detected by bash -n"
        _v_errors=$((_v_errors + 1))
    fi

    # Check 7: _STRATEGY_CONFIDENCE is set in strategy_detect
    local _v_has_confidence=0
    while IFS= read -r _v_line; do
        case "$_v_line" in
            *'_STRATEGY_CONFIDENCE='*) _v_has_confidence=1; break ;;
        esac
    done < "$filepath"
    if [[ $_v_has_confidence -eq 1 ]]; then
        echo "PASS: Sets _STRATEGY_CONFIDENCE in detect"
    else
        echo "WARN: Does not set _STRATEGY_CONFIDENCE (will default to 50)"
    fi

    # Check 8: Helper function naming convention (_strat_* required)
    local _v_bad_helpers=0
    while IFS= read -r _v_line; do
        # Match function definitions: word ()
        case "$_v_line" in
            strategy_detect*|strategy_extract*) continue ;;
            _strat_*'()'*|_strat_*'('*) continue ;;
            *'() {'*|*'()'*)
                # Extract function name
                local _v_fn="${_v_line%%(*}"
                _v_fn="${_v_fn# }"
                _v_fn="${_v_fn% }"
                case "$_v_fn" in
                    strategy_detect|strategy_extract) ;;
                    _strat_*) ;;
                    *)
                        if [[ $_v_bad_helpers -eq 0 ]]; then
                            echo "WARN: Helper function '$_v_fn' does not use _strat_* naming convention"
                        fi
                        _v_bad_helpers=$((_v_bad_helpers + 1))
                        ;;
                esac
                ;;
        esac
    done < "$filepath"
    if [[ $_v_bad_helpers -eq 0 ]]; then
        echo "PASS: Helper function naming convention (_strat_*)"
    fi

    if [[ $_v_errors -gt 0 ]]; then
        return 1
    fi
    return 0
}

# Validate all strategies in all strategy directories.
# Prints a summary report. Returns 0 if all pass, 1 if any fail.
validate_all_strategies () {
    local strategy_dirs=("$STRATEGIES_DIR")
    [[ -d "${HOME:-/nonexistent}/.mfe/strategies" ]] && strategy_dirs+=("${HOME:-/nonexistent}/.mfe/strategies")
    [[ -n "${_OPT_plugin_dir:-}" && -d "${_OPT_plugin_dir:-}" ]] && strategy_dirs+=("$_OPT_plugin_dir")

    local sorted_list
    sorted_list=$(build_strategy_list "${strategy_dirs[@]}")

    if [[ -z "$sorted_list" ]]; then
        _log_error "No strategies found."
        return 1
    fi

    local _va_total=0 _va_pass=0 _va_fail=0
    while IFS='|' read -r _priority _version strategy_file; do
        [[ -z "$strategy_file" ]] && continue
        _va_total=$((_va_total + 1))
        local sname="${strategy_file##*/}"
        sname="${sname%.sh}"
        echo "--- Validating: $sname ($strategy_file)"
        if validate_strategy "$strategy_file"; then
            _va_pass=$((_va_pass + 1))
        else
            _va_fail=$((_va_fail + 1))
        fi
        echo ""
    done <<< "$sorted_list"

    echo "========================================"
    echo "Validation: $_va_total strategies, $_va_pass passed, $_va_fail failed"
    echo "========================================"

    if [[ $_va_fail -gt 0 ]]; then
        return 1
    fi
    return 0
}

# ENV-018: self-validation. Run each strategy's detect() against its declared
# ## Sample: file and report strategies whose self-confidence is below the
# threshold (default 75). Miscalibrated strategies indicate either a wrong
# sample, a buggy detector, or inflated confidence scoring.
#
# Honors globals:
#   _OPT_self_validate_threshold  (int, default 75)
#   _OPT_self_validate_strategy   (string, filter to one strategy name)
#
# Returns 0 if all strategies meet the threshold, 1 otherwise.
self_validate_strategies () {
    local threshold="${_OPT_self_validate_threshold:-75}"
    local filter="${_OPT_self_validate_strategy:-}"

    local strategy_dirs=("$STRATEGIES_DIR")
    [[ -d "${HOME:-/nonexistent}/.mfe/strategies" ]] && strategy_dirs+=("${HOME:-/nonexistent}/.mfe/strategies")
    [[ -n "${_OPT_plugin_dir:-}" && -d "${_OPT_plugin_dir:-}" ]] && strategy_dirs+=("$_OPT_plugin_dir")

    local sorted_list
    sorted_list=$(build_strategy_list "${strategy_dirs[@]}")
    if [[ -z "$sorted_list" ]]; then
        _log_error "No strategies found."
        return 1
    fi

    # Sample paths in ## Sample: headers are relative to the EnvoyExtract root
    # (they already include the "samples/" prefix).
    local envoy_extract_root="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

    local total=0 pass=0 below=0 no_sample=0 missing_file=0
    local -a _below_lines=()
    local -a _no_sample_lines=()
    local -a _missing_file_lines=()

    printf "Self-validation: running each strategy's detect() against its declared sample\n"
    printf "Threshold: %d\n\n" "$threshold"
    printf "  %-22s %-8s %-30s %s\n" "STRATEGY" "CONF" "SAMPLE" "VERDICT"
    printf "  %-22s %-8s %-30s %s\n" "--------" "----" "------" "-------"

    while IFS='|' read -r _priority _version strategy_file; do
        [[ -z "$strategy_file" ]] && continue
        local name="${strategy_file##*/}"
        name="${name%.sh}"
        [[ -n "$filter" && "$name" != "$filter" ]] && continue
        total=$((total + 1))

        # Look up the ## Sample: header
        local sample=""
        local _line _n=0
        while IFS= read -r _line; do
            _n=$((_n + 1))
            [[ $_n -gt 20 ]] && break
            case "$_line" in
                '## Sample: '*) sample="${_line#'## Sample: '}"; break ;;
            esac
        done < "$strategy_file"

        if [[ -z "$sample" ]]; then
            no_sample=$((no_sample + 1))
            _no_sample_lines+=("$name")
            printf "  %-22s %-8s %-30s %s\n" "$name" "-" "(no sample)" "SKIP"
            continue
        fi

        local sample_path="$envoy_extract_root/$sample"
        if [[ ! -f "$sample_path" ]]; then
            missing_file=$((missing_file + 1))
            _missing_file_lines+=("$name: $sample")
            printf "  %-22s %-8s %-30s %s\n" "$name" "-" "$sample" "MISSING"
            continue
        fi

        # Source the strategy and invoke detect() against the sample.
        # Run in a subshell so a strategy's state changes don't leak.
        local conf
        conf=$(
            set +e
            unset -f strategy_detect strategy_extract 2>/dev/null
            source "$strategy_file" >/dev/null 2>&1
            if ! type -t strategy_detect >/dev/null 2>&1; then
                echo "-1"
                exit 0
            fi
            local text
            text=$(cat "$sample_path")
            _STRATEGY_CONFIDENCE=50
            _STRATEGY_CONFIDENCE_REASON=""
            if ! strategy_detect "$text" "$(basename "$sample_path")" "" >/dev/null 2>&1; then
                echo "0"
                exit 0
            fi
            # Clamp
            [[ "$_STRATEGY_CONFIDENCE" -lt 0 ]] && _STRATEGY_CONFIDENCE=0
            [[ "$_STRATEGY_CONFIDENCE" -gt 100 ]] && _STRATEGY_CONFIDENCE=100
            echo "$_STRATEGY_CONFIDENCE"
        )
        # Strip anything but the first line/integer
        conf="${conf%%$'\n'*}"

        if [[ "$conf" == "-1" ]]; then
            printf "  %-22s %-8s %-30s %s\n" "$name" "-" "$sample" "NO-DETECT-FN"
            continue
        fi

        if [[ "$conf" -ge "$threshold" ]]; then
            pass=$((pass + 1))
            printf "  %-22s %-8s %-30s %s\n" "$name" "$conf" "$sample" "PASS"
        else
            below=$((below + 1))
            _below_lines+=("$name (conf $conf, sample $sample)")
            printf "  %-22s %-8s %-30s %s\n" "$name" "$conf" "$sample" "BELOW"
        fi
    done <<< "$sorted_list"

    echo ""
    echo "========================================"
    printf "Self-validation: %d total, %d pass, %d below threshold, %d no sample, %d missing file\n" \
        "$total" "$pass" "$below" "$no_sample" "$missing_file"
    echo "========================================"

    if [[ $below -gt 0 ]]; then
        echo ""
        echo "Below threshold ($threshold):"
        local _line
        for _line in "${_below_lines[@]}"; do
            echo "  - $_line"
        done
    fi
    if [[ $missing_file -gt 0 ]]; then
        echo ""
        echo "Missing sample files:"
        for _line in "${_missing_file_lines[@]}"; do
            echo "  - $_line"
        done
    fi

    # Exit 1 if any strategy fell below threshold or has a missing sample file.
    if [[ $below -gt 0 || $missing_file -gt 0 ]]; then
        return 1
    fi
    return 0
}
