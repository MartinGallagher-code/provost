#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Threshold alerting for envoy-analyze
##
## Checks column statistics against user-defined thresholds and emits
## PASS/FAIL verdicts. Sets threshold_exit_code=1 if any threshold fails.
##
## Reads:  threshold_specs COL_NAMES COL_COUNT
##         COL_TYPE COL_MEAN COL_MIN COL_MAX
## Writes: threshold_exit_code
##         ITEM_TITLES ITEM_BODIES ITEM_TAGS ITEM_KINDS (via add_item)
################################################################################

# Parse a threshold spec like "column_name>100" or "column name<=0.5"
# Sets: _THRESH_COL _THRESH_OP _THRESH_VAL
_parse_threshold_spec () {
    local spec="$1"
    _THRESH_COL=""
    _THRESH_OP=""
    _THRESH_VAL=""

    # Try operators in order of length (longest first to avoid partial match)
    local op
    for op in ">=" "<=" "!=" "==" ">" "<"; do
        if [[ "$spec" == *"$op"* ]]; then
            _THRESH_COL="${spec%%"$op"*}"
            _THRESH_VAL="${spec#*"$op"}"
            _THRESH_OP="$op"
            return 0
        fi
    done
    return 1
}

# Find column index (0-based) by name (case-insensitive)
# Sets _THRESH_COL_IDX or returns 1 if not found
_THRESH_COL_IDX=-1
_find_threshold_col () {
    local target="$1"
    local target_lower="${target,,}"
    _THRESH_COL_IDX=-1
    local i
    for ((i=0; i<COL_COUNT; i++)); do
        local name_lower="${COL_NAMES[$i],,}"
        if [[ "$name_lower" == "$target_lower" ]]; then
            _THRESH_COL_IDX=$i
            return 0
        fi
    done
    return 1
}

# Check a single threshold against summary stats (mean, min, max).
# Returns result text via _THRESH_CHECK_RESULT and sets _THRESH_CHECK_PASS (0=pass, 1=fail)
_THRESH_CHECK_RESULT=""
_THRESH_CHECK_PASS=0

_check_threshold () {
    local col_idx="$1"
    local op="$2"
    local threshold="$3"
    local col_name="${COL_NAMES[$col_idx]}"

    _THRESH_CHECK_RESULT=""
    _THRESH_CHECK_PASS=0

    if [[ "${COL_TYPE[$col_idx]}" != "numeric" ]]; then
        _THRESH_CHECK_RESULT="Column '$col_name' is not numeric — threshold check skipped."
        _THRESH_CHECK_PASS=1
        return
    fi

    local mean="${COL_MEAN[$col_idx]}"
    local min="${COL_MIN[$col_idx]}"
    local max="${COL_MAX[$col_idx]}"

    if [[ -z "$mean" || "$mean" == "NA" ]]; then
        _THRESH_CHECK_RESULT="Column '$col_name' has no numeric data."
        _THRESH_CHECK_PASS=1
        return
    fi

    # Check mean, min, max against the threshold
    local mean_pass min_pass max_pass
    mean_pass=$(awk -v v="$mean" -v t="$threshold" -v op="$op" 'BEGIN{
        if(op==">")  exit !(v>t)
        if(op==">=") exit !(v>=t)
        if(op=="<")  exit !(v<t)
        if(op=="<=") exit !(v<=t)
        if(op=="==") exit !(v==t)
        if(op=="!=") exit !(v!=t)
        exit 1
    }' && echo "PASS" || echo "FAIL")

    min_pass=$(awk -v v="$min" -v t="$threshold" -v op="$op" 'BEGIN{
        if(op==">")  exit !(v>t)
        if(op==">=") exit !(v>=t)
        if(op=="<")  exit !(v<t)
        if(op=="<=") exit !(v<=t)
        if(op=="==") exit !(v==t)
        if(op=="!=") exit !(v!=t)
        exit 1
    }' && echo "PASS" || echo "FAIL")

    max_pass=$(awk -v v="$max" -v t="$threshold" -v op="$op" 'BEGIN{
        if(op==">")  exit !(v>t)
        if(op==">=") exit !(v>=t)
        if(op=="<")  exit !(v<t)
        if(op=="<=") exit !(v<=t)
        if(op=="==") exit !(v==t)
        if(op=="!=") exit !(v!=t)
        exit 1
    }' && echo "PASS" || echo "FAIL")

    local overall="PASS"
    # For > and >= thresholds: check that min satisfies (strongest test)
    # For < and <= thresholds: check that max satisfies (strongest test)
    # For == and !=: check mean
    case "$op" in
        ">"  |">=") [[ "$min_pass" == "FAIL" ]] && overall="FAIL" ;;
        "<"  |"<=") [[ "$max_pass" == "FAIL" ]] && overall="FAIL" ;;
        "==" |"!=") [[ "$mean_pass" == "FAIL" ]] && overall="FAIL" ;;
    esac

    _THRESH_CHECK_RESULT="Threshold: $col_name $op $threshold
