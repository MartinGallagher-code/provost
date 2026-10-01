#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: name-version-suffix
## Description: `name-VERSION` package tokens — split at the first `-` before a digit (rpm -qa, nix-env -q) -> name/version rows — hint-routed
## Version: 1.0
## Priority: 58
## Sample: samples/name-version-suffix/basic.txt

# Package listings print one `name-version` token per line, where the version
# begins at the first hyphen that is immediately followed by a digit:
#
#   glibc-2.34-60.el9.x86_64          (rpm -qa/-qf: NEVRA)
#   openssl-libs-3.0.7-16.el9.x86_64
#   bash-interactive-5.2p26           (nix-env -q)
#   git-2.44.0
#
# text-lines kept each as one opaque cell. The natural tidy form is name and
# version in their own columns:
#
#   name           version
#   glibc          2.34-60.el9.x86_64
#   openssl-libs   3.0.7-16.el9.x86_64
#   bash-interactive  5.2p26
#
# The split point is the first `-<digit>`: a package name may contain hyphens
# (`openssl-libs`, `util-linux-core`, `bash-interactive`) but the version
# always starts with a digit, so the FIRST `-` before a digit is the boundary.
# `name="${s%%-[0-9]*}"` removes the longest `-<digit>...` suffix, leaving the
# name; the remainder (minus the dash) is the version.
#
# HINT-ONLY: a `word-digit...` token is far too common to auto-detect (cargo
# trees, poetry, image tags all look like this), so this never auto-fires — it
# is reached exclusively through a hints.tsv row.

strategy_extract () {
    local text="$1"
    local line result="" entry=0
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "${line}" != *[![:space:]]* ]] && continue
        local s="${line#"${line%%[![:space:]]*}"}"
        s="${s%"${s##*[![:space:]]}"}"
        [[ -z "$s" ]] && continue
        # A package token is a single bare word: any internal whitespace means
        # this is a wider record (apk-list's `name ARCH {..} (..) [..]`, a dnf
        # `name : description`, a progress bar) — not a name-version list. Bail
        # so the hint falls through to normal auto-detection, preserving the
        # original parse. (Hints run the strategy before detection; an empty
        # result resumes auto-detect.)
        [[ "$s" == *[[:space:]]* ]] && return 0
        # Must have a `-<digit>` split point (a version follows the name).
        local name="${s%%-[0-9]*}"
        [[ "$name" == "$s" ]] && return 0
        local ver="${s#"$name"-}"
        entry=$((entry + 1))
        result+="entry${entry}.name ${name}"$'\n'
        [[ -n "$ver" ]] && result+="entry${entry}.version ${ver}"$'\n'
    done
    # A single token is a version banner (`jq-1.7.1`), not a list — leave those
    # to their own handling; only fire on an actual list of two or more.
    [[ $entry -ge 2 ]] || return 0
    result+="total_entries ${entry}"$'\n'
    echo "$result"
}

strategy_detect () {
    # HINT-ONLY (see header) — never auto-fires.
    _STRATEGY_CONFIDENCE=0
    return 1
}
