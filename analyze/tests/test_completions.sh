#!/bin/bash
# ENV-062: bash completions syntax + basic behaviour
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

COMPDIR="$(cd "$SCRIPT_DIR/.." && pwd)/completions"
ENVOY_ANALYZE_COMP="$COMPDIR/envoy-analyze.bash"
ENVOY_BROWSE_COMP="$COMPDIR/envoy-browse.bash"

test_envoy_analyze_syntax () {
    bash -n "$ENVOY_ANALYZE_COMP" || {
        echo "  ASSERT FAILED: envoy-analyze.bash fails syntax check"
        return 1
    }
}

test_envoy_browse_syntax () {
    bash -n "$ENVOY_BROWSE_COMP" || {
        echo "  ASSERT FAILED: envoy-browse.bash fails syntax check"
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
            envoy-analyze) _envoy_analyze_complete ;;
            envoy-browse)  _envoy_browse_complete ;;
        esac
        printf "%s\n" "${COMPREPLY[@]}"
    ' _comp "$script" "${words[@]}"
}

test_envoy_analyze_flag_completion () {
    local out
    out=$(_run_completion "$ENVOY_ANALYZE_COMP" envoy-analyze --)
    assert_contains "$out" "--format" "completion should include --format"
    assert_contains "$out" "--help" "completion should include --help"
    assert_contains "$out" "--head" "completion should include --head (ENV-063)"
    assert_contains "$out" "--color" "completion should include --color (ENV-065)"
    assert_contains "$out" "--benford-alpha" "completion should include --benford-alpha (ENV-067)"
}

test_envoy_analyze_format_values () {
    local out
    out=$(_run_completion "$ENVOY_ANALYZE_COMP" envoy-analyze --format "")
    assert_contains "$out" "plain" "--format should offer plain"
    assert_contains "$out" "json" "--format should offer json"
    assert_contains "$out" "html" "--format should offer html"
}

test_envoy_analyze_color_values () {
    local out
    out=$(_run_completion "$ENVOY_ANALYZE_COMP" envoy-analyze --color "")
    assert_contains "$out" "auto" "--color should offer auto"
    assert_contains "$out" "always" "--color should offer always"
    assert_contains "$out" "never" "--color should offer never"
}

test_envoy_browse_flag_completion () {
    local out
    out=$(_run_completion "$ENVOY_BROWSE_COMP" envoy-browse --)
    assert_contains "$out" "--all" "envoy-browse completion should include --all"
    assert_contains "$out" "--no-timeout" "envoy-browse completion should include --no-timeout"
}

run_test "ENV-062 envoy-analyze.bash passes bash -n" test_envoy_analyze_syntax
run_test "ENV-062 envoy-browse.bash passes bash -n" test_envoy_browse_syntax
run_test "ENV-062 envoy-analyze flag list includes new flags" test_envoy_analyze_flag_completion
run_test "ENV-062 --format offers enumerated values" test_envoy_analyze_format_values
run_test "ENV-062 --color offers enumerated values" test_envoy_analyze_color_values
run_test "ENV-062 envoy-browse flag list" test_envoy_browse_flag_completion

print_summary
