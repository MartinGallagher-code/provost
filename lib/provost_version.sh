#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## provost_version.sh — suite-wide version helpers
##
## The top-level VERSION file is the single source of truth for provost's
## version.  The engines source this helper and call provost_suite_version rather
## than embedding release numbers in each script.
################################################################################

# Print provost's version from its top-level VERSION file.
#
# The file is resolved RELATIVE TO THE SCRIPT, never by searching arbitrary
# parents: the engines live one level below the tool root (extract/, analyze/),
# and the same holds in the wheel, where the tree sits under
# provost_data/_bundle with VERSION at its root. Order:
#   1. <start>/VERSION, <start>/../VERSION        (the script's tool root)
#   2. $PROVOST_HOME/VERSION, $PROVOST_ROOT/VERSION (explicit overrides)
#   3. "0.0.0+unknown"                              (a partial checkout)
# Args: optional starting directory (or file) — normally the calling script's
# own directory; defaults to the caller's source file.
# shellcheck disable=SC2120
provost_suite_version () {
    local start="${1:-}"
    local dir="" candidate="" root

    if [[ -z "$start" ]]; then
        start="${BASH_SOURCE[1]:-${PWD}}"
    fi
    if [[ -f "$start" ]]; then
        dir="$(cd -P "$(dirname "$start")" 2>/dev/null && pwd)"
    else
        dir="$(cd -P "$start" 2>/dev/null && pwd)"
    fi

    for candidate in ${dir:+"$dir/VERSION" "$(dirname "$dir")/VERSION"} \
                     ${PROVOST_HOME:+"$PROVOST_HOME/VERSION"} \
                     ${PROVOST_ROOT:+"$PROVOST_ROOT/VERSION"}; do
        if [[ -r "$candidate" ]]; then
            root="$(head -n1 "$candidate" | tr -d '[:space:]')"
            if [[ -n "$root" ]]; then
                printf '%s\n' "$root"
                return 0
            fi
        fi
    done

    printf '%s\n' "0.0.0+unknown"
}

# Print the --version banner for one of provost's engines.
provost_version_banner () {
    local name="$1"
    local version="${2:-$(provost_suite_version)}"
    printf '%s (provost) %s\n' "$name" "$version"
    printf 'Copyright (C) 2026 Martin J. Gallagher\n'
    printf 'License: GPL-3.0-or-later <https://www.gnu.org/licenses/gpl-3.0.html>\n'
}
