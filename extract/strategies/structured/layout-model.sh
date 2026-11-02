#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: layout-model
## Description: The learned layout model (extract/model/) — labels each line's role and field starts, decides each table's columns once, cuts every value from the input. EXPLICIT ONLY: provost runs it for a capture the quality gate would hold (PROVOST_MODEL=1); it never competes in detection
## Version: 1.0
## Priority: 99
## Confidence-Max: 60
## Sample: samples/layout-model/basic.txt

# Gradient-boosted trees trained on the tidy corpus (ml/, docs/model-*.md),
# evaluated in plain Python (extract/model/layout_model.py, stdlib only), so
# it needs python3 and nothing else. Like kv-report it answers only when
# asked for by name (`-s layout-model`): the ordinary ranking never sees it,
# so no other input's parse can change because it exists. The engine measures
# its output with the same line coverage and column consistency as every
# parser, and provost files it only when that output passes the quality gate.
#
# It declines (no output) when python3 is missing, when the model file is
# missing, and above the runtime's line limit (layout_model.MAX_LINES).

_lm_script () { printf '%s\n' "${SCRIPT_DIR:-.}/model/layout_model.py"; }

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    [[ "${_OPT_strategy:-}" == layout-model ]] || return 1
    command -v "${PROVOST_PYTHON:-python3}" >/dev/null 2>&1 || return 1
    [[ -f "$(_lm_script)" ]] || return 1
    [[ "$text" == *[![:space:]]* ]] || return 1
    # 60: above the commit threshold (50), below every format parser; the
    # quality gate, not this number, decides whether the result is filed
    _STRATEGY_CONFIDENCE=60
    _STRATEGY_CONFIDENCE_REASON="learned layout model (explicit)"
    return 0
}

strategy_extract () {
    local text="$1"
    # PROVOST_LM_RECORDS: records the model already made for exactly this
    # text (one part of a report it segmented, labelled in the context of
    # the whole document) — emit them so the engine measures them like any
    # parse, instead of labelling the part again out of context.
    if [[ -n "${PROVOST_LM_RECORDS:-}" && -r "$PROVOST_LM_RECORDS" ]]; then
        cat "$PROVOST_LM_RECORDS"
        return 0
    fi
    printf '%s\n' "$text" | "${PROVOST_PYTHON:-python3}" "$(_lm_script)" - 2>/dev/null
}
