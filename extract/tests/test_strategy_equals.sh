#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Strategy Tests: equals
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: equals"
echo "========================================"

test_equals_basic () {
    local output
    output=$(run_mfe -r -s equals "$SAMPLES_DIR/equals/basic.txt")
    assert_contains "$output" "USER" "should extract USER"
    assert_contains "$output" "jdoe" "should extract value jdoe"
    assert_contains "$output" "HOME" "should extract HOME"
    assert_contains "$output" "SHELL" "should extract SHELL"
}

test_equals_field_selection () {
    local output
    output=$(run_mfe -s equals "$SAMPLES_DIR/equals/basic.txt" 1,2)
    assert_contains "$output" "USER" "should contain USER"
    assert_contains "$output" "HOME" "should contain HOME"
}

test_equals_skips_comparisons () {
    local tmpfile
    tmpfile=$(mktemp)
    printf "NAME=test\nif x == y then\na += b\nx != y\n" > "$tmpfile"
    local output
    output=$(run_mfe -r -s equals "$tmpfile")
    rm -f "$tmpfile"
    assert_contains "$output" "NAME" "should extract NAME"
    assert_not_contains "$output" "==" "should skip comparisons"
    assert_not_contains "$output" "+=" "should skip augmented assignments"
}

test_equals_json_format () {
    local output
    output=$(run_mfe -s equals -f json "$SAMPLES_DIR/equals/basic.txt" 1,2)
    assert_contains "$output" '"USER":' "JSON should have USER key"
    assert_contains "$output" '"HOME":' "JSON should have HOME key"
}

# CONFIDENCE REFLECTS EVIDENCE: a block of KEY=VALUE lines (env, systemctl
# show, git config --list) must clear provost's default filing threshold (50);
# one stray `=` in prose must not.
_equals_conf () { # <file> -> confidence equals reports
    run_mfe -s equals --emit-meta -f tsv "$1" 2>&1 >/dev/null \
        | awk -F'\t' '/^__EXTRACT_META__/ { c = $3 } END { print c + 0 }'
}

test_equals_confidence_env_block () {
    local tmp conf
    tmp="$(mktemp)"
    printf 'HOME=/home/alice\nSHELL=/bin/bash\nLANG=en_US.UTF-8\nPATH=/usr/bin:/bin\nEDITOR=vim\nTERM=xterm-256color\n' > "$tmp"
    conf="$(_equals_conf "$tmp")"
    rm -f "$tmp"
    [[ "$conf" -ge 70 ]] || _assert_failed "env block confidence should be >=70 (got $conf)"
}

test_equals_confidence_git_config () {
    local tmp conf
    tmp="$(mktemp)"
    printf 'user.name=Alice Example\nuser.email=alice@example.com\ncore.editor=vim\npull.rebase=true\n' > "$tmp"
    conf="$(_equals_conf "$tmp")"
    rm -f "$tmp"
    [[ "$conf" -ge 70 ]] || _assert_failed "git config --list confidence should be >=70 (got $conf)"
}

test_equals_confidence_prose_stays_low () {
    local tmp conf
    tmp="$(mktemp)"
    printf 'The build finished in 3 minutes.\nSet VERBOSE=1 to see more output.\nNo errors were reported by the linker.\nSee the manual for details.\n' > "$tmp"
    conf="$(_equals_conf "$tmp")"
    rm -f "$tmp"
    [[ "$conf" -lt 50 ]] || _assert_failed "prose with one assignment must stay below 50 (got $conf)"
}

test_equals_value_spaces_kept () {
    local tmp output
    tmp="$(mktemp)"
    printf 'NAME=John Smith\nBUILT=Mon Jan 26 12:30:45 2024\n' > "$tmp"
    output=$(run_mfe -s equals -f plain "$tmp")
    rm -f "$tmp"
    assert_contains "$output" "NAME John Smith" "value keeps its space"
    assert_contains "$output" "BUILT Mon Jan 26 12:30:45 2024" "date value keeps spaces and colons"
}

run_test "equals: basic extraction" test_equals_basic
run_test "equals: field selection" test_equals_field_selection
run_test "equals: skips comparisons" test_equals_skips_comparisons
run_test "equals: JSON format output" test_equals_json_format

run_test "equals: KEY=VALUE block confidence >= 70" test_equals_confidence_env_block
run_test "equals: git config --list confidence >= 70" test_equals_confidence_git_config
run_test "equals: prose with a lone '=' stays below 50" test_equals_confidence_prose_stays_low
run_test "equals: values keep spaces" test_equals_value_spaces_kept
print_summary
