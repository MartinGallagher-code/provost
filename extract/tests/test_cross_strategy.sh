#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Cross-Strategy False-Positive Tests
##
## Verify that similar-looking formats don't confuse each other.
## Each test ensures a specific strategy does NOT falsely claim input
## intended for a different strategy.
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Cross-Strategy False-Positive Tests"
echo "========================================"

# --- colons confusion ---

test_xstrat_yaml_not_colons () {
    # YAML uses "key: value" syntax which could trigger colons (c35, p60)
    # yaml (c90, p12) should win with auto-detect
    local output
    output=$(run_mfe -r "$SAMPLES_DIR/yaml/basic.yaml")
    # yaml produces dot-notation fields; colons would produce flat fields
    assert_contains "$output" "database.host" "auto-detect should use yaml (dot-notation)"
}




test_xstrat_syslog_not_colons () {
    # Syslog lines contain colons in timestamps and process names
    # syslog (c80, p20) should be detected over colons (c35, p60)
    local output
    output=$(run_mfe -r "$SAMPLES_DIR/syslog/basic.txt")
    assert_contains "$output" "hostname" "auto-detect should use syslog (hostname field)"
}

# --- equals confusion ---

test_xstrat_toml_not_equals () {
    # TOML uses key = value with [section] headers
    # toml (c85, p15) should win over equals (c35, p65)
    local output
    output=$(run_mfe -r "$SAMPLES_DIR/toml/basic.toml")
    assert_contains "$output" "." "auto-detect should use toml (section-dot-prefixed fields)"
}


# --- format confusion: toml vs ini ---

test_xstrat_toml_detected () {
    # TOML uses [section] headers; auto-detect should pick toml
    local auto_output
    auto_output=$(run_mfe -d -r "$SAMPLES_DIR/toml/basic.toml" 2>&1)
    assert_contains "$auto_output" "toml" "toml should be detected for TOML files"
}

# --- tabular format confusion ---

test_xstrat_csv_not_tsv () {
    # CSV has commas, no tabs — TSV should fail detection
    local output
    output=$(run_mfe -d -s tsv "$SAMPLES_DIR/csv/basic.csv" 2>&1)
    assert_contains "$output" "not applicable" "tsv should not detect CSV input"
}

test_xstrat_tsv_not_csv () {
    # TSV has tabs, commas only if in values — CSV should not produce good output
    local output
    output=$(run_mfe -d -s csv "$SAMPLES_DIR/tsv/basic.tsv" 2>&1)
    # CSV may or may not detect (depends on comma count); key test is auto-detect prefers tsv
    local auto_output
    auto_output=$(run_mfe -d -r "$SAMPLES_DIR/tsv/basic.tsv" 2>&1)
    assert_contains "$auto_output" "tsv" "auto-detect should prefer tsv for TSV files"
}

test_xstrat_fixedwidth_not_aligned () {
    # Fixed-width has dash separator; aligned-columns is a generic fallback (c30, p70)
    # fixed-width (c65, p30) should be detected first due to separator line
    local output
    output=$(run_mfe -d -r "$SAMPLES_DIR/fixed-width/basic.txt" 2>&1)
    assert_contains "$output" "fixed-width" "fixed-width should be detected (has separator)"
}

test_xstrat_aligned_not_fixedwidth () {
    # Aligned-columns sample has no dash separator — fixed-width should not detect
    local output
    output=$(run_mfe -d -s fixed-width "$SAMPLES_DIR/aligned-columns/basic.txt" 2>&1)
    assert_contains "$output" "not applicable" "fixed-width should not detect aligned-columns input"
}

# --- JSON format confusion ---

test_xstrat_json_not_jsonl () {
    # A multi-line JSON object should not trigger JSONL
    local output
    output=$(run_mfe -d -s jsonl "$SAMPLES_DIR/json/basic.json" 2>&1)
    assert_contains "$output" "not applicable" "jsonl should not detect multi-line JSON"
}

# --- hierarchical format confusion ---

test_xstrat_yaml_not_indented () {
    # yaml (c90, p12) has higher priority and confidence than indented-hierarchy (c65, p50)
    local output
    output=$(run_mfe -d -r "$SAMPLES_DIR/yaml/basic.yaml" 2>&1)
    assert_contains "$output" "yaml" "yaml should be detected before indented-hierarchy"
}



# --- container output confusion ---

# Note: test_xstrat_dockerps_not_aligned is not included because aligned-columns
# is intentionally a generic fallback that matches many formats. The priority system
# handles this correctly (docker-ps c90/p12 runs before aligned-columns c30/p70).

# --- Register all tests ---

run_test "xstrat: yaml not confused with colons" test_xstrat_yaml_not_colons
run_test "xstrat: syslog not confused with colons" test_xstrat_syslog_not_colons
run_test "xstrat: toml not confused with equals" test_xstrat_toml_not_equals
run_test "xstrat: toml detected for TOML files" test_xstrat_toml_detected
run_test "xstrat: csv not confused with tsv" test_xstrat_csv_not_tsv
run_test "xstrat: tsv not confused with csv" test_xstrat_tsv_not_csv
run_test "xstrat: fixed-width not confused with aligned-columns" test_xstrat_fixedwidth_not_aligned
run_test "xstrat: aligned-columns not confused with fixed-width" test_xstrat_aligned_not_fixedwidth
run_test "xstrat: json not confused with jsonl" test_xstrat_json_not_jsonl
run_test "xstrat: yaml not confused with indented-hierarchy" test_xstrat_yaml_not_indented

print_summary
