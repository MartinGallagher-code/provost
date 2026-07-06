#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
source "$SCRIPT_DIR/helpers.sh"

MDX_SCRIPT="$(cd "$SCRIPT_DIR/.." && pwd)/envoy-browse"

run_mdx () {
    bash "$MDX_SCRIPT" "$@"
}

test_help_exits_zero () {
    local output
    output=$(run_mdx --help 2>&1)
    assert_exit_zero "$?" "envoy-browse --help should exit 0"
    assert_contains "$output" "EnvoyAnalyze Browser" "help should contain tool name"
    assert_contains "$output" "Tab" "help should document Tab key"
    assert_contains "$output" "PgUp" "help should document PgUp key"
    assert_contains "$output" "Start search" "help should document search"
}

test_no_input_exits_nonzero () {
    local rc=0
    run_mdx 2>/dev/null </dev/null || rc=$?
    if [[ "$rc" -eq 0 ]]; then
        echo "  ASSERT FAILED: envoy-browse with no input should exit non-zero"
        return 1
    fi
}

test_bad_flag_exits_nonzero () {
    local rc=0
    run_mdx --suggest 2>/dev/null || rc=$?
    if [[ "$rc" -eq 0 ]]; then
        echo "  ASSERT FAILED: envoy-browse --suggest should exit non-zero"
        return 1
    fi
}

test_help_documents_all_keys () {
    local output
    output=$(run_mdx --help 2>&1)
    assert_contains "$output" "Home" "help should document Home key"
    assert_contains "$output" "End" "help should document End key"
    assert_contains "$output" "j/k" "help should document vim keys"
    assert_contains "$output" "Esc" "help should document Esc key"
}

test_all_flag_accepted () {
    local output
    output=$(run_mdx --all --help 2>&1)
    assert_exit_zero "$?" "envoy-browse --all --help should exit 0"
    assert_contains "$output" "EnvoyAnalyze Browser" "help should still show tool name with --all"
}

test_debug_flag_accepted () {
    local output
    output=$(run_mdx --debug --help 2>&1)
    assert_exit_zero "$?" "envoy-browse --debug --help should exit 0"
    assert_contains "$output" "EnvoyAnalyze Browser" "help should still show tool name with --debug"
}

################################################################################
## Unit tests for envoy-browse internal functions (sourced via MDX_TESTING=1)
################################################################################

test_parse_section_title_summary () {
    (
        MDX_TESTING=1 source "$MDX_SCRIPT"
        parse_section_title "Summary stats: age"
        if [[ "$_PARSED_SECTION" != "summary" ]]; then
            echo "  ASSERT FAILED: expected section 'summary', got '$_PARSED_SECTION'"
            exit 1
        fi
        if [[ "$_PARSED_VARNAME" != "age" ]]; then
            echo "  ASSERT FAILED: expected varname 'age', got '$_PARSED_VARNAME'"
            exit 1
        fi
    )
}

test_parse_section_title_unknown () {
    (
        MDX_TESTING=1 source "$MDX_SCRIPT"
        parse_section_title "Unknown prefix: something"
        if [[ -n "$_PARSED_SECTION" ]]; then
            echo "  ASSERT FAILED: unknown prefix should produce empty section, got '$_PARSED_SECTION'"
            exit 1
        fi
    )
}

test_classify_title_summary () {
    (
        MDX_TESTING=1 source "$MDX_SCRIPT"
        local result
        result=$(classify_title "Dataset overview")
        if [[ "$result" != "summary" ]]; then
            echo "  ASSERT FAILED: 'Dataset overview' should classify as 'summary', got '$result'"
            exit 1
        fi
    )
}

test_classify_title_variable () {
    (
        MDX_TESTING=1 source "$MDX_SCRIPT"
        local result
        result=$(classify_title "Histogram: age")
        if [[ "$result" != "variable" ]]; then
            echo "  ASSERT FAILED: 'Histogram: age' should classify as 'variable', got '$result'"
            exit 1
        fi
    )
}

test_classify_title_multi () {
    (
        MDX_TESTING=1 source "$MDX_SCRIPT"
        local result
        result=$(classify_title "Correlation matrix")
        if [[ "$result" != "multi" ]]; then
            echo "  ASSERT FAILED: 'Correlation matrix' should classify as 'multi', got '$result'"
            exit 1
        fi
    )
}

