#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## provost_suggest.sh — shared "did you mean" / typo helpers
##
## Typo heuristic shared by provost's engines. Sourced by tools that need to disambiguate
## between "this is a typo'd flag / subcommand" and "this is a real file
## that happens to be missing" (ENV-137).
##
## Public functions:
##   _provost_arg_looks_like_typo(arg)      → exit 0 if `arg` is plausibly a
##                                           typo'd token (not a path, no
##                                           extension, ≤30 chars, doesn't
##                                           exist). Suite-wide heuristic.
##
## All functions are pure bash, no forks.
################################################################################

# Returns 0 if `arg` plausibly is a typo'd token (vs a missing real file).
# Heuristic: doesn't start with `-`, doesn't contain `/` or `.`, ≤30 chars,
# does not exist on disk. Tools call this from their file-not-found paths to
# decide whether to print a typo hint or a plain "File not found".
_provost_arg_looks_like_typo () {
    local arg="$1"
    [[ -z "$arg" ]] && return 1
    [[ "$arg" == -* ]] && return 1
    [[ "$arg" == */* ]] && return 1
    [[ "$arg" == *.* ]] && return 1
    [[ ${#arg} -le 30 ]] || return 1
    [[ -e "$arg" ]] && return 1
    return 0
}
