#!/bin/bash
################################################################################
## Helper functions for envoy-analyze
##
## String utilities, escaping, delimiter detection, and common helpers.
##
## Reads:  (varies per helper; inputs are function arguments)
##         emit_summary kind_filter analysis_list (read by _will_keep_kind)
## Writes: AWK_ISMISSING (module-level definition)
################################################################################

err () {
    echo "envoy-analyze: error: $*" >&2
    exit 1
}

warn () {
    echo "envoy-analyze: warning: $*" >&2
}

################################################################################
## ENV-126: filter-aware computation gate
##
## Returns 0 (true) iff the caller should compute / report items of `kind`.
## A `run_*` analysis function should call this early and `return 0` on a
## false answer to skip its expensive work. Output for any *un*-filtered
## run is byte-identical to the no-skip pipeline.
##
## Conservative-by-default: if any signal makes us uncertain whether the
## kind would be kept, we say yes. Skipping is purely an optimisation;
## a false negative prints stale data, which is the worst-case failure.
##
## Skip-eligible scenarios:
##   - User passed `--kinds K1,K2,...` and `kind` is not in the list.
##
## Always-run scenarios (anything that could need every kind's globals):
##   - `EF_FILTER_SKIP=0` escape hatch (regression-test toggle).
##   - `--summary` is on — `run_summary_verdict` reads from every kind.
##   - `--analysis-list 1,2,...` (selecting by item id requires all
##     items to exist before the post-pass picker runs).
##   - `--mode benchmark|monitor` — modes rewrite tags after analyses
##     run; without knowing the post-rewrite tag we can't safely skip.
################################################################################
_will_keep_kind () {
    local kind="$1"
    # Escape hatch.
    [[ "${EF_FILTER_SKIP:-1}" == "0" ]] && return 0
    # --summary needs everything (run_summary_verdict reads from every kind).
    [[ "${emit_summary:-0}" == "1" ]] && return 0
    # Numeric `--analysis-list` picks items by id post-hoc.
    [[ -n "${analysis_list:-}" ]] && return 0
    # No --kinds filter → keep everything (tag-only filters and mode
    # rewrites operate over the full kind set; skipping the awks here
    # would mask items the user might still want).
    [[ -z "${kind_filter:-}" ]] && return 0
    # --kinds is set: skip iff the kind is not listed.
    local k
    for k in ${kind_filter//,/ }; do
        [[ "$kind" == "$k" ]] && return 0
    done
    return 1
}

normalize_list () {
    echo "$1" | tr ',' ' ' | tr -s ' ' | sed 's/^ *//;s/ *$//'
}

trim () {
    echo "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

detect_delim () {
    local file="$1"
    local header
    header=$(head -n 1 "$file")
    if [[ "$header" == *$'\t'* ]]; then
        echo $'\t'
    elif [[ "$header" == *'|'* ]]; then
        echo '|'
    elif [[ "$header" == *';'* ]] && [[ "$header" != *','* ]]; then
        echo ';'
    elif [[ "$header" == *':'* ]] && [[ "$header" != *','* ]]; then
        echo ':'
    else
        echo ','
    fi
}

# Shared AWK function for missing value detection.
# Inject into AWK blocks with: awk "$AWK_ISMISSING" '...'
AWK_ISMISSING='function ismissing(v) {
    return (v=="" || v=="NA" || v=="N/A" || v=="null" || v=="NULL" || v=="NaN" || v=="nan" || v=="None" || v=="none" || v=="-" || v=="." || v=="#N/A")
}'

json_escape () {
    awk 'BEGIN{ORS=""; first=1}
        {
            gsub(/\\/, "\\\\");
            gsub(/"/, "\\\"");
            gsub(/\t/, "\\t");
            gsub(/\r/, "");
            if (!first) printf "\\n";
            printf "%s", $0;
            first=0;
        }' <<< "$1"
}

escape_csv () {
    local v="$1"
    v="${v//$'\r'/}"
    v="${v//$'\n'/\\n}"
    v="${v//\"/\"\"}"
    printf '"%s"' "$v"
}

escape_tsv () {
    local v="$1"
    v="${v//$'\r'/}"
    v="${v//$'\n'/\\n}"
    v="${v//$'\t'/ }"
    printf "%s" "$v"
}

# Case-insensitive match of a name against a comma-separated list.
# Usage: _name_in_csv_list_ci "zip_code" "zip_code,id,total"
_name_in_csv_list_ci () {
    local needle="${1,,}"
    local csv="$2"
    local old_ifs="$IFS"
    IFS=',' read -ra _items <<< "$csv"
    IFS="$old_ifs"
    local v
    for v in "${_items[@]}"; do
        # Trim whitespace
        v="${v#"${v%%[![:space:]]*}"}"
        v="${v%"${v##*[![:space:]]}"}"
        if [[ "${v,,}" == "$needle" ]]; then
            return 0
        fi
    done
    return 1
}

list_contains () {
    local needle="$1"
    shift
    local v
    for v in "$@"; do
        if [[ "$v" == "$needle" ]]; then
            return 0
        fi
    done
    return 1
}

# Float comparison.
# Usage: float_cmp "3.14" ">=" "2.0"  (operators: > >= < <= == !=)
#
# ENV-164: implementation rewritten to delegate to awk. The previous
# bash-arithmetic version scaled by 1e6 and overflowed any value above
# ~9.2e12 (signed-64-bit max / 1e6) — a column of nanosecond timestamps,
# financial cents, or large IDs would silently produce wrong comparison
# results. It also rejected scientific notation (`1e-05`) with
# "value too great for base", which awk routinely produces from
# `printf %g`. The awk delegation handles both: numbers go through
# awk's IEEE-754 double conversion (~15-17 significant digits, scientific
# notation native), and the per-call awk fork is acceptable because
# float_cmp is called O(columns) per analyze run, not in tight loops.
float_cmp () {
    local a="$1" op="$2" b="$3"
    awk -v a="$a" -v b="$b" -v op="$op" '
        BEGIN {
            af = a + 0
            bf = b + 0
            if (op == ">")  exit !(af >  bf)
            if (op == ">=") exit !(af >= bf)
            if (op == "<")  exit !(af <  bf)
            if (op == "<=") exit !(af <= bf)
            if (op == "==") exit !(af == bf)
            if (op == "!=") exit !(af != bf)
            exit 1
        }
    '
}
