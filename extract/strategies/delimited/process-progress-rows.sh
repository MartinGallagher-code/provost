#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: process-progress-rows
## Description: `[id] process > NAME (TAG) [PCT%] N of M` pipeline rows (nextflow) -> id/process/tag/percent/done/total rows — hint-routed
## Version: 1.0
## Priority: 47
## Sample: samples/process-progress-rows/basic.txt

# Nextflow's run log mixes a version/launcher header with a formatted process
# table:
#
#   N E X T F L O W  ~  version 24.04.2
#   [a1/2b3c4d] process > FASTQC (sample_01)      [100%] 8 of 8
#   [3a/4b5c6d] process > MULTIQC                 [  0%] 0 of 1
#
# The reviewer: "There is a header here, and then a formatted table." The
# process rows are the table; the header/footer chrome drops:
#
#   id          process   tag         percent   done   total
#   a1/2b3c4d   FASTQC    sample_01   100%      8      8
#   3a/4b5c6d   MULTIQC               0%        0      1
#
# HINT-ONLY: routes on the `] process > ` marker via hints.tsv.

_ppr_re='^\[([^]]+)\][[:space:]]+process[[:space:]]+>[[:space:]]+([^([:space:]]+)([[:space:]]+\(([^)]*)\))?[[:space:]]+\[[[:space:]]*([0-9]+%)\][[:space:]]+([0-9]+)[[:space:]]+of[[:space:]]+([0-9]+)'

strategy_extract () {
    local text="$1"
    local line result="" entry=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        [[ "$line" =~ $_ppr_re ]] || continue
        entry=$((entry + 1))
        result+="entry${entry}.id ${BASH_REMATCH[1]}"$'\n'
        result+="entry${entry}.process ${BASH_REMATCH[2]}"$'\n'
        [[ -n "${BASH_REMATCH[4]}" ]] && result+="entry${entry}.tag ${BASH_REMATCH[4]}"$'\n'
        result+="entry${entry}.percent ${BASH_REMATCH[5]}"$'\n'
        result+="entry${entry}.done ${BASH_REMATCH[6]}"$'\n'
        result+="entry${entry}.total ${BASH_REMATCH[7]}"$'\n'
    done <<< "$text"
    [[ $entry -ge 1 ]] || return 0
    result+="total_entries ${entry}"$'\n'
    echo "$result"
}

strategy_detect () {
    # HINT-ONLY (see header) — never auto-fires.
    _STRATEGY_CONFIDENCE=0
    return 1
}