Mean: $mean ($mean_pass)
Min:  $min ($min_pass)
Max:  $max ($max_pass)
Verdict: $overall"

    if [[ "$overall" == "FAIL" ]]; then
        _THRESH_CHECK_PASS=1
    else
        _THRESH_CHECK_PASS=0
    fi
}

# ENV-027: boolean composition for threshold expressions.
#
# Grammar:
#   expr   := term (OR term)*
#   term   := factor (AND factor)*
#   factor := '(' expr ')' | atom
#   atom   := column op value
#
# Tokenize to _THRESH_TOKENS (one token per element). AND/OR are emitted in
# canonical upper case. Parentheses are separate tokens. Conditions are kept
# whole (column, operator, and value merged) so existing _parse_threshold_spec
# can handle them as before.
_tokenize_threshold_expr () {
    _THRESH_TOKENS=()
    local expr="$1"
    local len=${#expr}
    local i=0
    local cur=""
    _push_cur () {
        local c="${cur#"${cur%%[![:space:]]*}"}"
        c="${c%"${c##*[![:space:]]}"}"
        if [[ -n "$c" ]]; then
            case "${c,,}" in
                and) _THRESH_TOKENS+=("AND") ;;
                or)  _THRESH_TOKENS+=("OR") ;;
                *)   _THRESH_TOKENS+=("$c") ;;
            esac
        fi
        cur=""
    }
    while (( i < len )); do
        local ch="${expr:i:1}"
        case "$ch" in
            '(')
                _push_cur
                _THRESH_TOKENS+=("(")
                ;;
            ')')
                _push_cur
                _THRESH_TOKENS+=(")")
                ;;
            ' '|$'\t')
                # Whitespace alone doesn't split a condition like "a>1"; we
                # decide word boundaries based on context. To tokenize AND/OR
                # reliably, treat whitespace as a soft boundary: if the
                # accumulated text (case-insensitive) is exactly "and" or "or"
                # when we hit whitespace, flush. Otherwise accumulate the
                # whitespace too so "col name > 5" stays one token.
                case "${cur,,}" in
                    "and"|"or")
                        _push_cur
                        ;;
                    *)
                        cur+="$ch"
                        ;;
                esac
                # If the next non-space content starts the AND/OR keyword,
                # flush so "a>1 AND b>2" tokenizes as [a>1, AND, b>2].
                local j=$((i + 1))
                while (( j < len )) && [[ "${expr:j:1}" == " " || "${expr:j:1}" == $'\t' ]]; do
                    j=$((j + 1))
                done
                # Peek the next 3-4 chars for AND / OR followed by space/paren/EOF
                local peek3="${expr:j:3}"
                local peek2="${expr:j:2}"
                local after3="${expr:j+3:1}"
                local after2="${expr:j+2:1}"
                if [[ "${peek3,,}" == "and" && ( "$after3" == " " || "$after3" == $'\t' || "$after3" == "(" || -z "$after3" ) ]]; then
                    _push_cur
                fi
                if [[ "${peek2,,}" == "or" && ( "$after2" == " " || "$after2" == $'\t' || "$after2" == "(" || -z "$after2" ) ]]; then
                    _push_cur
                fi
                ;;
            *)
                cur+="$ch"
                ;;
        esac
        i=$((i + 1))
    done
    _push_cur
}

# Evaluate a condition atom. Takes the token string, populates
# _THRESH_ATOM_PASS (0=pass, 1=fail) and _THRESH_ATOM_DETAIL.
_eval_threshold_atom () {
    local spec="$1"
    _THRESH_ATOM_PASS=1
    _THRESH_ATOM_DETAIL=""
    if ! _parse_threshold_spec "$spec"; then
        _THRESH_ATOM_DETAIL="Invalid condition syntax: '$spec'"
        return
    fi
    if ! _find_threshold_col "$_THRESH_COL"; then
        _THRESH_ATOM_DETAIL="Column '$_THRESH_COL' not found"
        return
    fi
    _check_threshold "$_THRESH_COL_IDX" "$_THRESH_OP" "$_THRESH_VAL"
    _THRESH_ATOM_PASS="$_THRESH_CHECK_PASS"
    _THRESH_ATOM_DETAIL="$_THRESH_CHECK_RESULT"
}

# Recursive-descent parser/evaluator over _THRESH_TOKENS using a cursor.
# Sets _THRESH_EVAL_PASS (0=pass, 1=fail). Collects per-atom detail lines
# into _THRESH_EVAL_DETAIL.
_THRESH_CUR=0
_THRESH_EVAL_PASS=1
_THRESH_EVAL_DETAIL=""
_THRESH_EVAL_ERROR=""

_thresh_peek () {
    _THRESH_PEEK="${_THRESH_TOKENS[$_THRESH_CUR]:-}"
}
_thresh_consume () {
    _THRESH_CUR=$((_THRESH_CUR + 1))
}

