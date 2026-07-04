#!/bin/bash
################################################################################
## Core Engine Tests for Envoy:Explore (envoy-extract)
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Envoy:Explore Core Engine Tests"
echo "========================================"

################################################################################
## --help flag
################################################################################

test_help_flag () {
    local output
    output=$(run_mfe --help)
    assert_contains "$output" "Multi-Format Extractor" "help should show program name"
    assert_contains "$output" "--strategy" "help should list --strategy flag"
    assert_contains "$output" "--format" "help should list --format flag"
}

test_help_short_flag () {
    local output
    output=$(run_mfe -h)
    assert_contains "$output" "Usage:" "short help should show usage"
}

################################################################################
## --list-strategies flag
################################################################################

test_list_strategies () {
    local output
    output=$(run_mfe --list-strategies)
    assert_contains "$output" "colons" "should list colons strategy"
    assert_contains "$output" "json" "should list json strategy"
    assert_contains "$output" "vertical-line" "should list vertical-line strategy"
    assert_contains "$output" "csv" "should list csv strategy"
    assert_contains "$output" "http-headers" "should list http-headers strategy"
    assert_contains "$output" "warc-headers" "should list warc-headers strategy"
    assert_contains "$output" "aligned-columns" "should list aligned-columns strategy"
    assert_contains "$output" "equals" "should list equals strategy"
}

test_list_strategies_short () {
    local output
    output=$(run_mfe -l)
    assert_contains "$output" "Available strategies:" "short list should show header"
}

################################################################################
## Error handling
################################################################################

test_no_input_fails () {
    # When stdin is empty (not a terminal), mfe should fail
    local output rc=0
    output=$(echo -n "" | run_mfe 2>&1) || rc=$?
    assert_exit_nonzero "$rc" "should fail with no input"
    assert_contains "$output" "No data" "should show error message"
}

test_invalid_file_fails () {
    local output rc=0
    output=$(run_mfe /nonexistent/file.txt 2>&1) || rc=$?
    assert_exit_nonzero "$rc" "should fail with nonexistent file"
    assert_contains "$output" "File not found" "should show file not found error"
}

test_unknown_option_fails () {
    local output rc=0
    output=$(run_mfe --unknown-flag 2>&1) || rc=$?
    assert_exit_nonzero "$rc" "should fail with unknown flag"
    assert_contains "$output" "Unknown option" "should show unknown option error"
}

test_unknown_format_fails () {
    local output rc=0
    output=$(run_mfe -f bogus "$SAMPLES_DIR/json/basic.json" 1 2>&1) || rc=$?
    assert_exit_nonzero "$rc" "should fail with unknown format"
    assert_contains "$output" "Unknown format" "should show format error"
}

################################################################################
## stdin support
################################################################################

test_stdin_input () {
    local output
    output=$(echo '{"key": "value"}' | run_mfe -s json)
    assert_contains "$output" "key" "should extract from stdin"
    assert_contains "$output" "value" "should extract value from stdin"
}

################################################################################
## --strategy flag
################################################################################

test_strategy_filter () {
    local output
    output=$(run_mfe -r -s json "$SAMPLES_DIR/json/benchmark.json")
    assert_contains "$output" "STRAT-json" "should only show json strategy results"
    assert_not_contains "$output" "STRAT-colons" "should not show colons results"
}

################################################################################
## --raw flag
################################################################################

test_raw_output () {
    local output
    output=$(run_mfe -r -s json "$SAMPLES_DIR/json/basic.json")
    assert_contains "$output" "STRAT-json" "raw should include strategy labels"
    assert_not_contains "$output" "# ID" "raw should not include header"
}

################################################################################
## --debug flag
################################################################################

test_debug_output () {
    local output
    output=$(run_mfe -d -s json "$SAMPLES_DIR/json/basic.json" 2>&1)
    assert_contains "$output" "[debug]" "debug should show debug messages"
    assert_contains "$output" "detected as applicable" "debug should show detection"
}

################################################################################
## Field selection
################################################################################

test_field_selection () {
    local output
    output=$(run_mfe -s json "$SAMPLES_DIR/json/basic.json" 1,2)
    assert_contains "$output" "name" "should contain first field"
    assert_contains "$output" "version" "should contain second field"
    assert_not_contains "$output" "enabled" "should not contain unselected field"
}

################################################################################
## Output formats
################################################################################

test_json_format () {
    local output
    output=$(run_mfe -s json -f json "$SAMPLES_DIR/json/basic.json" 1,2)
    assert_contains "$output" '{"name":' "JSON should start with opening brace and first key"
    assert_contains "$output" '"version":' "JSON should contain second key"
}

test_csv_format () {
    local output
    output=$(run_mfe -s json -f csv "$SAMPLES_DIR/json/basic.json" 1,2)
    # Should have two lines: header and values
    local line_count
    line_count=$(echo "$output" | wc -l | tr -d ' ')
    assert_eq "2" "$line_count" "CSV should have 2 lines"
    assert_contains "$output" '"name"' "CSV header should contain field name"
}

