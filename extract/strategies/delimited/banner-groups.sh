#!/bin/bash
## Name: banner-groups
## Description: `=== SECTION ===` banners over per-line entries (fossil timeline) -> group/value rows
## Version: 1.0
## Priority: 34
## Sample: samples/banner-groups/basic.txt

# Section banners as `=== text ===` lines, entries beneath each:
#
#   === 2026-07-06 ===
#   10:15:42 [a1b2c3d4e5] Add login form validation (user: alice tags: trunk)
#   === 2026-07-05 ===
#   18:44:03 [d4e5f6a7b8] Refactor session handling (user: carol)
#
# A flat line list keeps the banner as a data row and loses which section each
# entry belongs to. Here the banner text is carried down: `group | value`, one
# row per entry — the reviewer's "each section should have the repeated ===
# column value, with each line beneath". (Splitting the entry line itself into
# time/hash/message would need per-tool knowledge; the group carry-down is the
# generic part.)
#
# NOTE: the engine's preprocessing already deletes `== word ==` banners
# (exactly-two-equals decoration). THREE-plus equals runs survive to here as
# group labels — that split of meaning is deliberate and this strategy depends
# on it.
#
# Gates: >=2 banners; the FIRST non-blank line is a banner (entries before any
# banner have no group to belong to); every banner has non-empty inner text;
# `--- text ---` footer lines (fossil's `--- entry limit (6) reached ---`) are
# decoration and dropped, but only as the LAST non-blank line.

# EXACTLY three equals per side: fossil/nst label their sections `=== x ===`,
# while pytest/rocm draw DECORATION rules 10-20 equals wide -- the run length
# is the difference between a label and a horizontal line with words in it.
_bg_banner_re='^[[:space:]]*===[[:space:]]+([^=]+[^=[:space:]])[[:space:]]+===[[:space:]]*$'
_bg_footer_re='^[[:space:]]*---+[[:space:]].*[[:space:]]---+[[:space:]]*$'

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    local line banners=0 members=0 first=1 last_kind=""
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        if [[ "$line" =~ $_bg_banner_re ]]; then
            banners=$((banners + 1)); first=0; last_kind=B
            continue
        fi
        [[ $first -eq 1 ]] && return 1
        if [[ "$line" =~ $_bg_footer_re ]]; then
            last_kind=F
            continue
        fi
        # A footer that was not last after all — reject rather than guess.
        [[ "$last_kind" == F ]] && return 1
        # A member that IS a `Key: value` line means these sections hold kv
        # blocks (smartctl info sections) — the kv/embedded parsers read those
        # with real fields; welding them into group|value would lose them.
        [[ "$line" =~ ^[[:space:]]*[A-Za-z][A-Za-z0-9\ _-]*:[[:space:]] ]] && return 1
        members=$((members + 1)); last_kind=M
    done <<< "$text"
    [[ $banners -ge 2 && $members -ge $banners ]] || return 1
    _STRATEGY_CONFIDENCE=83
    return 0
}

strategy_extract () {
    local text="$1"
    local line result="" entry=0 group=""
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        if [[ "$line" =~ $_bg_banner_re ]]; then
            group="${BASH_REMATCH[1]}"
            continue
        fi
        [[ "$line" =~ $_bg_footer_re ]] && continue
        [[ -n "$group" ]] || continue
        local body="${line#"${line%%[![:space:]]*}"}"
        body="${body%"${body##*[![:space:]]}"}"
        entry=$((entry + 1))
        result+="entry${entry}.group ${group}"$'\n'
        result+="entry${entry}.value ${body}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
