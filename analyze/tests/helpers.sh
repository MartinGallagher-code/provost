#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Test Helpers for provost-analyze (provost-analyze)
################################################################################

MDA_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/provost-analyze"
SAMPLES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/samples"

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
FAILED_NAMES=()

if [[ -t 1 ]]; then
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    YELLOW='\033[0;33m'
    NC='\033[0m'
else
    GREEN='' RED='' YELLOW='' NC=''
fi

assert_contains () {
    local haystack="$1"
    local needle="$2"
    local msg="${3:-output should contain string}"
    if [[ "$haystack" == *"$needle"* ]]; then
        return 0
    else
        echo -e "  ${RED}ASSERT FAILED${NC}: $msg"
        echo "    looking for: '$needle'"
        echo "    in:          '$haystack'"
        return 1
    fi
}

assert_not_contains () {
    local haystack="$1"
    local needle="$2"
    local msg="${3:-output should not contain string}"
    if [[ "$haystack" != *"$needle"* ]]; then
        return 0
    else
        echo -e "  ${RED}ASSERT FAILED${NC}: $msg"
        echo "    should not find: '$needle'"
        echo "    in:              '$haystack'"
        return 1
    fi
}

assert_exit_zero () {
    local code="$1"
    local msg="${2:-command should succeed (exit 0)}"
    if [[ "$code" -eq 0 ]]; then
        return 0
    else
        echo -e "  ${RED}ASSERT FAILED${NC}: $msg"
        echo "    exit code: $code"
        return 1
    fi
}

run_mda () {
    bash "$MDA_SCRIPT" "$@"
}

run_test () {
    local description="$1"
    local func="$2"
    TESTS_RUN=$((TESTS_RUN + 1))

    # Capture the test subshell's exit code without triggering the
    # caller's `set -e`. Half of provost-analyze's test files top with
    # `set -euo pipefail`; a bare `( ... ); result=$?` would let
    # `set -e` fire on a failing subshell BEFORE `result=$?` runs,
    # aborting the entire run. Putting the subshell in an
    # `|| result=$?` list suppresses `set -e` for that step and
    # captures the real exit status. The default `result=0` covers
    # the success branch (where `||` short-circuits).
    local result=0
    ( set -e; "$func" ) || result=$?

    if [[ $result -eq 0 ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}PASS${NC}: $description"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        FAILED_NAMES+=("$description")
        echo -e "  ${RED}FAIL${NC}: $description (exit $result)"
    fi
}

print_summary () {
    echo ""
    echo "========================================"
    echo "Results: $TESTS_PASSED/$TESTS_RUN passed, $TESTS_FAILED failed"
    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo -e "${RED}Failed tests:${NC}"
        for name in "${FAILED_NAMES[@]}"; do
            echo "  - $name"
        done
        echo "========================================"
        return 1
    else
        echo -e "${GREEN}All tests passed.${NC}"
        echo "========================================"
        return 0
    fi
}
