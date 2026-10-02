#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Tests for --field-pattern and --exclude-field flags
##
## Covers: regex pattern matching, exact name exclusion, combined usage,
##         edge cases (no matches, invalid regex, multiple excludes)
################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/tests/helpers.sh"

echo ""
echo "========================================"
echo "Field Filter Tests (--field-pattern, --exclude-field)"
echo "========================================"

# Sample JSON input used by most tests
SAMPLE_JSON='{"cpu_user": 42, "cpu_system": 10, "cpu_idle": 48, "hostname": "server1", "mem_total": 8192, "mem_free": 4096, "disk_total": 500, "uptime_seconds": 86400}'

################################################################################
## Test 1: --field-pattern '^cpu' matches cpu_user, cpu_system, cpu_idle
##

test_field_pattern_prefix () {
    local out
    out=$(echo "$SAMPLE_JSON" | run_extract --field-pattern '^cpu' -f json 2>/dev/null)
    assert_contains "$out" "cpu_user" "should contain cpu_user"
    assert_contains "$out" "cpu_system" "should contain cpu_system"
    assert_contains "$out" "cpu_idle" "should contain cpu_idle"
    assert_not_contains "$out" "hostname" "should not contain hostname"
    assert_not_contains "$out" "mem_total" "should not contain mem_total"
}

run_test "--field-pattern '^cpu' matches cpu_ fields" test_field_pattern_prefix

################################################################################
## Test 2: --field-pattern '.*_total$' matches fields ending in _total
##

test_field_pattern_suffix () {
    local out
    out=$(echo "$SAMPLE_JSON" | run_extract --field-pattern '_total$' -f json 2>/dev/null)
    assert_contains "$out" "mem_total" "should contain mem_total"
    assert_contains "$out" "disk_total" "should contain disk_total"
    assert_not_contains "$out" "cpu_user" "should not contain cpu_user"
    assert_not_contains "$out" "hostname" "should not contain hostname"
}

run_test "--field-pattern '_total\$' matches fields ending in _total" test_field_pattern_suffix

################################################################################
## Test 3: --exclude-field hostname removes exactly that field
##

test_exclude_field_single () {
    local out
    out=$(echo "$SAMPLE_JSON" | run_extract --exclude-field hostname -f json 2>/dev/null)
    assert_not_contains "$out" "hostname" "should not contain hostname"
    assert_contains "$out" "cpu_user" "should still contain cpu_user"
    assert_contains "$out" "mem_total" "should still contain mem_total"
}

run_test "--exclude-field hostname removes exactly hostname" test_exclude_field_single

################################################################################
## Test 4: Multiple --exclude-field flags
##

test_exclude_field_multiple () {
    local out
    out=$(echo "$SAMPLE_JSON" | run_extract --exclude-field hostname --exclude-field uptime_seconds -f json 2>/dev/null)
    assert_not_contains "$out" "hostname" "should not contain hostname"
    assert_not_contains "$out" "uptime_seconds" "should not contain uptime_seconds"
    assert_contains "$out" "cpu_user" "should still contain cpu_user"
    assert_contains "$out" "mem_total" "should still contain mem_total"
}

run_test "Multiple --exclude-field flags remove multiple fields" test_exclude_field_multiple

################################################################################
## Test 5: Combined --field-pattern + --exclude-field
##

test_combined_pattern_and_exclude () {
    local out
    out=$(echo "$SAMPLE_JSON" | run_extract --field-pattern '^cpu' --exclude-field cpu_idle -f json 2>/dev/null)
    assert_contains "$out" "cpu_user" "should contain cpu_user"
    assert_contains "$out" "cpu_system" "should contain cpu_system"
    assert_not_contains "$out" "cpu_idle" "should not contain cpu_idle (excluded)"
    assert_not_contains "$out" "hostname" "should not contain hostname (filtered by pattern)"
}

run_test "Combined --field-pattern + --exclude-field" test_combined_pattern_and_exclude

