#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: systemd-analyze-security
## Description: Parse `systemd-analyze security` setting table (NAME DESCRIPTION EXPOSURE)
## Version: 1.0
## Priority: 22
## Sample: samples/systemd-analyze-security/basic.txt

# `systemd-analyze security <unit>` prints a table of hardening settings, each
# row prefixed with a ✓/✗ glyph: NAME, a free-text DESCRIPTION, and an optional
# EXPOSURE number. It ends with an "→ Overall exposure level ..." summary line.
# One record per setting row; header and summary are skipped.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    [[ "$text" == *"Overall exposure level"* ]] || return 1
    [[ "$text" == *"EXPOSURE"* ]] || return 1
    _STRATEGY_CONFIDENCE=92
    return 0
}

strategy_extract () {
    printf '%s\n' "$1" | awk '
        {
            if ($0 ~ /^[ \t]*$/) next
            if ($0 ~ /NAME[ \t]+DESCRIPTION[ \t]+EXPOSURE/) next
            if ($0 ~ /Overall exposure/) next
            # Remaining rows are glyph-prefixed settings: glyph NAME DESC [EXPOSURE].
            if (NF < 3) next
            name=$2
            expo=""
            last=$NF
            if (last ~ /^[0-9]+(\.[0-9]+)?$/) { expo=last; hi=NF-1 } else { hi=NF }
            desc=""
            for(i=3;i<=hi;i++) desc=desc (i>3?"_":"") $i
            e++
            print "entry" e ".name " name
            print "entry" e ".description " (desc==""?"-":desc)
            print "entry" e ".exposure " (expo==""?"-":expo)
        }
        END{ if(e>0) print "total_entries " e }
    '
}
