#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Tests for v3.4 features: YAML/XML formats, auto-tune, interactive
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "v3.4 Feature Tests"
echo "========================================"

################################################################################
## YAML output format
################################################################################

test_yaml_format_basic () {
    local output
    output=$(run_extract -f yaml -s json "$SAMPLES_DIR/json/basic.json")
    assert_contains "$output" ": " "YAML output should contain key: value pairs"
    assert_not_contains "$output" "{" "YAML output should not contain JSON braces"
}

test_yaml_special_char_quoting () {
    # Create temp file with colons in values
    local tmpfile
    tmpfile=$(mktemp)
    echo 'time: 12:30:00' > "$tmpfile"
    echo 'note: hello' >> "$tmpfile"
    local output
    output=$(run_extract -f yaml -s colons "$tmpfile")
    # The value "12:30:00" contains colons, so it should be quoted
    assert_contains "$output" '"' "YAML should quote values with colons"
    rm -f "$tmpfile"
}

test_yaml_keyword_quoting () {
    # Create temp file where values are YAML keywords
    local tmpfile
    tmpfile=$(mktemp)
    echo 'enabled: true' > "$tmpfile"
    echo 'active: false' >> "$tmpfile"
    local output
    output=$(run_extract -f yaml -s colons "$tmpfile")
    # "true" and "false" are YAML keywords and should be quoted
    assert_contains "$output" '"true"' "YAML should quote boolean keywords"
    rm -f "$tmpfile"
}

test_yaml_format_with_field_selection () {
    local output
    output=$(run_extract -f yaml -s json "$SAMPLES_DIR/json/basic.json" 1)
    # Should output exactly one YAML key: value line
    local line_count
    line_count=$(echo "$output" | sed '/^$/d' | wc -l | tr -d ' ')
    assert_eq "1" "$line_count" "field selection should return single line"
    assert_contains "$output" ": " "should be YAML format"
}

################################################################################
## XML output format
################################################################################

test_xml_format_basic () {
    local output
    output=$(run_extract -f xml -s json "$SAMPLES_DIR/json/basic.json")
    assert_contains "$output" '<?xml version="1.0"' "should have XML declaration"
    assert_contains "$output" '<fields>' "should have root element"
    assert_contains "$output" '</fields>' "should have closing root element"
    assert_contains "$output" '<field name=' "should have field elements"
}

test_xml_escaping () {
    # Create temp file with values that need XML escaping
    local tmpfile
    tmpfile=$(mktemp)
    echo 'formula: 1<2 & 3>0' > "$tmpfile"
    local output
    output=$(run_extract -f xml -s colons "$tmpfile")
    assert_contains "$output" '&lt;' "should escape < in XML"
    assert_contains "$output" '&amp;' "should escape & in XML"
    assert_contains "$output" '&gt;' "should escape > in XML"
    rm -f "$tmpfile"
}

test_xml_format_with_field_selection () {
    local output
    output=$(run_extract -f xml -s json "$SAMPLES_DIR/json/basic.json" 1)
    assert_contains "$output" '<fields>' "should have root element"
    # Count field elements — should be exactly 1
    local field_count
    field_count=$(echo "$output" | grep -c '<field name=' || true)
    assert_eq "1" "$field_count" "field selection should return single field"
}

################################################################################
## Auto-tune
################################################################################

test_auto_tune_confidence_fallback () {
    # With --min-confidence 100 nothing should match normally,
    # but --auto-tune should fall back to a lower threshold
    local output
    output=$(run_extract --auto-tune --min-confidence 100 -s json "$SAMPLES_DIR/json/basic.json" 2>&1)
    assert_not_contains "$output" "No fields extracted" "auto-tune should find fields at lower confidence"
}

test_auto_tune_best_match_verbose () {
    # With multiple strategies matching, --auto-tune -v should suggest the best one
    local output
    output=$(run_extract --auto-tune -v "$SAMPLES_DIR/json/basic.json" 2>&1)
    # json.sh should match at minimum; if multiple match, should see auto-tune ranking
    # At a minimum, the verbose output should appear
    assert_contains "$output" "[info]" "verbose should produce info output"
}

test_auto_tune_conflict_first_match () {
    local output rc=0
    output=$(run_extract --auto-tune --first-match "$SAMPLES_DIR/json/basic.json" 2>&1) || rc=$?
    assert_exit_nonzero "$rc" "should fail with conflicting flags"
    assert_contains "$output" "cannot be used together" "should show conflict error"
}

test_auto_tune_single_strategy_noop () {
    # --auto-tune with --strategy should work without error
    local output rc=0
    output=$(run_extract --auto-tune --strategy json "$SAMPLES_DIR/json/basic.json" 2>&1) || rc=$?
    assert_exit_zero "$rc" "should succeed with single strategy"
}

test_auto_tune_no_effect_without_min_conf () {
    # --auto-tune without --min-confidence should produce normal output
    local output rc=0
    output=$(run_extract --auto-tune -s json "$SAMPLES_DIR/json/basic.json" 2>&1) || rc=$?
    assert_exit_zero "$rc" "should succeed"
    assert_not_contains "$output" "No fields extracted" "should produce output"
}

################################################################################
## Interactive mode
################################################################################

test_interactive_flag_accepted () {
    # --interactive should be accepted as a valid flag
    # In non-TTY context (subshell), it should fall back gracefully
    local output rc=0
    output=$(run_extract --interactive -s json "$SAMPLES_DIR/json/basic.json" 2>&1) || rc=$?
    # Should not fail with "unknown option"
    assert_not_contains "$output" "Unknown option" "should accept --interactive flag"
}

test_interactive_conflict_quiet () {
    local output rc=0
    output=$(run_extract --interactive --quiet "$SAMPLES_DIR/json/basic.json" 2>&1) || rc=$?
    assert_exit_nonzero "$rc" "should fail with conflicting flags"
    assert_contains "$output" "cannot be used together" "should show conflict error"
}

test_interactive_conflict_stream () {
    local output rc=0
    output=$(run_extract --interactive --stream --strategy json 2>&1) || rc=$?
    assert_exit_nonzero "$rc" "should fail with conflicting flags"
    assert_contains "$output" "cannot be used together" "should show conflict error"
}

################################################################################
## Run all tests
################################################################################

run_test "YAML format basic output" test_yaml_format_basic
run_test "YAML special character quoting" test_yaml_special_char_quoting
run_test "YAML keyword quoting" test_yaml_keyword_quoting
run_test "YAML format with field selection" test_yaml_format_with_field_selection
run_test "XML format basic output" test_xml_format_basic
run_test "XML escaping" test_xml_escaping
run_test "XML format with field selection" test_xml_format_with_field_selection
run_test "Auto-tune confidence fallback" test_auto_tune_confidence_fallback
run_test "Auto-tune best match verbose" test_auto_tune_best_match_verbose
run_test "Auto-tune conflict with first-match" test_auto_tune_conflict_first_match
run_test "Auto-tune with single strategy" test_auto_tune_single_strategy_noop
run_test "Auto-tune without min-confidence" test_auto_tune_no_effect_without_min_conf
run_test "Interactive flag accepted" test_interactive_flag_accepted
run_test "Interactive conflict with quiet" test_interactive_conflict_quiet
run_test "Interactive conflict with stream" test_interactive_conflict_stream

print_summary
