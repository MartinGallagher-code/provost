#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo "========================================"
echo "provost-analyze --list-items menu (ENV-191)"
echo "========================================"

export PROVOST_ANALYZE_SUPPRESS_AWK_WARNING=1
SAMPLE="$SAMPLES_DIR/anscombe.csv"

test_list_items_shows_menu () {
    local out
    out=$(run_mda --list-items "$SAMPLE" 2>/dev/null)
    assert_contains "$out" "ID" "menu has a header"
    assert_contains "$out" "KIND" "menu lists the kind column"
    assert_contains "$out" "TITLE" "menu lists the title column"
    assert_contains "$out" "Dataset overview" "menu includes the overview item"
}

test_list_items_marks_suggested () {
    local out
    out=$(run_mda --list-items "$SAMPLE" 2>/dev/null)
    # The overview item is always suggested → row 1 carries the '*' marker.
    assert_contains "$out" "*" "suggested items are marked"
}

test_list_items_lists_kinds () {
    local out
    out=$(run_mda --list-items "$SAMPLE" 2>/dev/null)
    assert_contains "$out" "summary" "summary analyses are listed"
    assert_contains "$out" "col_types" "column-type analysis is listed"
}

test_list_items_in_help () {
    local out
    out=$(run_mda --help 2>/dev/null)
    assert_contains "$out" "--list-items" "help documents --list-items"
}

run_test "list-items prints the analysis menu" test_list_items_shows_menu
run_test "list-items marks suggested items"    test_list_items_marks_suggested
run_test "list-items includes analysis kinds"  test_list_items_lists_kinds
run_test "list-items documented in --help"     test_list_items_in_help

print_summary
