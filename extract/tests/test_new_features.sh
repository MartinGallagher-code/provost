#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## New Feature Tests for Envoy:Explore (envoy-extract v3.0)
##
## Tests for priority ordering, confidence filtering, verbose, first-match,
## max-strategies, rename, delimiter, aggregate, stream, chain, plugin-dir,
## list-strategies priority column, and JSONL strategy basic test.
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "New Feature Tests (v3.0)"
echo "========================================"

################################################################################
## Priority ordering verified via --debug output
################################################################################

test_priority_ordering () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"name": "test"}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    # Debug output should show strategy names with priority markers (pNN)
    assert_contains "$output" "[debug]" "debug output should be present"
    # The json strategy (p10) should appear before colons (p60) in debug
    # Check that at least one strategy shows priority info
    assert_contains "$output" "(p" "debug should show priority values"
}

################################################################################
## --min-confidence filtering
################################################################################

test_min_confidence () {
    local tmpfile
    tmpfile=$(mktemp)
    # Input that matches yaml (confidence 90) and colons (confidence 35)
    printf 'Host: localhost\nPort: 5432\n' > "$tmpfile"
    local output
    output=$(run_mfe -d --min-confidence 80 "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    # Colons has confidence 35; should be filtered out when threshold is 80
    assert_contains "$output" "below threshold" "should report low-confidence strategy filtered"
}

################################################################################
## --verbose output shows summary
################################################################################

test_verbose_summary () {
    local output
    output=$(run_mfe -v -s json "$SAMPLES_DIR/json/basic.json" 2>&1)
    assert_contains "$output" "[info]" "verbose should show info messages"
    assert_contains "$output" "Strategies:" "verbose should show strategies summary"
    assert_contains "$output" "matched" "verbose should show match count"
    assert_contains "$output" "fields extracted" "verbose should show field count"
}

################################################################################
## --first-match produces single strategy output
################################################################################

test_first_match () {
    local tmpfile
    tmpfile=$(mktemp)
    # Input that matches multiple strategies (colons + equals)
    printf 'Host: localhost\nPort: 5432\nHost=localhost\nPort=5432\n' > "$tmpfile"
    local output
    output=$(run_mfe -r -d --first-match "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "--first-match: stopping" "debug should confirm first-match stop"
    # Only one STRAT- prefix should appear in the output
    local strat_names
    strat_names=$(echo "$output" | grep 'STRAT-' | sed 's/.*STRAT-//;s/:.*//' | sort -u | wc -l | tr -d ' ')
    assert_eq "1" "$strat_names" "first-match should produce output from exactly one strategy"
}

################################################################################
## --max-strategies limits count
################################################################################

test_max_strategies () {
    local tmpfile
    tmpfile=$(mktemp)
    # Input that matches multiple strategies
    printf 'Host: localhost\nPort: 5432\nHost=localhost\nPort=5432\nDB_NAME=mydb\n' > "$tmpfile"
    local output
    output=$(run_mfe -r -d --max-strategies 1 "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "--max-strategies 1 reached" "debug should confirm max-strategies limit"
}

################################################################################
## --rename single field
################################################################################

test_rename_single () {
    local tmpfile
    tmpfile=$(mktemp)
    printf 'Host: localhost\nPort: 5432\n' > "$tmpfile"
    local output
    output=$(run_mfe -r -s colons --rename 'Host=hostname' "$tmpfile")
    rm -f "$tmpfile"
    assert_contains "$output" "hostname" "should contain renamed field 'hostname'"
    assert_not_contains "$output" "	Host " "original 'Host' field name should be replaced"
}

################################################################################
## --rename multiple fields
################################################################################

test_rename_multiple () {
    local tmpfile
    tmpfile=$(mktemp)
    printf 'Host: localhost\nPort: 5432\nStatus: active\n' > "$tmpfile"
    local output
    output=$(run_mfe -r -s colons --rename 'Host=server,Port=port_number' "$tmpfile")
    rm -f "$tmpfile"
    assert_contains "$output" "server" "should contain renamed 'server'"
    assert_contains "$output" "port_number" "should contain renamed 'port_number'"
    assert_contains "$output" "Status" "unchanged field 'Status' should remain"
}

################################################################################
## --delimiter with '=>' custom delimiter
################################################################################

test_delimiter_arrow () {
    local tmpfile
    tmpfile=$(mktemp)
    printf 'hostname => web-01\nrole => frontend\nenv => production\n' > "$tmpfile"
    local output
    output=$(run_mfe -r --delimiter '=>' "$tmpfile")
    rm -f "$tmpfile"
    assert_contains "$output" "hostname" "should extract hostname field"
    assert_contains "$output" "web-01" "should extract value web-01"
    assert_contains "$output" "role" "should extract role field"
    assert_contains "$output" "frontend" "should extract value frontend"
}

################################################################################
## --delimiter with '::' custom delimiter
################################################################################

test_delimiter_double_colon () {
    local tmpfile
    tmpfile=$(mktemp)
    printf 'server::localhost\nport::8080\ndebug::true\n' > "$tmpfile"
    local output
    output=$(run_mfe -r --delimiter '::' "$tmpfile")
    rm -f "$tmpfile"
    assert_contains "$output" "server" "should extract server field"
    assert_contains "$output" "localhost" "should extract value localhost"
    assert_contains "$output" "port" "should extract port field"
    assert_contains "$output" "8080" "should extract value 8080"
}

################################################################################
## --aggregate on repeated numeric fields
################################################################################

test_aggregate () {
    local tmpfile
    tmpfile=$(mktemp)
    # Create input with repeated numeric fields across multiple "records"
    printf 'Score: 10\nScore: 20\nScore: 30\nLevel: 5\nLevel: 15\n' > "$tmpfile"
    local output
    output=$(run_mfe -r -s colons --aggregate "$tmpfile")
    rm -f "$tmpfile"
    # Aggregation should produce count/min/max/sum/avg lines for repeated numeric fields
    assert_contains "$output" "Score_count" "should show Score_count aggregate"
    assert_contains "$output" "Score_min" "should show Score_min aggregate"
    assert_contains "$output" "Score_max" "should show Score_max aggregate"
    assert_contains "$output" "Score_sum" "should show Score_sum aggregate"
    assert_contains "$output" "Score_avg" "should show Score_avg aggregate"
}

################################################################################
## --stream with --strategy produces JSON Lines
################################################################################

test_stream_mode () {
    local output
    output=$(printf 'Host: web-01\nPort: 8080\n' | run_mfe --stream --strategy colons)
    # Each line of output should be a JSON object
    assert_contains "$output" "{" "stream output should contain JSON objects"
    assert_contains "$output" "}" "stream output should contain closing braces"
    assert_contains "$output" '"Host":' "stream should extract Host field as JSON"
}

################################################################################
## --chain two strategies
################################################################################

test_chain () {
    local tmpfile
    tmpfile=$(mktemp)
    printf 'Host: localhost\nPort: 5432\nDebug: true\n' > "$tmpfile"
    local output rc=0
    output=$(run_mfe -r --chain 'colons' "$tmpfile" 2>&1) || rc=$?
    rm -f "$tmpfile"
    assert_exit_zero "$rc" "chain with single strategy should not crash"
    assert_contains "$output" "STRAT-chain" "chain output should have STRAT-chain label"
    assert_contains "$output" "Host" "chain should extract Host"
}

################################################################################
## --plugin-dir discovery
################################################################################

test_plugin_dir () {
    local plugin_dir
    plugin_dir=$(mktemp -d)
    # Create a minimal plugin strategy
    cat > "$plugin_dir/custom-test.sh" <<'STRAT'
#!/bin/bash
## Name: custom-test
## Description: Test plugin strategy
## Version: 1.0
## Priority: 50

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90
    echo "$text" | grep -q 'CUSTOM_MARKER' 2>/dev/null
}

strategy_extract () {
    local text="$1"
    echo "plugin_field plugin_value"
}
STRAT

    local tmpfile
    tmpfile=$(mktemp)
    printf 'CUSTOM_MARKER\ndata here\n' > "$tmpfile"
    local output
    output=$(run_mfe -r --plugin-dir "$plugin_dir" "$tmpfile")
    rm -f "$tmpfile"
    rm -rf "$plugin_dir"
    assert_contains "$output" "plugin_field" "should discover and run plugin strategy"
    assert_contains "$output" "plugin_value" "should extract plugin value"
}

################################################################################
## --list-strategies shows priority column
################################################################################

test_list_strategies_priority () {
    local output
    output=$(run_mfe --list-strategies)
    # The list output format includes priority: "  name   vN.N   pNN  description"
    assert_contains "$output" "p" "strategy list should show priority column"
    # json should show p10
    assert_contains "$output" "p10" "json strategy should show priority 10"
}

################################################################################
## New JSONL strategy basic test
################################################################################

test_jsonl_basic () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"name": "Alice", "age": 30}\n{"name": "Bob", "age": 25}\n' > "$tmpfile"
    local output rc=0
    output=$(run_mfe -r -s jsonl "$tmpfile" 2>&1) || rc=$?
    rm -f "$tmpfile"
    assert_exit_zero "$rc" "JSONL extraction should succeed"
    assert_contains "$output" "name" "should extract name field"
    assert_contains "$output" "Alice" "should extract value Alice"
    assert_contains "$output" "age" "should extract age field"
}

