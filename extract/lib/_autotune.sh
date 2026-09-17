#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Auto-tune logic for envoy-extract
##
## Two-phase automatic confidence adjustment and best-match ranking.
## Reads and modifies globals: output, _OPT_min_confidence, matched_strategies,
## near_miss_strategies, strategies_tried, strategies_matched, total_fields.
## Dependencies: _discovery.sh (run_auto_strategies), _log.sh
################################################################################

# Auto-tune: confidence fallback + best-match ranking.
# Phase 1: If nothing matched with current confidence, retry with lower thresholds.
# Phase 2: When multiple strategies matched, rank by field count and report the best.
run_auto_tune () {
    [[ $_OPT_auto_tune -eq 0 || -n "$_OPT_chain" ]] && return

    # Phase 1: Confidence auto-adjust
    # If no strategies matched and min_confidence > 0, retry with lower thresholds.
    local _at_has_content=0
    if [[ -n "$output" ]]; then
        while IFS= read -r _atline; do
            if [[ -n "$_atline" ]]; then _at_has_content=1; break; fi
        done <<< "$output"
    fi
    if [[ $_at_has_content -eq 0 && $_OPT_min_confidence -gt 0 ]]; then
        local _at_orig_confidence=$_OPT_min_confidence
        local _at_threshold
        for _at_threshold in 50 25 10 0; do
            if [[ $_at_threshold -ge $_at_orig_confidence ]]; then continue; fi
            _OPT_min_confidence=$_at_threshold
            output=""
            matched_strategies=""
            near_miss_strategies=""
            strategies_tried=0
            strategies_matched=0
            total_fields=0
            run_auto_strategies
            _at_has_content=0
            if [[ -n "$output" ]]; then
                while IFS= read -r _atline; do
                    if [[ -n "$_atline" ]]; then _at_has_content=1; break; fi
                done <<< "$output"
            fi
            if [[ $_at_has_content -eq 1 ]]; then
                if [[ $_OPT_debug -eq 1 || $_OPT_verbose -eq 1 ]]; then
                    _log_info "[auto-tune] Matched at confidence threshold $_at_threshold (original: $_at_orig_confidence)"
                fi
                break
            fi
        done
        _OPT_min_confidence=$_at_orig_confidence
    fi

    # Phase 2: Best-match ranking
    # When multiple strategies matched, rank by field count and suggest the best.
    if [[ $strategies_matched -gt 1 && -n "$matched_strategies" ]]; then
        local _at_best_name="" _at_best_count=0 _at_remaining="$matched_strategies"
        local _at_entry _at_sname _at_scount _at_ol
        while [[ -n "$_at_remaining" ]]; do
            _at_entry="${_at_remaining%%,*}"
            if [[ "$_at_remaining" == *","* ]]; then
                _at_remaining="${_at_remaining#*,}"
            else
                _at_remaining=""
            fi
            _at_sname="${_at_entry%%@*}"
            [[ -z "$_at_sname" ]] && continue
            _at_scount=0
            while IFS= read -r _at_ol; do
                case "$_at_ol" in
                    "STRAT-${_at_sname}:"*) _at_scount=$((_at_scount + 1)) ;;
                esac
            done <<< "$output"
            if [[ $_at_scount -gt $_at_best_count ]]; then
                _at_best_count=$_at_scount
                _at_best_name="$_at_sname"
            fi
        done
        if [[ -n "$_at_best_name" && ($_OPT_verbose -eq 1 || $_OPT_debug -eq 1) ]]; then
            _log_info "[auto-tune] Best strategy: $_at_best_name ($_at_best_count fields)"
            _log_info "[auto-tune] Replay with: mfe --strategy $_at_best_name"
        fi
    fi
}
