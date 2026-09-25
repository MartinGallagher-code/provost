#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

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
# `- ` bullet or leading `#` comment lead is stripped first.
#
# The same first-token split also serves a colon-delimited family the reviewer
# marked "colons are delimiters: remove from values" — `pwdx` (`1337:
# /var/www/html`), `ip rule list` (`0:\tfrom all lookup local`), and `nmcli
# connection show` (`connection.id:  homewifi`). Their key token ends in a
# colon, so a single trailing `:` is stripped from the key. Git-family keys
# carry no trailing colon, so the strip is a no-op there.
#
# This is a deliberately GENERIC 2-column split, far too broad to auto-detect
# safely (half the corpus is space-separated) — its `strategy_detect` is a
# strict guard used only as a sanity check; in practice it is reached through
# a `hints.tsv` row, which bypasses detection. Blank lines separate records
# but add none of their own.

strategy_extract () {
    local text="$1"
    local line result="" entry=0
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "${line}" != *[![:space:]]* ]] && continue
        # Strip a leading bullet / comment marker.
        local s="${line#"${line%%[![:space:]]*}"}"
        s="${s#- }"; s="${s#\* }"
        [[ "${s}" != *[![:space:]]* ]] && continue
        # A line with no alphanumeric character is a separator / progress rule
        # (pyperf's `.....................`), not a key-bearing record — skip it.
        [[ "$s" == *[[:alnum:]]* ]] || continue
        # A `#`-led line is a comment (mamba/conda env listings open with
        # `# conda environments:`), not a record — skip it.
        [[ "$s" == \#* ]] && continue
        local key="${s%%[[:space:]]*}"
        local val="${s#"$key"}"
        # A trailing colon on the key is a delimiter, not part of the name
        # (`1337:`, `0:`, `connection.id:`) — the reviewer's repeated note on
        # the colon-delimited family is "remove from values". Drop one.
        key="${key%:}"
        # A bracket-indexed key is a register/array index — the reviewer's
        # modbus note "remove square brackets and colons" wants `[0]` → `0`.
        if [[ "$key" == \[*\] ]]; then key="${key#\[}"; key="${key%\]}"; fi
        val="${val#"${val%%[![:space:]]*}"}"
        val="${val%"${val##*[![:space:]]}"}"
        entry=$((entry + 1))
        result+="entry${entry}.key ${key}"$'\n'
        [[ -n "$val" ]] && result+="entry${entry}.value ${val}"$'\n'
    done
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