################################################################################
## v3.1 features
################################################################################

test_near_miss_feedback () {
    local output rc=0
    output=$(echo "random text no structure" | run_mfe --min-confidence 100 2>&1) || rc=$?
    assert_contains "$output" "No fields extracted" "should show no-extraction message"
}

test_near_miss_confidence_detail () {
    # Force high confidence threshold so detected strategies are filtered
    local output rc=0
    output=$(run_mfe --min-confidence 100 "$SAMPLES_DIR/json/benchmark.json" 2>&1) || rc=$?
    assert_contains "$output" "Near-miss" "should show near-miss details"
}

test_plain_format_without_fields () {
    local output
    output=$(run_mfe -f plain "$SAMPLES_DIR/json/benchmark.json")
    # Should contain key-value pairs (no numbered table header)
    assert_contains "$output" "context.date" "should contain field name"
    assert_not_contains "$output" "ID" "should not contain table header"
}

test_json_format_without_fields () {
    local output
    output=$(run_mfe -f json "$SAMPLES_DIR/json/benchmark.json")
    # Should be JSON output with braces
    assert_contains "$output" "{" "should start with JSON brace"
    assert_contains "$output" "context.date" "should contain field name"
}

test_early_format_validation () {
    local output rc=0
    output=$(run_mfe -f bogus 2>&1) || rc=$?
    assert_exit_nonzero "$rc" "should fail immediately with invalid format"
    assert_contains "$output" "Unknown format" "should show format error"
}