test_tsv_format () {
    local output
    output=$(run_mfe -s json -f tsv "$SAMPLES_DIR/json/basic.json" 1,2)
    # TSV horizontal: header row + data row, tab-separated columns
    local line_count
    line_count=$(echo "$output" | wc -l | tr -d ' ')
    assert_eq "2" "$line_count" "TSV should have 2 lines (header + data)"
    # With 2 fields, each line should have 1 tab
    local header_tabs
    header_tabs=$(echo "$output" | head -1 | tr -cd '\t' | wc -c | tr -d ' ')
    assert_eq "1" "$header_tabs" "TSV header should have 1 tab for 2 columns"
}

test_plain_format () {
    local output
    output=$(run_mfe -s json -f plain "$SAMPLES_DIR/json/basic.json" 1)
    assert_contains "$output" "name" "plain should show field name"
    assert_not_contains "$output" "{" "plain should not have JSON braces"
}

################################################################################
## Empty/no-match handling
################################################################################

test_empty_file () {
    local tmpfile
    tmpfile=$(mktemp)
    local rc=0
    run_mfe "$tmpfile" >/dev/null 2>&1 || rc=$?
    rm -f "$tmpfile"
    # Should exit 0 (no output, no error)
    assert_exit_zero "$rc" "empty file should exit cleanly"
}

################################################################################
## Deduplication
################################################################################

test_dedup_across_strategies () {
    # This file has "Name: John" (colons) and "Name=John" (equals)
    # Both should detect, but dedup should keep only one Name/John pair
    local output
    output=$(run_mfe -r "$SAMPLES_DIR/edge-cases/dedup-overlap.txt")
    local name_count
    name_count=$(echo "$output" | grep -c 'Name John' || true)
    assert_eq "1" "$name_count" "Name John should appear only once after dedup"
    local age_count
    age_count=$(echo "$output" | grep -c 'Age 42' || true)
    assert_eq "1" "$age_count" "Age 42 should appear only once after dedup"
}

################################################################################
## -c flag (fully-qualified command line export)
################################################################################

test_cmdline_export () {
    local output
    output=$(run_mfe -c -s json "$SAMPLES_DIR/json/basic.json")
    assert_contains "$output" "--replay" "command line should contain --replay"
    assert_contains "$output" "json@" "command line should contain strategy name and version"
    assert_contains "$output" "basic.json" "command line should contain filename"
}

test_cmdline_export_with_fields () {
    local output
    output=$(run_mfe -c -s json "$SAMPLES_DIR/json/basic.json" 1,3)
    assert_contains "$output" "--replay" "should contain --replay"
    # ENV-182 routes the field-list arg through `printf '%q'` for shell
    # safety; bash %q escapes the bare comma to `\,` (defensive against
    # brace-expansion contexts), so the literal substring "1,3" is no
    # longer present even though the eval'd token is.  Strip backslashes
    # before checking for the field list.
    assert_contains "${output//\\/}" "1,3" "should contain field list"
}

################################################################################
## --replay flag
################################################################################

test_replay_basic () {
    # First extract with -c to get the command line
    local cmd_output
    cmd_output=$(run_mfe -c -s json "$SAMPLES_DIR/json/basic.json")
    # ENV-182 changed the cmdline format from `mfe --replay 'spec' file`
    # (single-quoted) to `mfe --replay spec file` (printf %q quoting only
    # when the value contains shell-special chars — `json@1.0` has none).
    # Pull out the second whitespace-separated token (the spec) directly.
    local spec
    spec=$(awk '{print $3}' <<<"$cmd_output")
    # Now replay
    local replay_output
    replay_output=$(run_mfe -r --replay "$spec" "$SAMPLES_DIR/json/basic.json")
    # Should produce json results
    assert_contains "$replay_output" "STRAT-json" "replay should run json strategy"
    assert_contains "$replay_output" "name" "replay should extract name field"
}

################################################################################
## Run all tests
################################################################################

run_test "help flag shows usage" test_help_flag
run_test "short help flag works" test_help_short_flag
run_test "list strategies shows all strategies" test_list_strategies
run_test "short list flag works" test_list_strategies_short
run_test "no input produces error" test_no_input_fails
run_test "invalid file produces error" test_invalid_file_fails
run_test "unknown option produces error" test_unknown_option_fails
run_test "unknown format produces error" test_unknown_format_fails
run_test "stdin input works" test_stdin_input
run_test "strategy filter works" test_strategy_filter
run_test "raw output works" test_raw_output
run_test "debug output works" test_debug_output
run_test "field selection works" test_field_selection
run_test "JSON format output" test_json_format
run_test "CSV format output" test_csv_format
run_test "TSV format output" test_tsv_format
run_test "plain format output" test_plain_format
run_test "empty file handled gracefully" test_empty_file
run_test "dedup across strategies" test_dedup_across_strategies
run_test "command line export" test_cmdline_export
run_test "command line export with fields" test_cmdline_export_with_fields
run_test "replay basic" test_replay_basic

print_summary
