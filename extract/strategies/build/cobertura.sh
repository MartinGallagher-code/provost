#!/bin/bash
## Name: cobertura
## Description: Extract coverage metrics from Cobertura XML reports
## Version: 1.0
## Priority: 25
## Sample: samples/cobertura/basic.xml

# Helper: extract the value of an XML attribute from a tag string.
# Sets _COB_ATTR_VAL to the attribute value, or "" if not found.
_strat_cob_attr () {
    local tag="$1"
    local attr="$2"
    _COB_ATTR_VAL=""

    local search=" ${attr}=\""
    case "$tag" in
        *"${search}"*)
            local after="${tag#*"${search}"}"
            _COB_ATTR_VAL="${after%%\"*}"
            return 0
            ;;
    esac
    return 1
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=85

    # Must contain <coverage or DOCTYPE coverage
    [[ "$text" == *"<coverage"* || "$text" == *"DOCTYPE coverage"* ]] || return 1

    return 0
}

strategy_extract () {
    local text="$1"

    local result=""
    local pkg_num=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Strip leading whitespace
        local trimmed="$line"
        while [[ "$trimmed" == " "* || "$trimmed" == "	"* ]]; do trimmed="${trimmed#?}"; done

        # Match <coverage ...> tag
        case "$trimmed" in
            '<coverage '*)
                _strat_cob_attr "$trimmed" "line-rate"
                [[ -n "$_COB_ATTR_VAL" ]] && result+="line-rate $_COB_ATTR_VAL"$'\n'

                _strat_cob_attr "$trimmed" "branch-rate"
                [[ -n "$_COB_ATTR_VAL" ]] && result+="branch-rate $_COB_ATTR_VAL"$'\n'

                _strat_cob_attr "$trimmed" "lines-covered"
                [[ -n "$_COB_ATTR_VAL" ]] && result+="lines-covered $_COB_ATTR_VAL"$'\n'

                _strat_cob_attr "$trimmed" "lines-valid"
                [[ -n "$_COB_ATTR_VAL" ]] && result+="lines-valid $_COB_ATTR_VAL"$'\n'

                _strat_cob_attr "$trimmed" "branches-covered"
                [[ -n "$_COB_ATTR_VAL" ]] && result+="branches-covered $_COB_ATTR_VAL"$'\n'

                _strat_cob_attr "$trimmed" "branches-valid"
                [[ -n "$_COB_ATTR_VAL" ]] && result+="branches-valid $_COB_ATTR_VAL"$'\n'

                _strat_cob_attr "$trimmed" "complexity"
                [[ -n "$_COB_ATTR_VAL" ]] && result+="complexity $_COB_ATTR_VAL"$'\n'

                _strat_cob_attr "$trimmed" "version"
                [[ -n "$_COB_ATTR_VAL" ]] && result+="version $_COB_ATTR_VAL"$'\n'

                _strat_cob_attr "$trimmed" "timestamp"
                [[ -n "$_COB_ATTR_VAL" ]] && result+="timestamp $_COB_ATTR_VAL"$'\n'
                ;;
        esac

        # Match <package ...> tag
        case "$trimmed" in
            '<package '*)
                pkg_num=$((pkg_num + 1))

                _strat_cob_attr "$trimmed" "name"
                [[ -n "$_COB_ATTR_VAL" ]] && result+="package${pkg_num}.name $_COB_ATTR_VAL"$'\n'

                _strat_cob_attr "$trimmed" "line-rate"
                [[ -n "$_COB_ATTR_VAL" ]] && result+="package${pkg_num}.line-rate $_COB_ATTR_VAL"$'\n'

                _strat_cob_attr "$trimmed" "branch-rate"
                [[ -n "$_COB_ATTR_VAL" ]] && result+="package${pkg_num}.branch-rate $_COB_ATTR_VAL"$'\n'

                _strat_cob_attr "$trimmed" "complexity"
                [[ -n "$_COB_ATTR_VAL" ]] && result+="package${pkg_num}.complexity $_COB_ATTR_VAL"$'\n'
                ;;
        esac

    done <<< "$text"

    echo "$result"
}
