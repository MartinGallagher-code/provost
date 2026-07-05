#!/bin/bash
# ENV-065: ANSI colour in plain output with NO_COLOR and --color support
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

SAMPLE="$SAMPLES_DIR/trees.csv"

test_color_always_emits_escapes () {
    local out
    out=$(run_mda --color always --good "$SAMPLE")
    assert_contains "$out" $'\033[' "--color always should emit ANSI escapes"
}

test_color_never_strips_escapes () {
    local out
    out=$(run_mda --color never --good "$SAMPLE")
    if [[ "$out" == *$'\033['* ]]; then
        echo "  ASSERT FAILED: --color never must not emit ANSI escapes"
        return 1
    fi
}

test_no_color_env_wins () {
    # NO_COLOR overrides --color always
    local out
    out=$(NO_COLOR=1 run_mda --color always --good "$SAMPLE")
    if [[ "$out" == *$'\033['* ]]; then
        echo "  ASSERT FAILED: NO_COLOR must override --color always"
        return 1
    fi
}

test_color_auto_pipe_is_monochrome () {
    # When stdout is a pipe (not a TTY), auto resolves to no colour
    local out
    out=$(run_mda --color auto --good "$SAMPLE" | cat)
    if [[ "$out" == *$'\033['* ]]; then
        echo "  ASSERT FAILED: --color auto over pipe should be monochrome"
        return 1
    fi
}

test_json_never_has_ansi () {
    local out
    out=$(run_mda --color always --format json "$SAMPLE")
    if [[ "$out" == *$'\033['* ]]; then
        echo "  ASSERT FAILED: JSON output must never contain ANSI escapes"
        return 1
    fi
}

test_csv_never_has_ansi () {
    local out
    out=$(run_mda --color always --format csv "$SAMPLE")
    if [[ "$out" == *$'\033['* ]]; then
        echo "  ASSERT FAILED: CSV output must never contain ANSI escapes"
        return 1
    fi
}

test_color_invalid () {
    local out code=0
    out=$(run_mda --color sometimes "$SAMPLE" 2>&1) || code=$?
    [[ $code -ne 0 ]] || { echo "  ASSERT FAILED: invalid --color value must error"; return 1; }
    assert_contains "$out" "--color must be" "error message should list accepted values"
}

run_test "ENV-065 --color always emits ANSI" test_color_always_emits_escapes
run_test "ENV-065 --color never strips ANSI" test_color_never_strips_escapes
run_test "ENV-065 NO_COLOR overrides --color always" test_no_color_env_wins
run_test "ENV-065 auto over pipe is monochrome" test_color_auto_pipe_is_monochrome
run_test "ENV-065 JSON never has ANSI" test_json_never_has_ansi
run_test "ENV-065 CSV never has ANSI" test_csv_never_has_ansi
run_test "ENV-065 invalid --color value rejected" test_color_invalid

print_summary