################################################################################
## Test 6: --field-pattern with no matches produces empty/no-fields output
##

test_field_pattern_no_matches () {
    local out
    out=$(echo "$SAMPLE_JSON" | run_extract --field-pattern '^nonexistent' -f json 2>/dev/null)
    # When no fields match, output should be empty JSON or no output
    assert_not_contains "$out" "cpu_user" "should not contain cpu_user"
    assert_not_contains "$out" "hostname" "should not contain hostname"
}

run_test "--field-pattern with no matches produces empty output" test_field_pattern_no_matches

################################################################################
## Test 7: Invalid regex produces error message
##

test_field_pattern_invalid_regex () {
    local out rc
    out=$(echo "$SAMPLE_JSON" | run_extract --field-pattern '[invalid' -f json 2>&1) || rc=$?
    assert_exit_nonzero "${rc:-1}" "should exit non-zero for invalid regex"
    assert_contains "$out" "Invalid regex" "should show invalid regex error"
}

run_test "--field-pattern with invalid regex shows error" test_field_pattern_invalid_regex

################################################################################
## Test 8: --exclude-field with nonexistent field name is a no-op
##

test_exclude_nonexistent_field () {
    local out_without out_with
    out_without=$(echo "$SAMPLE_JSON" | run_extract -f json 2>/dev/null)
    out_with=$(echo "$SAMPLE_JSON" | run_extract --exclude-field nonexistent_field -f json 2>/dev/null)
    assert_eq "$out_without" "$out_with" "excluding nonexistent field should not change output"
}

run_test "--exclude-field with nonexistent field is a no-op" test_exclude_nonexistent_field

################################################################################
## Test 9: --field-pattern with dot-star matches all fields
##

test_field_pattern_match_all () {
    local out_all out_pattern
    out_all=$(echo "$SAMPLE_JSON" | run_extract -f json 2>/dev/null)
    out_pattern=$(echo "$SAMPLE_JSON" | run_extract --field-pattern '.*' -f json 2>/dev/null)
    assert_eq "$out_all" "$out_pattern" "pattern '.*' should match all fields"
}

run_test "--field-pattern '.*' matches all fields" test_field_pattern_match_all

################################################################################
## Test 10: --field-pattern works with --names output mode
##

test_field_pattern_with_names () {
    local out
    out=$(echo "$SAMPLE_JSON" | run_extract --field-pattern '^mem' --names 2>/dev/null)
    assert_contains "$out" "mem_total" "should list mem_total"
    assert_contains "$out" "mem_free" "should list mem_free"
    assert_not_contains "$out" "cpu_user" "should not list cpu_user"
    assert_not_contains "$out" "hostname" "should not list hostname"
}

run_test "--field-pattern works with --names output mode" test_field_pattern_with_names

################################################################################
## Test 11: --exclude-field works with --count output mode
##

test_exclude_field_with_count () {
    local count_all count_excluded
    count_all=$(echo "$SAMPLE_JSON" | run_extract --count 2>/dev/null)
    count_excluded=$(echo "$SAMPLE_JSON" | run_extract --exclude-field hostname --count 2>/dev/null)
    # Excluding one field should reduce the count by 1
    local expected=$((count_all - 1))
    assert_eq "$expected" "$count_excluded" "count should be one less after excluding a field"
}

run_test "--exclude-field works with --count output mode" test_exclude_field_with_count

################################################################################
## Test 12: --field-pattern with case-sensitive matching
##

test_field_pattern_case_sensitive () {
    local out
    out=$(echo "$SAMPLE_JSON" | run_extract --field-pattern '^CPU' -f json 2>/dev/null)
    # Field names are lowercase (cpu_user, etc.), so ^CPU should not match
    assert_not_contains "$out" "cpu_user" "case-sensitive: ^CPU should not match cpu_user"
}

run_test "--field-pattern is case-sensitive" test_field_pattern_case_sensitive

################################################################################
## Summary
##

print_summary
exit $?
