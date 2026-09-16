#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: unspaced-colon-kv
## Description: `Label:value` lines where the colon is a delimiter with no space after it (HammerDB TPC-C, Vuser logs) -> label/value rows
## Version: 1.0
## Priority: 52
## Sample: samples/unspaced-colon-kv/basic.txt

# The `colons` parser (priority 60) requires whitespace AFTER the colon, because
# that is what tells a `key: value` pair apart from a colon living inside a value
# (`10:15:42`). Some tools never print that space:
#
#   TEST RESULT : System achieved 482100 NOPM from 1204882 TPM
#   Vuser 1:RAMPUP complete
#   Vuser 1:Test complete, Taking end AWR snapshot.
#
# Those fall through to the blob parser and land in one column, which is exactly
# the "the colons are delimiters, not values" complaint. This strategy owns that
# form: split each line at its FIRST colon into `label` and `value`.
#
# Labels repeat (`Vuser 1` three times above), so the output is records — a real
# two-column table — not a flat key/value map that would collapse them.
#
# Kept off everything else by gates that all must hold. Each one is here because
# it was caught stealing a tool that a better parser already owned:
#   * every non-blank line splits into a plausible label + non-empty value;
#   * labels start with a letter (so `10:15:42` and `2024-01-01T00:00:00` are
#     out, their "label" starting with a digit) and stay short;
#   * no line carries a `d:dd` clock pair or `://`, so timestamps and URLs are
#     out even when a letter leads the line;
#   * no line is indented — YAML and nested config blocks are out;
#   * the first token never packs 3+ colons — passwd/group records stay with
#     colon-fields (priority 48, which runs first anyway);
#   * every line contains whitespace SOMEWHERE. A whitespace-free line is one
#     identifier that happens to hold a colon, not a pair — `redis-cli KEYS`
#     (`user:1001`), `rg --count` (`src/main.rs:12`), `jack_lsp`
#     (`system:capture_1`), image refs (`registry.k8s.io/pause:3.9`);
#   * no line contains a 2+ space run — that gap is column alignment, so
#     `lsblk` (`sda        8:0   500G`), `vcpkg list` and `haproxy show servers`
#     stay with the column parsers;
#   * no value starts with `digits:` — that is `file:LINE:text` grep output;
#   * no value starts with a colon — `::` is IPv6 (`prefix ::1/128`) or a Python
#     test path (`test_auth.py::test_login`), not a delimiter;
#   * a MAJORITY of lines have no space after the colon. One unspaced banner
#     over a spaced block is still a `colons` document — `nvme smart-log` prints
#     `Smart Log for NVME device:nvme0` above twenty `critical_warning : 0` rows;
#   * at least two DISTINCT labels. One label repeated on every line is a
#     namespace prefix, not a key — `vllm:num_requests_running 12`. This mirrors
#     the uniform-identifier guard colon-fields already carries.

# Split "$1" at its first colon -> _UCK_LABEL, _UCK_VALUE. Returns 1 if the line
# is not a usable label/value pair.
_uck_split () {
    local l="$1"
    [[ "$l" == *:* ]] || return 1
    # A pair always has whitespace somewhere; a bare `user:1001` identifier does not.
    [[ "$l" == *[[:space:]]* ]] || return 1
    # A 2+ space run ANYWHERE is column alignment: the colon belongs to an
    # identifier in column 1 and the real delimiter is the gap. Keeps `vcpkg
    # list` (`fmt:x64-linux    10.2.1  Formatting library`) and `haproxy show
    # servers` (`... 10.0.2.1:8080 UP  L7OK/200`) with the column parsers.
    [[ "$l" == *"  "* ]] && return 1
    local label="${l%%:*}" value="${l#*:}"
    # A second colon straight after the first is `::`, not a delimiter.
    [[ "$value" == :* ]] && return 1
    # `file:LINE:text` — grep/compiler diagnostics, owned by their own parsers.
    [[ "$value" =~ ^[0-9]+: ]] && return 1
    # rtrim label (`TEST RESULT :` -> `TEST RESULT`), trim value both ends
    label="${label%"${label##*[![:space:]]}"}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    [[ -n "$label" && -n "$value" ]] || return 1
    [[ ${#label} -le 40 ]] || return 1
    [[ "$label" == [A-Za-z]* ]] || return 1
    # Letters, digits, spaces and mild punctuation only — a label, not prose.
    [[ -z "${label//[A-Za-z0-9 ._#\/-]/}" ]] || return 1
    _UCK_LABEL="$label"; _UCK_VALUE="$value"
    return 0
}

# Colons in the first whitespace token of "$1" -> _UCK_N.
_uck_first_colons () {
    local tok="${1#"${1%%[![:space:]]*}"}"
    tok="${tok%%[[:space:]]*}"
    local nc="${tok//[^:]/}"
    _UCK_N=${#nc}
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    [[ "$text" == *'{'* || "$text" == *'":'* ]] && return 1

    local line nb=0 tight=0 labels=""
    # A clock is 1-2 digits, a colon, then EXACTLY two more digits — the trailing
    # `[^0-9]` matters: without it `Vuser 1:482100` reads as the time `1:48`.
    local _clock_re='(^|[^0-9:])[0-9][0-9]?:[0-9][0-9]([^0-9]|$)'
    while IFS= read -r line; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        # Indented -> YAML / nested config, not this.
        [[ "$line" == [[:space:]]* ]] && return 1
        [[ "$line" == *"://"* ]] && return 1
        [[ "$line" =~ $_clock_re ]] && return 1
        _uck_first_colons "$line"
        [[ $_UCK_N -ge 3 ]] && return 1
        _uck_split "$line" || return 1
        nb=$((nb + 1))
        # An unspaced colon is the whole point — `Label:value`, not `Label: value`.
        [[ "${line#*:}" == [[:space:]]* ]] || tight=$((tight + 1))
        case "$labels" in
            *"|${_UCK_LABEL}|"*) ;;
            *) labels+="|${_UCK_LABEL}|" ;;
        esac
    done <<< "$text"

    [[ $nb -ge 2 ]] || return 1
    # Majority unspaced, and more than one distinct label.
    [[ $(( tight * 100 / nb )) -ge 60 ]] || return 1
    local distinct="${labels//[^|]/}"
    [[ $(( ${#distinct} / 2 )) -ge 2 ]] || return 1
    _STRATEGY_CONFIDENCE=80
    return 0
}

strategy_extract () {
    local text="$1"
    local line result="" entry=0
    while IFS= read -r line; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        _uck_split "$line" || continue
        entry=$((entry + 1))
        result+="entry${entry}.label ${_UCK_LABEL}"$'\n'
        result+="entry${entry}.value ${_UCK_VALUE}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
