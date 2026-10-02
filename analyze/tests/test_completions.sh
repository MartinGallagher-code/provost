#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

# ENV-062: bash completions syntax + basic behaviour
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

COMPDIR="$(cd "$SCRIPT_DIR/.." && pwd)/completions"
PROVOST_ANALYZE_COMP="$COMPDIR/provost-analyze.bash"
PROVOST_BROWSE_COMP="$COMPDIR/provost-browse.bash"

test_provost_analyze_syntax () {
    bash -n "$PROVOST_ANALYZE_COMP" || {
        echo "  ASSERT FAILED: provost-analyze.bash fails syntax check"
        return 1
    }
}

test_provost_browse_syntax () {
    bash -n "$PROVOST_BROWSE_COMP" || {
        echo "  ASSERT FAILED: provost-browse.bash fails syntax check"
        return 1
    }
}

# Drive the completion function in a subshell and capture COMPREPLY.
_run_completion () {
    local script="$1"
    local -a words=( "${@:2}" )
    local cword=$(( ${#words[@]} - 1 ))
    bash -c '
        source "$1"
        shift
        COMP_WORDS=("$@")
        COMP_CWORD=$(( $# - 1 ))
        # Call the right handler based on the command name
        case "${COMP_WORDS[0]}" in
            provost-analyze) _provost_analyze_complete ;;
            provost-browse)  _provost_browse_complete ;;
        esac
        printf "%s\n" "${COMPREPLY[@]}"
    ' _comp "$script" "${words[@]}"
}

test_provost_analyze_flag_completion () {
    local out
    out=$(_run_completion "$PROVOST_ANALYZE_COMP" provost-analyze --)
    assert_contains "$out" "--format" "completion should include --format"
    assert_contains "$out" "--help" "completion should include --help"
    assert_contains "$out" "--head" "completion should include --head (ENV-063)"
    assert_contains "$out" "--color" "completion should include --color (ENV-065)"
    assert_contains "$out" "--benford-alpha" "completion should include --benford-alpha (ENV-067)"
}

test_provost_analyze_format_values () {
    local out
    out=$(_run_completion "$PROVOST_ANALYZE_COMP" provost-analyze --format "")
    assert_contains "$out" "plain" "--format should offer plain"
    assert_contains "$out" "json" "--format should offer json"
    assert_contains "$out" "html" "--format should offer html"
}

test_provost_analyze_color_values () {
    local out
    out=$(_run_completion "$PROVOST_ANALYZE_COMP" provost-analyze --color "")
    assert_contains "$out" "auto" "--color should offer auto"
    assert_contains "$out" "always" "--color should offer always"
    assert_contains "$out" "never" "--color should offer never"
}

test_provost_browse_flag_completion () {
    local out
    out=$(_run_completion "$PROVOST_BROWSE_COMP" provost-browse --)
    assert_contains "$out" "--all" "provost-browse completion should include --all"
    assert_contains "$out" "--no-timeout" "provost-browse completion should include --no-timeout"
}

run_test "ENV-062 provost-analyze.bash passes bash -n" test_provost_analyze_syntax
run_test "ENV-062 provost-browse.bash passes bash -n" test_provost_browse_syntax
run_test "ENV-062 provost-analyze flag list includes new flags" test_provost_analyze_flag_completion
run_test "ENV-062 --format offers enumerated values" test_provost_analyze_format_values
run_test "ENV-062 --color offers enumerated values" test_provost_analyze_color_values
run_test "ENV-062 provost-browse flag list" test_provost_browse_flag_completion

print_summary