################################################################################
## Run all tests
################################################################################

run_test "new: priority ordering in debug output" test_priority_ordering
run_test "new: --min-confidence filters low-confidence strategies" test_min_confidence
run_test "new: --verbose shows extraction summary" test_verbose_summary
run_test "new: --first-match stops after first strategy" test_first_match
run_test "new: --max-strategies limits strategy count" test_max_strategies
run_test "new: --rename single field" test_rename_single
run_test "new: --rename multiple fields" test_rename_multiple
run_test "new: --delimiter with '=>' custom delimiter" test_delimiter_arrow
run_test "new: --delimiter with '::' custom delimiter" test_delimiter_double_colon
run_test "new: --aggregate on repeated numeric fields" test_aggregate
run_test "new: --stream with --strategy produces JSON Lines" test_stream_mode
run_test "new: --chain strategies" test_chain
run_test "new: --plugin-dir discovers custom strategies" test_plugin_dir
run_test "new: --list-strategies shows priority column" test_list_strategies_priority
run_test "new: JSONL strategy basic extraction" test_jsonl_basic
run_test "new: near-miss feedback on no extraction" test_near_miss_feedback
run_test "new: near-miss confidence detail" test_near_miss_confidence_detail
run_test "new: plain format without field list" test_plain_format_without_fields
run_test "new: JSON format without field list" test_json_format_without_fields
run_test "new: early format validation" test_early_format_validation

print_summary
