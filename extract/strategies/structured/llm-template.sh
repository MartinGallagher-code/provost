#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: llm-template
## Description: A parsing template Claude wrote for this tool (extract/llm/): regular expressions per kind of line, applied offline and deterministically. EXPLICIT ONLY: provost runs it under --llm for a capture the quality gate would hold; it never competes in detection
## Version: 1.0
## Priority: 99
## Confidence-Max: 60
## Sample: samples/llm-template/basic.txt

# The template comes from PROVOST_LLM_TEMPLATE (a file), or is the stored one
# whose `detect` pattern recognises the input and that covers most of it:
# first the store's templates (PROVOST_LLM_TEMPLATE_DIRS, colon-separated),
# then the ones shipped in extract/llm/templates/. This strategy only APPLIES
# templates; writing one (asking Claude) is provost's --llm, never the engine.
# With PROVOST_LLM_RECORDS it emits records provost already made from a
# template (one block of a multi-block template), so the engine measures
# them like any parse. It prints the template's first block otherwise.

_lt_script () { printf '%s\n' "${SCRIPT_DIR:-.}/llm/template.py"; }

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    [[ "${_OPT_strategy:-}" == llm-template ]] || return 1
    command -v python3 >/dev/null 2>&1 || return 1
    [[ -f "$(_lt_script)" ]] || return 1
    [[ "$text" == *[![:space:]]* ]] || return 1
    # 60: above the commit threshold (50), below every format parser; the
    # quality gate, not this number, decides whether the result is filed
    _STRATEGY_CONFIDENCE=60
    _STRATEGY_CONFIDENCE_REASON="LLM-written template (explicit)"
    return 0
}

strategy_extract () {
    local text="$1" tpl="${PROVOST_LLM_TEMPLATE:-}"
    if [[ -n "${PROVOST_LLM_RECORDS:-}" && -r "$PROVOST_LLM_RECORDS" ]]; then
        cat "$PROVOST_LLM_RECORDS"
        return 0
    fi
    if [[ -z "$tpl" ]]; then
        tpl="$(printf '%s\n' "$text" | python3 "$(_lt_script)" find - \
            --dirs "${PROVOST_LLM_TEMPLATE_DIRS:-}" 2>/dev/null | cut -f1)"
    fi
    [[ -n "$tpl" && -r "$tpl" ]] || return 0
    printf '%s\n' "$text" | python3 "$(_lt_script)" apply "$tpl" - --records 2>/dev/null
}
