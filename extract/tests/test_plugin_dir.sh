#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Plugin Directory Tests for envoy-extract
##
## Tests that --plugin-dir correctly loads strategy plugins from a custom
## directory, including detection, extraction, listing, and edge cases.
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Plugin Directory Tests"
echo "========================================"

TMPDIR_P="${TMPDIR:-/tmp}/plugin_dir_tests_$$"
mkdir -p "$TMPDIR_P"

################################################################################
## Helper: create a minimal plugin strategy file
################################################################################

_create_plugin () {
    local dir="$1" name="$2" marker="$3" field_name="$4" field_value="$5"
    cat > "$dir/${name}.sh" <<STRAT
#!/bin/bash
## Name: ${name}
## Description: Test plugin strategy for ${name}
## Version: 1.0
## Priority: 50

strategy_detect () {
    local text="\$1"
    _STRATEGY_CONFIDENCE=90
    echo "\$text" | grep -q '${marker}' 2>/dev/null
}

strategy_extract () {
    local text="\$1"
    echo "${field_name} ${field_value}"
}
STRAT
}

################################################################################
## Plugin loaded and used for extraction
################################################################################

test_plugin_dir_basic_extraction () {
    local plugin_dir="$TMPDIR_P/basic"
    mkdir -p "$plugin_dir"
    _create_plugin "$plugin_dir" "my-plugin" "PLUGIN_BASIC" "plugin_key" "plugin_val"

    local tmpfile="$TMPDIR_P/basic_input.txt"
    printf 'PLUGIN_BASIC\nsome data\n' > "$tmpfile"
    local output
    output=$(run_mfe -r --plugin-dir "$plugin_dir" "$tmpfile")
    assert_contains "$output" "plugin_key" "should extract field from plugin strategy"
    assert_contains "$output" "plugin_val" "should extract value from plugin strategy"
}

################################################################################
## Plugin appears in --list-strategies output
################################################################################

test_plugin_dir_list_strategies () {
    local plugin_dir="$TMPDIR_P/list"
    mkdir -p "$plugin_dir"
    _create_plugin "$plugin_dir" "list-test-plugin" "LIST_MARKER" "f" "v"

    local output
    output=$(run_mfe --list-strategies --plugin-dir "$plugin_dir")
    assert_contains "$output" "list-test-plugin" "plugin should appear in strategy list"
}

################################################################################
## Plugin with high confidence overrides built-in strategies
################################################################################

test_plugin_dir_high_confidence () {
    local plugin_dir="$TMPDIR_P/highconf"
    mkdir -p "$plugin_dir"
    # Create a plugin that detects "Name:" patterns (same as colons) but with
    # high confidence (95) and a unique field name
    cat > "$plugin_dir/override-colons.sh" <<'STRAT'
#!/bin/bash
## Name: override-colons
## Description: Override colons with high confidence
## Version: 1.0
## Priority: 5

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=95
    echo "$text" | grep -q ':' 2>/dev/null
}

strategy_extract () {
    local text="$1"
    echo "override_field override_value"
}
STRAT

    local tmpfile="$TMPDIR_P/highconf_input.txt"
    printf 'Name: Alice\nAge: 30\n' > "$tmpfile"
    local output
    output=$(run_mfe -r --first-match --plugin-dir "$plugin_dir" "$tmpfile")
    # The plugin has higher confidence (95) and lower priority number (5),
    # so it should be preferred with --first-match
    assert_contains "$output" "override_field" "high-confidence plugin should win with --first-match"
}

################################################################################
## Plugin directory that does not exist (error handling)
################################################################################

test_plugin_dir_nonexistent () {
    local tmpfile="$TMPDIR_P/nodir_input.txt"
    printf 'Name: test\n' > "$tmpfile"
    local output rc=0
    output=$(run_mfe --plugin-dir "/tmp/nonexistent_plugin_dir_$$" "$tmpfile" 2>&1) || rc=$?
    # Should not crash; may warn about missing directory but still process
    if [[ $rc -le 1 ]]; then
        return 0
    else
        echo "  exit code was $rc (expected 0 or 1)"
        return 1
    fi
}

################################################################################
## Plugin directory with no .sh files (empty dir)
################################################################################

test_plugin_dir_empty () {
    local plugin_dir="$TMPDIR_P/empty_plugins"
    mkdir -p "$plugin_dir"
    local tmpfile="$TMPDIR_P/empty_plugins_input.txt"
    printf 'Name: test\n' > "$tmpfile"
    local output rc=0
    output=$(run_mfe -r --plugin-dir "$plugin_dir" -s colons "$tmpfile" 2>&1) || rc=$?
    # Should still work with built-in strategies
    assert_exit_zero "$rc" "empty plugin dir should not cause errors"
    assert_contains "$output" "Name" "should still extract using built-in strategies"
}

################################################################################
## Multiple plugins in same directory
################################################################################

test_plugin_dir_multiple_plugins () {
    local plugin_dir="$TMPDIR_P/multi"
    mkdir -p "$plugin_dir"
    _create_plugin "$plugin_dir" "plugin-alpha" "ALPHA_MARKER" "alpha_field" "alpha_value"
    _create_plugin "$plugin_dir" "plugin-beta" "BETA_MARKER" "beta_field" "beta_value"

    local tmpfile="$TMPDIR_P/multi_input.txt"
    printf 'ALPHA_MARKER\nALPHA_MARKER line\n' > "$tmpfile"
    local output
    output=$(run_mfe -r --plugin-dir "$plugin_dir" "$tmpfile")
    assert_contains "$output" "alpha_field" "should use alpha plugin when marker matches"

    printf 'BETA_MARKER\nBETA_MARKER line\n' > "$tmpfile"
    output=$(run_mfe -r --plugin-dir "$plugin_dir" "$tmpfile")
    assert_contains "$output" "beta_field" "should use beta plugin when marker matches"
}

################################################################################
## Plugin with --strategy explicit selection
################################################################################

test_plugin_dir_explicit_strategy () {
    local plugin_dir="$TMPDIR_P/explicit"
    mkdir -p "$plugin_dir"
    _create_plugin "$plugin_dir" "explicit-plugin" "EXPLICIT_MARKER" "explicit_field" "explicit_value"

    local tmpfile="$TMPDIR_P/explicit_input.txt"
    # Include the marker so detection succeeds when strategy is explicit
    printf 'EXPLICIT_MARKER\nsome data here\n' > "$tmpfile"
    local output rc=0
    output=$(run_mfe -r --plugin-dir "$plugin_dir" --strategy explicit-plugin "$tmpfile" 2>&1) || rc=$?
    assert_contains "$output" "explicit_field" "explicit --strategy should load plugin by name"
}

################################################################################
## Run all tests
################################################################################

run_test "plugin-dir: basic extraction from plugin" test_plugin_dir_basic_extraction
run_test "plugin-dir: plugin appears in list-strategies" test_plugin_dir_list_strategies
run_test "plugin-dir: high confidence plugin overrides built-in" test_plugin_dir_high_confidence
run_test "plugin-dir: nonexistent directory handled gracefully" test_plugin_dir_nonexistent
run_test "plugin-dir: empty directory still works" test_plugin_dir_empty
run_test "plugin-dir: multiple plugins in same directory" test_plugin_dir_multiple_plugins
run_test "plugin-dir: explicit strategy selection" test_plugin_dir_explicit_strategy

print_summary

# Cleanup
rm -rf "$TMPDIR_P"
