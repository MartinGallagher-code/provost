#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## envoy_version.sh — suite-wide version helpers
##
## The top-level VERSION file is the only current-source for the Envoy suite
## version.  Public CLIs source this helper and call envoy_suite_version rather
## than embedding release numbers in each script.
################################################################################

# Print the canonical suite version from VERSION.
# Args: optional starting directory used when ENVOY_HOME is not set.
# shellcheck disable=SC2120
envoy_suite_version () {
    local start="${1:-}"
    local dir=""
    local candidate=""

    if [[ -n "${ENVOY_HOME:-}" && -r "${ENVOY_HOME}/VERSION" ]]; then
        head -n1 "${ENVOY_HOME}/VERSION" | tr -d '[:space:]'
        return 0
    fi

    if [[ -z "$start" ]]; then
        start="${BASH_SOURCE[1]:-${PWD}}"
    fi
    if [[ -f "$start" ]]; then
        dir="$(cd -P "$(dirname "$start")" 2>/dev/null && pwd)"
    else
        dir="$(cd -P "$start" 2>/dev/null && pwd)"
    fi

    while [[ -n "$dir" && "$dir" != "/" ]]; do
        candidate="$dir/VERSION"
        if [[ -r "$candidate" ]]; then
            head -n1 "$candidate" | tr -d '[:space:]'
            return 0
        fi
        dir="$(dirname "$dir")"
    done

    if [[ -r "/VERSION" ]]; then
        head -n1 "/VERSION" | tr -d '[:space:]'
        return 0
    fi

    printf '%s\n' "0.0.0+unknown"
}

envoy_version_banner () {
    local name="$1"
    local version="${2:-$(envoy_suite_version)}"
    printf '%s %s — Developed by SageCor Solutions, Annapolis Junction, MD\n' "$name" "$version"
}
