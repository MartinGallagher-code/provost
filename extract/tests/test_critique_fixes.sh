#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Tests for CRITIQUE.md fixes
##
## Covers: clean_text cache, source error guard, escape functions,
##         ini detection, apply_renames safety, aggregate ordering,
##         validation enhancements
################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/tests/helpers.sh"

echo ""
echo "========================================"
echo "Critique Fix Tests"
echo "========================================"

################################################################################
## Fix #1: clean_text() cache works (no subshell)
##

test_clean_text_cache_works () {
    # Source the modules to get clean_text
    source "$SCRIPT_DIR/lib/_log.sh"
    source "$SCRIPT_DIR/lib/_helpers.sh"
    _CLEAN_TEXT_CACHE=""
    _CLEAN_TEXT_DONE=0

    local input="Host: server1
Date: Mon 01 12:30:45 2024"

    # First call should compute and cache
    clean_text "$input"
    local result1="$_CLEAN_TEXT_RESULT"
    assert_eq "1" "$_CLEAN_TEXT_DONE" "cache flag should be set after first call"

    # Second call should use cache (verify _CLEAN_TEXT_DONE is still 1)
    clean_text "$input"
    local result2="$_CLEAN_TEXT_RESULT"
    assert_eq "$result1" "$result2" "cached result should match first result"
}

run_test "clean_text cache flag persists (no subshell loss)" test_clean_text_cache_works

################################################################################
## Fix #2: _json_escape uses global return
##

test_json_escape_global_return () {
    source "$SCRIPT_DIR/lib/_helpers.sh"
    source "$SCRIPT_DIR/lib/_format.sh"

    _json_escape 'hello "world"'
    assert_eq 'hello \"world\"' "$_ESCAPED" "json escape should handle double quotes"

    _json_escape 'back\slash'
    assert_eq 'back\\slash' "$_ESCAPED" "json escape should handle backslashes"
}

run_test "json_escape returns via _ESCAPED global" test_json_escape_global_return

################################################################################
## Fix #2: _xml_escape uses global return
##

test_xml_escape_global_return () {
    source "$SCRIPT_DIR/lib/_helpers.sh"
    source "$SCRIPT_DIR/lib/_format.sh"

    _xml_escape 'a & b < c'
    assert_eq 'a &amp; b &lt; c' "$_ESCAPED" "xml escape should handle & and <"
}

run_test "xml_escape returns via _ESCAPED global" test_xml_escape_global_return

################################################################################
## Fix #5: source error guard -- broken strategy doesn't crash mfe
##

test_source_error_guard () {
    local tmpdir
    tmpdir=$(mktemp -d)
    local strat_dir="$tmpdir/strategies"
    mkdir -p "$strat_dir"

    # Create a valid strategy
    cat > "$strat_dir/good.sh" << 'STRAT'
#!/bin/bash
## Name: good
## Description: A valid strategy
## Version: 1.0
## Priority: 50
strategy_detect () { _STRATEGY_CONFIDENCE=90; return 0; }
strategy_extract () { echo "key value"; }
STRAT

    # Create a broken strategy (syntax error)
    cat > "$strat_dir/broken.sh" << 'STRAT'
#!/bin/bash
## Name: broken
## Description: A broken strategy
## Version: 1.0
## Priority: 10
strategy_detect () {
    this is not valid bash syntax }{}{
}
STRAT

    # Run mfe with the plugin dir -- should not crash
    local output rc=0
    output=$(echo "key: value" | bash "$MFE_SCRIPT" --plugin-dir "$strat_dir" -f plain 2>/dev/null) || rc=$?
    # Should succeed (good strategy or built-in strategies should still work)
    # The broken strategy should be skipped, not crash the engine

    rm -rf "$tmpdir"

    # mfe should not have crashed (exit code 0 if fields extracted)
    assert_eq "0" "$rc" "mfe should not crash on broken strategy file"
}

run_test "source error guard: broken strategy skipped, not crashed" test_source_error_guard

################################################################################
## Fix #4: chain version uses real metadata
##

test_chain_version_real () {
    # Use -c to export the command line with version info
    local output
    output=$(echo '{"name": "test"}' | bash "$MFE_SCRIPT" --chain 'json' -c 2>/dev/null) || true
    # The replay spec should contain json@ followed by the actual version from json.sh
    # json.sh has ## Version: 1.0
    assert_contains "$output" "json@1.0" "chain version should be real metadata version"
}

run_test "chain version uses real strategy metadata" test_chain_version_real

################################################################################
## Fix #12: ini.sh detection -- brackets on different lines shouldn't match
##

