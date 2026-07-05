#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
source "$SCRIPT_DIR/helpers.sh"

MDX_SCRIPT="$(cd "$SCRIPT_DIR/.." && pwd)/envoy-browse"

########################################
## Help overlay tests (envoy-browse)
########################################

test_help_overlay_state_variable_exists () {
    # Verify help_overlay variable is initialized to 0
    (
        MDX_TESTING=1 source "$MDX_SCRIPT"
        if [[ "$help_overlay" -ne 0 ]]; then
            echo "  ASSERT FAILED: help_overlay should be initialized to 0, got '$help_overlay'"
            exit 1
        fi
    )
}

test_render_help_overlay_function_exists () {
    # Verify render_help_overlay function is defined
    (
        MDX_TESTING=1 source "$MDX_SCRIPT"
        if ! declare -f render_help_overlay > /dev/null 2>&1; then
            echo "  ASSERT FAILED: render_help_overlay function should be defined"
            exit 1
        fi
    )
}

test_help_key_documented_in_usage () {
    local output
    output=$(bash "$MDX_SCRIPT" --help 2>&1)
    assert_contains "$output" "?" "help should document ? key"
    assert_contains "$output" "shortcut" "help should mention keyboard shortcut"
}

test_help_overlay_footer_shows_help_key () {
    # The footer in render should include ?:help
    (
        MDX_TESTING=1 source "$MDX_SCRIPT"
        # Verify by checking render function source indirectly -- we check the
        # footer keys string includes ?:help
        local src
        src=$(declare -f render)
        if [[ "$src" != *"?:help"* ]]; then
            echo "  ASSERT FAILED: render footer should include '?:help'"
            exit 1
        fi
    )
}

test_help_overlay_contains_all_keys () {
    # Verify the help_keys array in render_help_overlay contains all expected keys
    (
        MDX_TESTING=1 source "$MDX_SCRIPT"
        local src
        src=$(declare -f render_help_overlay)
        for key in "Up / k" "Down / j" "Tab" "Home" "End" "PgUp" "PgDn" "?" "q" "/" "n / N" "Esc" "a" "g" "G"; do
            if [[ "$src" != *"$key"* ]]; then
                echo "  ASSERT FAILED: render_help_overlay should list key '$key'"
                exit 1
            fi
        done
    )
}

########################################
## Run all help overlay tests
########################################

run_test "help_overlay state variable initialized to 0" test_help_overlay_state_variable_exists
run_test "render_help_overlay function exists" test_render_help_overlay_function_exists
run_test "? key documented in --help usage" test_help_key_documented_in_usage
run_test "Footer includes ?:help shortcut hint" test_help_overlay_footer_shows_help_key
run_test "Help overlay lists all keyboard shortcuts" test_help_overlay_contains_all_keys

print_summary
