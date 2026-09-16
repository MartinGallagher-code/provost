#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: ledger-balance
## Description: Right-aligned `AMOUNT  account` balance reports (hledger/ledger/beancount bal) -> amount/account rows
## Version: 1.0
## Priority: 44
## Sample: samples/ledger-balance/basic.txt

# Plain-text accounting balance reports right-align an amount, then a 2+-space
# gap, then a colon-joined account path — closed by a dash rule and a grand
# total standing alone:
#
#                   $8,821.00  assets:bank:checking
#                  -$10,025.00  income:salary
#   --------------------
#                           0
#
# aligned-columns mangles these (the indent and the rule line defeat it, and
# the lone total has no second column), so the whole report fell to a blob.
# Here: one row per `amount | account`, the rule line dropped as decoration,
# and the grand total kept as a scalar `total` field — the reviewer's "you
# lost data" was aimed exactly at rows vanishing.
#
# Gates: every non-blank line must be an amount+account pair, a dash rule, or
# a lone amount AFTER a dash rule (the total). Amounts are strictly money/
# number shaped (optional -, optional currency symbol, digits with , and .),
# so `option  description` help text never reads as a balance.

_lb_amount_re='^-?[$€£]?-?[0-9][0-9,]*(\.[0-9]+)?$'

# `AMOUNT  account` -> _LB_AMT / _LB_ACCT. Account is a single token.
_lb_split () {
    local l="$1"
    l="${l#"${l%%[![:space:]]*}"}"
    l="${l%"${l##*[![:space:]]}"}"
    [[ "$l" =~ ^([^[:space:]]+)[\ ]{2,}([^[:space:]]+)$ ]] || return 1
    _LB_AMT="${BASH_REMATCH[1]}"
    _LB_ACCT="${BASH_REMATCH[2]}"
    [[ "$_LB_AMT" =~ $_lb_amount_re ]] || return 1
    return 0
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    local line rows=0 rule=0 total=0 body=""
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        body="${line#"${line%%[![:space:]]*}"}"
        body="${body%"${body##*[![:space:]]}"}"
        if [[ "$body" =~ ^-{4,}$ ]]; then
            rule=1
            continue
        fi
        if _lb_split "$line"; then
            # amount+account after the rule would be a second section — fine,
            # but a pair BEFORE any rule is the normal body.
            rows=$((rows + 1))
            continue
        fi
        # A lone amount is the grand total: only valid after the rule.
        if [[ $rule -eq 1 && "$body" =~ $_lb_amount_re ]]; then
            total=$((total + 1))
            continue
        fi
        return 1
    done <<< "$text"
    # >=2 balance rows and at most one grand total; the rule is optional but
    # a total without a rule is not this shape.
    [[ $rows -ge 2 && $total -le 1 ]] || return 1
    # At least one amount must actually carry a currency symbol: plain
    # integers before a path are a size listing (gsutil du, zoxide query -l),
    # not a ledger, and their existing 2-col parses were already right.
    [[ "$text" == *'$'* || "$text" == *'€'* || "$text" == *'£'* ]] || return 1
    _STRATEGY_CONFIDENCE=84
    return 0
}

strategy_extract () {
    local text="$1"
    local line result="" entry=0 rule=0 body=""
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        body="${line#"${line%%[![:space:]]*}"}"
        body="${body%"${body##*[![:space:]]}"}"
        if [[ "$body" =~ ^-{4,}$ ]]; then rule=1; continue; fi
        if _lb_split "$line"; then
            entry=$((entry + 1))
            result+="entry${entry}.amount ${_LB_AMT}"$'\n'
            result+="entry${entry}.account ${_LB_ACCT}"$'\n'
            continue
        fi
        if [[ $rule -eq 1 && "$body" =~ $_lb_amount_re ]]; then
            result+="total ${body}"$'\n'
        fi
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