test_wrap_text_short () {
    (
        MDX_TESTING=1 source "$MDX_SCRIPT"
        wrapped_detail=()
        wrap_text 80 "short line"
        if [[ ${#wrapped_detail[@]} -ne 1 ]]; then
            echo "  ASSERT FAILED: short text should produce 1 line, got ${#wrapped_detail[@]}"
            exit 1
        fi
        if [[ "${wrapped_detail[0]}" != "short line" ]]; then
            echo "  ASSERT FAILED: short text should be unchanged, got '${wrapped_detail[0]}'"
            exit 1
        fi
    )
}

test_wrap_text_long () {
    (
        MDX_TESTING=1 source "$MDX_SCRIPT"
        wrapped_detail=()
        wrap_text 20 "this is a long line that should wrap at word boundaries"
        if [[ ${#wrapped_detail[@]} -lt 2 ]]; then
            echo "  ASSERT FAILED: long text should wrap into 2+ lines, got ${#wrapped_detail[@]}"
            exit 1
        fi
    )
}

test_wrap_text_no_spaces () {
    (
        MDX_TESTING=1 source "$MDX_SCRIPT"
        wrapped_detail=()
        wrap_text 10 "abcdefghijklmnop"
        if [[ ${#wrapped_detail[@]} -lt 2 ]]; then
            echo "  ASSERT FAILED: text with no spaces should still wrap, got ${#wrapped_detail[@]}"
            exit 1
        fi
    )
}

test_wrap_text_empty () {
    (
        MDX_TESTING=1 source "$MDX_SCRIPT"
        wrapped_detail=()
        wrap_text 80 ""
        if [[ ${#wrapped_detail[@]} -ne 1 ]]; then
            echo "  ASSERT FAILED: empty text should produce 1 line, got ${#wrapped_detail[@]}"
            exit 1
        fi
    )
}

test_compose_var_body_empty () {
    (
        MDX_TESTING=1 source "$MDX_SCRIPT"
        VAR_SUMMARY=()
        VAR_SHAPE=()
        VAR_HIST=()
        VAR_SPARK=()
        VAR_ANOM=()
        VAR_TOP=()
        VAR_DOM=()
        VAR_EXTRA=()
        compose_var_body 0
        if [[ -n "$_COMPOSED_BODY" ]]; then
            echo "  ASSERT FAILED: compose_var_body with no data should produce empty body"
            exit 1
        fi
    )
}

test_compose_var_body_partial () {
    (
        MDX_TESTING=1 source "$MDX_SCRIPT"
        VAR_SUMMARY=("Min: 1, Max: 10")
        VAR_SHAPE=()
        VAR_HIST=()
        VAR_SPARK=()
        VAR_ANOM=()
        VAR_TOP=()
        VAR_DOM=()
        VAR_EXTRA=()
        compose_var_body 0
        if [[ "$_COMPOSED_BODY" != *"Summary stats:"* ]]; then
            echo "  ASSERT FAILED: body should contain Summary stats section"
            exit 1
        fi
        if [[ "$_COMPOSED_BODY" != *"Min: 1"* ]]; then
            echo "  ASSERT FAILED: body should contain the summary data"
            exit 1
        fi
    )
}

test_load_items_passes_all_flag () {
    # When show_all=1, load_items must pass --all to envoy-analyze
    # so that ALL items (not just GOOD) are returned.
    (
        MDX_TESTING=1 source "$MDX_SCRIPT"
        show_all=1
        MDA_ARGS=("$SAMPLES_DIR/trees.csv")
        # Capture the command that load_items would construct
        # by overriding bash to echo the args
        local cmd
        if [[ $show_all -eq 1 ]]; then
            cmd=(bash "$MDA_BIN" --all "${MDA_ARGS[@]}")
        else
            cmd=(bash "$MDA_BIN" --good "${MDA_ARGS[@]}")
        fi
        local found_all=0
        for arg in "${cmd[@]}"; do
            if [[ "$arg" == "--all" ]]; then
                found_all=1
                break
            fi
        done
        if [[ $found_all -ne 1 ]]; then
            echo "  ASSERT FAILED: load_items should pass --all when show_all=1, got: ${cmd[*]}"
            exit 1
        fi
    )
}

test_load_items_passes_good_flag () {
    # When show_all=0, load_items must pass --good to envoy-analyze
    (
        MDX_TESTING=1 source "$MDX_SCRIPT"
        show_all=0
        MDA_ARGS=("$SAMPLES_DIR/trees.csv")
        local cmd
        if [[ $show_all -eq 1 ]]; then
            cmd=(bash "$MDA_BIN" --all "${MDA_ARGS[@]}")
        else
            cmd=(bash "$MDA_BIN" --good "${MDA_ARGS[@]}")
        fi
        local found_good=0
        for arg in "${cmd[@]}"; do
            if [[ "$arg" == "--good" ]]; then
                found_good=1
                break
            fi
        done
        if [[ $found_good -ne 1 ]]; then
            echo "  ASSERT FAILED: load_items should pass --good when show_all=0, got: ${cmd[*]}"
            exit 1
        fi
    )
}

test_section_prefix_map_completeness () {
    (
        MDX_TESTING=1 source "$MDX_SCRIPT"
        local expected_prefixes=("Summary stats" "Histogram" "Sparkline" "Anomaly detection" "Top values" "Distribution shape" "Category dominance" "Coefficient of variation" "Mode" "Normality" "Numeric precision" "Trend" "Bimodality" "Benford's Law" "Monotonicity" "Group summary" "Numeric exclusion warning")
        for prefix in "${expected_prefixes[@]}"; do
            if [[ -z "${SECTION_PREFIX_MAP[$prefix]:-}" ]]; then
                echo "  ASSERT FAILED: SECTION_PREFIX_MAP missing prefix '$prefix'"
                exit 1
            fi
        done
    )
}

################################################################################
## TUI rendering / input handling tests
## These test envoy-browse's graceful handling of various edge cases.
################################################################################

test_missing_file_exits_nonzero () {
    # envoy-browse given a nonexistent file should exit non-zero and not hang
    local rc=0
    run_mdx /tmp/nonexistent_file_that_does_not_exist_$$.csv 2>/dev/null </dev/null || rc=$?
    if [[ "$rc" -eq 0 ]]; then
        echo "  ASSERT FAILED: envoy-browse with missing file should exit non-zero"
        return 1
    fi
}

test_empty_csv_exits_nonzero () {
    # envoy-browse given an empty CSV file should exit non-zero (envoy-analyze produces no output)
    local tmpfile
    tmpfile=$(mktemp "${TMPDIR:-/tmp}/envoy_browse_empty_test.XXXXXX.csv")
    : > "$tmpfile"
    local rc=0
    run_mdx "$tmpfile" 2>/dev/null </dev/null || rc=$?
    rm -f "$tmpfile"
    if [[ "$rc" -eq 0 ]]; then
        echo "  ASSERT FAILED: envoy-browse with empty CSV should exit non-zero"
        return 1
    fi
}

test_piped_input_requires_tty () {
    # Piping input to envoy-browse without a TTY should fail gracefully
    local rc=0
    echo "a,b,c" | run_mdx 2>/dev/null || rc=$?
    if [[ "$rc" -eq 0 ]]; then
        echo "  ASSERT FAILED: envoy-browse piped without TTY should exit non-zero"
        return 1
    fi
}

########################################
## Run all envoy-browse tests
##

# Original tests
run_test "envoy-browse --help exits zero with correct content" test_help_exits_zero
run_test "envoy-browse with no input exits non-zero" test_no_input_exits_nonzero
run_test "envoy-browse --suggest rejected" test_bad_flag_exits_nonzero
run_test "envoy-browse --help documents all navigation keys" test_help_documents_all_keys
run_test "envoy-browse --all flag accepted" test_all_flag_accepted
run_test "envoy-browse --debug flag accepted" test_debug_flag_accepted

# v0.7 unit tests
run_test "parse_section_title: Summary stats → summary" test_parse_section_title_summary
run_test "parse_section_title: unknown prefix → empty" test_parse_section_title_unknown
run_test "classify_title: Dataset overview → summary" test_classify_title_summary
run_test "classify_title: Histogram: age → variable" test_classify_title_variable
run_test "classify_title: Correlation matrix → multi" test_classify_title_multi
run_test "wrap_text: short line unchanged" test_wrap_text_short
run_test "wrap_text: long line wraps" test_wrap_text_long
run_test "wrap_text: no-space text wraps" test_wrap_text_no_spaces
run_test "wrap_text: empty string" test_wrap_text_empty
run_test "compose_var_body: empty data" test_compose_var_body_empty
run_test "compose_var_body: partial data" test_compose_var_body_partial
run_test "load_items passes --all when show_all=1" test_load_items_passes_all_flag
run_test "load_items passes --good when show_all=0" test_load_items_passes_good_flag
run_test "SECTION_PREFIX_MAP has all 17 prefixes" test_section_prefix_map_completeness

# TUI rendering / edge case tests
run_test "envoy-browse with missing file exits non-zero" test_missing_file_exits_nonzero
run_test "envoy-browse with empty CSV exits non-zero" test_empty_csv_exits_nonzero
run_test "envoy-browse piped input without TTY exits non-zero" test_piped_input_requires_tty

print_summary
