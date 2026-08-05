#!/bin/bash
## Name: first-word-kv
## Description: Each line's FIRST token is the key, the rest is the value (git blame --porcelain, cat-file, git log) — hint-routed
## Version: 1.0
## Priority: 58
## Sample: samples/first-word-kv/basic.txt

# Many git plumbing outputs are one `key rest-of-line` record per line:
#
#   author Alice Nguyen
#   author-mail <alice@example.com>
#   summary Add parser
#   a1b2c3d4 1 1 3
#
# and git log --oneline:
#
#   a1b2c3d Fix null pointer in request handler
#
# The reviewer's repeated note across the git family: "key value." The first
# whitespace-run splits key from value; the value keeps its own spaces. A bare
# `- ` bullet or leading `#` comment lead is stripped first (gnutls-cli-info's
# `- Certificate type: X.509` also routes here, though its value keeps the
# inner colon).
#
# This is a deliberately GENERIC 2-column split, far too broad to auto-detect
# safely (half the corpus is space-separated) — its `strategy_detect` is a
# strict guard used only as a sanity check; in practice it is reached through
# a `hints.tsv` row, which bypasses detection. Blank lines separate records
# but add none of their own.

strategy_extract () {
    local text="$1"
    local line result="" entry=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        # Strip a leading bullet / comment marker.
        local s="${line#"${line%%[![:space:]]*}"}"
        s="${s#- }"; s="${s#\* }"
        [[ -z "${s//[[:space:]]/}" ]] && continue
        local key="${s%%[[:space:]]*}"
        local val="${s#"$key"}"
        val="${val#"${val%%[![:space:]]*}"}"
        val="${val%"${val##*[![:space:]]}"}"
        entry=$((entry + 1))
        result+="entry${entry}.key ${key}"$'\n'
        [[ -n "$val" ]] && result+="entry${entry}.value ${val}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}

strategy_detect () {
    # HINT-ONLY. A bare first-token split is far too broad to auto-detect
    # without stealing half the corpus from colons/aligned-columns, so this
    # never fires on its own — it is reached exclusively through a hints.tsv
    # row (which bypasses detection). The extract path is exercised in tests
    # via `--strategy first-word-kv`.
    _STRATEGY_CONFIDENCE=0
    return 1
}