test_ini_false_positive_brackets () {
    local input="[error log entry
some other text that has
a closing bracket ] somewhere"
    local output rc=0
    output=$(echo "$input" | bash "$MFE_SCRIPT" -s ini -f plain 2>/dev/null) || rc=$?
    # This should NOT match as INI (brackets are on different lines, not a section header)
    assert_output_empty "$output" "brackets on different lines should not match as INI"
}

run_test "ini: brackets on different lines rejected" test_ini_false_positive_brackets

################################################################################
## Fix #11: apply_renames -- only renames field name, not values
##

test_apply_renames_field_only () {
    source "$SCRIPT_DIR/lib/_helpers.sh"
    source "$SCRIPT_DIR/lib/_postprocess.sh"

    # Create output where a field value contains text that looks like another field name
    local input="STRAT-test:1	host server.host.example.com
STRAT-test:2	port 8080"

    local result
    result=$(apply_renames "$input" "host=hostname")

    # "host" field should be renamed to "hostname"
    assert_contains "$result" "hostname server.host.example.com" "field name should be renamed"
    # The value should NOT have "host" replaced within it
    assert_contains "$result" "server.host.example.com" "field value should not be modified"
}

run_test "apply_renames: only renames field name portion" test_apply_renames_field_only

################################################################################
## Fix #13: aggregate_output deterministic ordering
##

test_aggregate_deterministic_order () {
    source "$SCRIPT_DIR/lib/_helpers.sh"
    source "$SCRIPT_DIR/lib/_postprocess.sh"

    local input="STRAT-test:1	alpha 10
STRAT-test:2	beta 20
STRAT-test:3	alpha 30
STRAT-test:4	beta 40"

    # Run multiple times -- output order should be stable
    local result1 result2
    result1=$(aggregate_output "$input")
    result2=$(aggregate_output "$input")
    assert_eq "$result1" "$result2" "aggregate output should be deterministic"

    # alpha should appear before beta (insertion order)
    local first_field="${result1%%$'\n'*}"
    assert_contains "$first_field" "alpha" "first aggregated field should be alpha (insertion order)"
}

run_test "aggregate_output: deterministic insertion-order output" test_aggregate_deterministic_order

################################################################################
## Fix #15: validation checks syntax
##

test_validation_syntax_check () {
    local tmpfile
    tmpfile=$(mktemp /tmp/test_strat_XXXXXX.sh)

    # Create a strategy with a real syntax error (unclosed quote)
    cat > "$tmpfile" << 'STRAT'
#!/bin/bash
## Name: test_strat
## Description: Test
## Version: 1.0
## Priority: 50
strategy_detect () {
    local x="unclosed
}
strategy_extract () { echo "x y"; }
STRAT

    local output
    output=$(bash "$MFE_SCRIPT" --validate-strategy "$tmpfile" 2>/dev/null) || true
    rm -f "$tmpfile"

    assert_contains "$output" "FAIL" "validation should catch syntax errors"
    assert_contains "$output" "Syntax" "should report syntax error"
}

run_test "validation: catches syntax errors via bash -n" test_validation_syntax_check

################################################################################
## Fix #15: validation checks _STRATEGY_CONFIDENCE
##

test_validation_confidence_warning () {
    local tmpfile
    tmpfile=$(mktemp /tmp/test_strat_XXXXXX.sh)

    # Create a strategy that doesn't set confidence
    cat > "$tmpfile" << 'STRAT'
#!/bin/bash
## Name: test_strat
## Description: Test
## Version: 1.0
## Priority: 50
strategy_detect () { return 0; }
strategy_extract () { echo "x y"; }
STRAT

    local output
    output=$(bash "$MFE_SCRIPT" --validate-strategy "$tmpfile" 2>/dev/null) || true
    rm -f "$tmpfile"

    assert_contains "$output" "WARN" "should warn about missing confidence"
    assert_contains "$output" "_STRATEGY_CONFIDENCE" "should mention confidence variable"
}

run_test "validation: warns about missing _STRATEGY_CONFIDENCE" test_validation_confidence_warning

################################################################################
## Fix #8: assert_json_valid uses jq when available
##

test_assert_json_valid_rejects_bad_json () {
    # Only meaningful if jq is installed
    if ! command -v jq >/dev/null 2>&1; then
        return 0  # skip gracefully
    fi

    # Valid JSON should pass
    assert_json_valid '{"key": "value"}'

    # Invalid JSON should fail. Wrapped so this deliberate failure is not
    # recorded as a failure OF THIS TEST -- see expect_assert_failure.
    local rc=0
    expect_assert_failure assert_json_valid '{garbage}' || rc=$?
    assert_eq "1" "$rc" "invalid JSON should fail with jq validation"
}

run_test "assert_json_valid: rejects invalid JSON when jq available" test_assert_json_valid_rejects_bad_json

print_summary