# Returns pass/fail via _THRESH_EVAL_PASS on each call
_parse_expr () {
    _parse_term
    [[ -n "$_THRESH_EVAL_ERROR" ]] && return
    local left="$_THRESH_EVAL_PASS"
    while :; do
        _thresh_peek
        [[ "$_THRESH_PEEK" == "OR" ]] || break
        _thresh_consume
        _parse_term
        [[ -n "$_THRESH_EVAL_ERROR" ]] && return
        # OR: pass if either side passes
        if [[ "$left" == "0" || "$_THRESH_EVAL_PASS" == "0" ]]; then
            left=0
        else
            left=1
        fi
    done
    _THRESH_EVAL_PASS="$left"
}

_parse_term () {
    _parse_factor
    [[ -n "$_THRESH_EVAL_ERROR" ]] && return
    local left="$_THRESH_EVAL_PASS"
    while :; do
        _thresh_peek
        [[ "$_THRESH_PEEK" == "AND" ]] || break
        _thresh_consume
        _parse_factor
        [[ -n "$_THRESH_EVAL_ERROR" ]] && return
        # AND: pass only if both sides pass
        if [[ "$left" == "0" && "$_THRESH_EVAL_PASS" == "0" ]]; then
            left=0
        else
            left=1
        fi
    done
    _THRESH_EVAL_PASS="$left"
}

_parse_factor () {
    _thresh_peek
    if [[ "$_THRESH_PEEK" == "(" ]]; then
        _thresh_consume
        _parse_expr
        [[ -n "$_THRESH_EVAL_ERROR" ]] && return
        _thresh_peek
        if [[ "$_THRESH_PEEK" != ")" ]]; then
            _THRESH_EVAL_ERROR="Expected ')' at token position $_THRESH_CUR"
            return
        fi
        _thresh_consume
        return
    fi
    if [[ -z "$_THRESH_PEEK" || "$_THRESH_PEEK" == "AND" || "$_THRESH_PEEK" == "OR" || "$_THRESH_PEEK" == ")" ]]; then
        _THRESH_EVAL_ERROR="Expected condition at token position $_THRESH_CUR, got '$_THRESH_PEEK'"
        return
    fi
    _eval_threshold_atom "$_THRESH_PEEK"
    if [[ -z "$_THRESH_ATOM_DETAIL" || "$_THRESH_ATOM_DETAIL" == Invalid* || "$_THRESH_ATOM_DETAIL" == Column*not\ found ]]; then
        _THRESH_EVAL_ERROR="$_THRESH_ATOM_DETAIL"
        _thresh_consume
        return
    fi
    _THRESH_EVAL_DETAIL+="${_THRESH_ATOM_DETAIL}"$'\n\n'
    _THRESH_EVAL_PASS="$_THRESH_ATOM_PASS"
    _thresh_consume
}

# Main entry point: run all threshold checks.
run_threshold_checks () {
    if [[ ${#threshold_specs[@]} -eq 0 ]]; then
        return
    fi

    local pass_count=0
    local fail_count=0
    local spec

    for spec in "${threshold_specs[@]}"; do
        # Reset parser state
        _THRESH_CUR=0
        _THRESH_EVAL_PASS=1
        _THRESH_EVAL_DETAIL=""
        _THRESH_EVAL_ERROR=""

        _tokenize_threshold_expr "$spec"
        if [[ ${#_THRESH_TOKENS[@]} -eq 0 ]]; then
            add_item "Threshold check: $spec" "Empty threshold expression" "DIAGNOSTIC" "threshold"
            threshold_exit_code=1
            fail_count=$((fail_count + 1))
            continue
        fi

        _parse_expr
        if [[ -n "$_THRESH_EVAL_ERROR" ]]; then
            add_item "Threshold check: $spec" "Threshold parse error: $_THRESH_EVAL_ERROR
Expression: '$spec'
Supported syntax: column>value, column<=value, etc.
Compose with AND / OR / parentheses, e.g. '(a>1 OR b>1) AND c<10'" "DIAGNOSTIC" "threshold"
            threshold_exit_code=1
            fail_count=$((fail_count + 1))
            continue
        fi

        local tag="GOOD"
        if [[ "$_THRESH_EVAL_PASS" != "0" ]]; then
            tag="DIAGNOSTIC"
            threshold_exit_code=1
            fail_count=$((fail_count + 1))
        else
            pass_count=$((pass_count + 1))
        fi

        local verdict="PASS"
        [[ "$_THRESH_EVAL_PASS" != "0" ]] && verdict="FAIL"
        add_item "Threshold check: $spec" "Expression: $spec
Verdict: $verdict

Per-condition detail:
${_THRESH_EVAL_DETAIL}" "$tag" "threshold"
    done

    # Summary item
    local total=$((pass_count + fail_count))
    local summary_tag="GOOD"
    if [[ $fail_count -gt 0 ]]; then
        summary_tag="DIAGNOSTIC"
    fi
    add_item "Threshold summary" "$pass_count/$total checks passed, $fail_count failed" "$summary_tag" "threshold_summary"
}
