#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: systemd-analyze-time
## Description: systemd-analyze (time) boot summary — `Startup finished in A (kernel) + B (userspace) = T` -> one record of per-phase times
## Version: 1.0
## Priority: 20
## Sample: samples/systemd-analyze-time/basic.txt

# `systemd-analyze` / `systemd-analyze time` prints one sentence per boot:
#
#   Startup finished in 3.412s (kernel) + 6.271s (initrd) + 18.998s (userspace) = 28.682s
#   graphical.target reached after 18.921s in userspace.
#
# Each `+`-joined term is a phase time with its phase name in parentheses
# (firmware, loader, kernel, initrd, userspace — the set varies by machine);
# a time may hold a space (`1min 2.345s`). One record: a field per phase,
# `total`, and the default target with the time it was reached. The
# `Startup finished in` sentence with a parenthesised `(kernel)` /
# `(userspace)` phase is systemd's own wording (92, bespoke strong).

_sat_re='^Startup finished in (.*) = (.+)$'
_sat_tgt_re='^([^[:space:]]+) reached after (.+) in userspace\.?$'

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    # PREFILTER (exact)
    [[ "$text" == *"Startup finished in "* ]] || return 1
    [[ "$text" == *"(kernel)"* || "$text" == *"(userspace)"* ]] || return 1
    local line ok=0 other=0
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "${line}" != *[![:space:]]* ]] && continue
        if [[ "$line" =~ $_sat_re ]]; then ok=1
        elif [[ "$line" =~ $_sat_tgt_re ]]; then :
        else other=$((other + 1)); fi
    done
    # the summary sentence, and nothing but its target line around it
    [[ $ok -eq 1 && $other -eq 0 ]] || return 1
    _STRATEGY_CONFIDENCE=92
    return 0
}

strategy_extract () {
    local text="$1" result="" line terms term t total
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        if [[ "$line" =~ $_sat_re ]]; then
            terms="${BASH_REMATCH[1]}"; total="${BASH_REMATCH[2]}"
            terms+=" + "
            while [[ "$terms" == *" + "* ]]; do
                term="${terms%% + *}"; terms="${terms#* + }"
                # `3.412s (kernel)` -> kernel = 3.412s
                if [[ "$term" =~ ^(.+)[[:space:]]+\(([A-Za-z]+)\)$ ]]; then
                    result+="entry1.${BASH_REMATCH[2]} ${BASH_REMATCH[1]}"$'\n'
                fi
            done
            result+="entry1.total ${total}"$'\n'
        elif [[ "$line" =~ $_sat_tgt_re ]]; then
            result+="entry1.target ${BASH_REMATCH[1]}"$'\n'
            result+="entry1.target_reached ${BASH_REMATCH[2]}"$'\n'
        fi
    done
    [[ -n "$result" ]] && result+="total_entries 1"$'\n'
    printf '%s' "$result"
}
