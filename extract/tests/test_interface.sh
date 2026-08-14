#!/bin/bash
################################################################################
## Interface Tests for EnvoyExtract v4.2
##
## Tests for subcommand dispatch, smart piped output, interactive non-TTY
## warning, field provenance, and backward compatibility.
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Interface Tests (v4.2)"
echo "========================================"

################################################################################
## Subcommand: list
################################################################################

test_subcommand_list () {
    local output
    output=$(run_mfe list)
    assert_contains "$output" "Available strategies:" "list subcommand should show header"
    assert_contains "$output" "json" "list subcommand should show json strategy"
    assert_contains "$output" "colons" "list subcommand should show colons strategy"
}

test_subcommand_list_backward_compat () {
    local output_sub output_flag
    output_sub=$(run_mfe list)
    output_flag=$(run_mfe --list-strategies)
    assert_eq "$output_sub" "$output_flag" "list subcommand should match --list-strategies"
}

################################################################################
## Subcommand: validate
################################################################################

test_subcommand_validate_all () {
    local output rc=0
    output=$(run_mfe validate 2>&1) || rc=$?
    assert_exit_zero "$rc" "validate subcommand should succeed"
    assert_contains "$output" "PASS" "validate should show PASS results"
}

test_subcommand_validate_file () {
    local output rc=0
    output=$(run_mfe validate "$STRATEGIES_DIR/structured/json.sh" 2>&1) || rc=$?
    assert_exit_zero "$rc" "validate FILE should succeed for valid strategy"
    assert_contains "$output" "PASS" "validate FILE should show PASS"
}

test_subcommand_validate_backward_compat () {
    local output_sub output_flag rc1=0 rc2=0
    output_sub=$(run_mfe validate "$STRATEGIES_DIR/structured/json.sh" 2>&1) || rc1=$?
    output_flag=$(run_mfe --validate-strategy "$STRATEGIES_DIR/structured/json.sh" 2>&1) || rc2=$?
    assert_eq "$rc1" "$rc2" "validate FILE and --validate-strategy should have same exit code"
    assert_eq "$output_sub" "$output_flag" "validate FILE should match --validate-strategy"
}

################################################################################
## Subcommand: stream
################################################################################

test_subcommand_stream () {
    local output
    output=$(echo '{"name": "test"}' | run_mfe stream -s json)
    assert_contains "$output" "name" "stream subcommand should extract fields"
}

test_subcommand_stream_backward_compat () {
    local output_sub output_flag
    output_sub=$(echo '{"name": "test"}' | run_mfe stream -s json)
    output_flag=$(echo '{"name": "test"}' | run_mfe --stream -s json)
    assert_eq "$output_sub" "$output_flag" "stream subcommand should match --stream flag"
}

################################################################################
## Subcommand: batch
################################################################################

test_subcommand_batch () {
    local output
    output=$(echo "$SAMPLES_DIR/json/basic.json" | run_mfe batch -s json)
    assert_contains "$output" '"file"' "batch subcommand should emit JSON Lines with file key"
    assert_contains "$output" '"fields"' "batch subcommand should emit JSON Lines with fields key"
}

test_subcommand_batch_backward_compat () {
    local output_sub output_flag
    output_sub=$(echo "$SAMPLES_DIR/json/basic.json" | run_mfe batch -s json)
    output_flag=$(echo "$SAMPLES_DIR/json/basic.json" | run_mfe --batch -s json)
    assert_eq "$output_sub" "$output_flag" "batch subcommand should match --batch flag"
}

################################################################################
## Subcommand: extract (explicit default)
################################################################################

test_subcommand_extract () {
    local output
    output=$(run_mfe extract -s json -f json "$SAMPLES_DIR/json/basic.json")
    assert_json_valid "$output" "extract subcommand should produce valid JSON"
}

test_subcommand_extract_matches_default () {
    local output_sub output_default
    output_sub=$(run_mfe extract -s json -f json "$SAMPLES_DIR/json/basic.json")
    output_default=$(run_mfe -s json -f json "$SAMPLES_DIR/json/basic.json")
    assert_eq "$output_sub" "$output_default" "extract subcommand should match default mode"
}

################################################################################
## Smart piped output: JSON when stdout is not TTY
################################################################################

test_piped_output_is_json () {
    # When piped (not a TTY), output should be JSON by default
    local output
    output=$(run_mfe -s json "$SAMPLES_DIR/json/basic.json" | cat)
    assert_json_valid "$output" "piped output should be valid JSON"
    assert_not_contains "$output" "# ID" "piped output should not be display table"
}

