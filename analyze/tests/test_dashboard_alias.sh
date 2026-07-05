#!/bin/bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"
DASHBOARD="$(cd "$SCRIPT_DIR/.." && pwd)/envoy-dashboard"
BROWSE="$(cd "$SCRIPT_DIR/.." && pwd)/envoy-browse"

test_dashboard_help () {
    local out
    out=$(bash "$DASHBOARD" --help 2>&1)
    assert_contains "$out" "envoy-browse --watch" "dashboard help should describe watch alias"
}

test_browse_help_describes_title () {
    local out
    out=$(bash "$BROWSE" --help 2>&1)
    assert_contains "$out" "--title TEXT" "browse help should describe dashboard title context"
}

run_test "envoy-dashboard help describes alias" test_dashboard_help
run_test "envoy-browse help describes title context" test_browse_help_describes_title
print_summary
