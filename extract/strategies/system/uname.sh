#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: uname
## Description: Extract the canonical fields from a `uname -a` line
## Version: 1.0
## Priority: 20
## Sample: samples/uname/basic.txt

# `uname -a` prints ONE line in a fixed field order:
#
#   Linux vm 6.18.5-fc-v20 #1 SMP PREEMPT_DYNAMIC @0 x86_64 x86_64 x86_64 GNU/Linux
#   kernel  |  release     |<------ version (free text) ------>| m     p      i    os
#         node
#
# The version segment runs from the `#<buildno>` token to the last four fields
# (machine, processor, hardware-platform — often repeats — and the OS name).
# Without this the line shredded into eleven A..K columns with no names, which
# is the benchmark's definition of a FAIL: a headerless table where the input
# actually HAS a schema, just not a printed one.
#
# Any other lines in the capture (a bare `uname -r` / `-m` echoed alongside)
# are kept as line<N> so nothing is dropped.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    local line
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "${line}" != *[![:space:]]* ]] && continue
        # First non-blank line: OS name, node, release, then a `#buildno`.
        if [[ "$line" =~ ^(Linux|Darwin|FreeBSD|OpenBSD|NetBSD|SunOS|AIX)[[:space:]]+[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+\# ]]; then
            _STRATEGY_CONFIDENCE=87
            return 0
        fi
        return 1
    done
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" line done_main=0 extra=0
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "${line}" != *[![:space:]]* ]] && continue
        if [[ $done_main -eq 0 && "$line" =~ ^(Linux|Darwin|FreeBSD|OpenBSD|NetBSD|SunOS|AIX)[[:space:]] ]]; then
            done_main=1
            local toks=()
            { _fr_tok "$line"; toks=("${_FR_TOK[@]}"); }
            local n=${#toks[@]}
            result+="kernel_name ${toks[0]}"$'\n'
            [[ $n -ge 2 ]] && result+="nodename ${toks[1]}"$'\n'
            [[ $n -ge 3 ]] && result+="kernel_release ${toks[2]}"$'\n'
            # The machine / processor / hardware-platform fields are only
            # printed when known — GNU uname omits an `unknown` processor and
            # platform (Debian: `… Debian 6.1.76-1 x86_64 GNU/Linux`), so the
            # tail is 2-4 tokens, not always 4. Count the architecture-shaped
            # tokens in front of the OS name instead of assuming four.
            local _arch_re='^(x86_64|amd64|i[3-6]86|athlon|aarch64|arm64|armv[0-9][0-9a-z]*|ppc64(le)?|ppc|s390x?|riscv(32|64)|mips[0-9a-z]*|sparc(64)?|loongarch64|ia64|alpha|unknown)$'
            local _na=0 _k
            for ((_k = n - 2; _k >= 4 && _na < 3; _k--)); do
                [[ "${toks[$_k]}" =~ $_arch_re ]] || break
                _na=$((_na + 1))
            done
            if [[ $n -ge 6 && $_na -ge 1 ]]; then
                # version = tokens 3 .. before the arch tail (free text); then
                # machine[, processor[, hardware_platform]], operating_system.
                local ver="" i _first=$((n - 1 - _na))
                for ((i = 3; i < _first; i++)); do ver+="${ver:+ }${toks[$i]}"; done
                [[ -n "$ver" ]] && result+="kernel_version ${ver}"$'\n'
                local -a _an=(machine processor hardware_platform)
                for ((i = 0; i < _na; i++)); do
                    result+="${_an[$i]} ${toks[$((_first + i))]}"$'\n'
                done
                result+="operating_system ${toks[$((n - 1))]}"$'\n'
            elif [[ $n -ge 8 ]]; then
                # version = tokens 3 .. n-5 (free text); then machine,
                # processor, hardware_platform, operating_system.
                local ver="" i
                for ((i = 3; i <= n - 5; i++)); do ver+="${ver:+ }${toks[$i]}"; done
                [[ -n "$ver" ]] && result+="kernel_version ${ver}"$'\n'
                result+="machine ${toks[$((n - 4))]}"$'\n'
                result+="processor ${toks[$((n - 3))]}"$'\n'
                result+="hardware_platform ${toks[$((n - 2))]}"$'\n'
                result+="operating_system ${toks[$((n - 1))]}"$'\n'
            elif [[ $n -ge 4 ]]; then
                # Short forms (`uname -snrm`): keep the rest as version text.
                local rest="" i
                for ((i = 3; i < n; i++)); do rest+="${rest:+ }${toks[$i]}"; done
                [[ -n "$rest" ]] && result+="kernel_version ${rest}"$'\n'
            fi
        else
            extra=$((extra + 1))
            local trimmed="${line#"${line%%[![:space:]]*}"}"
            trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
            result+="line${extra} ${trimmed}"$'\n'
        fi
    done
    echo "$result"
}