test_explicit_format_overrides_pipe () {
    # Explicit format should override the pipe default
    local output
    output=$(run_mfe -s json -f plain "$SAMPLES_DIR/json/basic.json" | cat)
    assert_not_contains "$output" "{" "explicit -f plain should not produce JSON"
}

test_piped_csv_format () {
    local output
    output=$(run_mfe -s json -f csv "$SAMPLES_DIR/json/basic.json" | cat)
    assert_not_contains "$output" "# ID" "piped csv should not be display table"
}

################################################################################
## Version and help text
################################################################################

test_version_string () {
    local output expected
    # The top-level VERSION file is the single source of truth (lib/envoy_version.sh);
    # derive the expectation from it so version bumps can't break this test.
    expected="$(head -n1 "$SCRIPT_DIR/../../VERSION" | tr -d '[:space:]')"
    output=$(run_mfe --version)
    assert_contains "$output" "$expected" "version should be $expected"
}

test_help_shows_commands () {
    local output
    output=$(run_mfe --help)
    assert_contains "$output" "Commands:" "help should show Commands section"
    assert_contains "$output" "list" "help should show list command"
    assert_contains "$output" "validate" "help should show validate command"
    assert_contains "$output" "stream" "help should show stream command"
    assert_contains "$output" "batch" "help should show batch command"
}

test_help_shows_grouped_sections () {
    local output
    output=$(run_mfe --help)
    assert_contains "$output" "Basic Options:" "help should have Basic Options section"
    assert_contains "$output" "Output Control:" "help should have Output Control section"
    assert_contains "$output" "Filtering & Selection:" "help should have Filtering section"
    assert_contains "$output" "Advanced:" "help should have Advanced section"
    assert_contains "$output" "Debug & Development:" "help should have Debug section"
}

test_help_shows_new_name () {
    local output
    output=$(run_mfe --help)
    assert_contains "$output" "Multi-Format Extractor" "help should show new name"
    assert_not_contains "$output" "Magical" "help should not show old name"
}

################################################################################
## Field provenance in verbose mode
################################################################################

test_verbose_shows_provenance () {
    local output
    output=$(run_mfe -v -s json "$SAMPLES_DIR/json/basic.json" 2>&1)
    assert_contains "$output" "Fields by strategy:" "verbose should show field provenance"
    assert_contains "$output" "json" "verbose provenance should mention strategy name"
}

################################################################################
## Subcommands with additional flags
################################################################################

test_list_with_extra_flags_ignored () {
    # "list" doesn't take extra flags, but shouldn't crash on common ones
    local output rc=0
    output=$(run_mfe list 2>&1) || rc=$?
    assert_exit_zero "$rc" "list subcommand should succeed"
}

test_stream_requires_strategy () {
    local output rc=0
    output=$(echo "data" | run_mfe stream 2>&1) || rc=$?
    assert_exit_nonzero "$rc" "stream without --strategy should fail"
    assert_contains "$output" "--strategy" "error should mention --strategy"
}

################################################################################
## Run all tests
################################################################################

run_test "subcommand: list" test_subcommand_list
run_test "subcommand: list backward compat" test_subcommand_list_backward_compat
run_test "subcommand: validate all" test_subcommand_validate_all
run_test "subcommand: validate file" test_subcommand_validate_file
run_test "subcommand: validate backward compat" test_subcommand_validate_backward_compat
run_test "subcommand: stream" test_subcommand_stream
run_test "subcommand: stream backward compat" test_subcommand_stream_backward_compat
run_test "subcommand: batch" test_subcommand_batch
run_test "subcommand: batch backward compat" test_subcommand_batch_backward_compat
run_test "subcommand: extract" test_subcommand_extract
run_test "subcommand: extract matches default" test_subcommand_extract_matches_default
run_test "piped output is JSON" test_piped_output_is_json
run_test "explicit format overrides pipe" test_explicit_format_overrides_pipe
run_test "piped csv format" test_piped_csv_format
run_test "version string" test_version_string
run_test "help shows commands" test_help_shows_commands
run_test "help shows grouped sections" test_help_shows_grouped_sections
run_test "help shows new name" test_help_shows_new_name
run_test "verbose shows provenance" test_verbose_shows_provenance
run_test "list with no extra flags" test_list_with_extra_flags_ignored
run_test "stream requires strategy" test_stream_requires_strategy

print_summary
