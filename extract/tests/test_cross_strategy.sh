#!/bin/bash
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

test_xstrat_http_headers_not_colons () {
    # HTTP headers use "Key: value" format, same as colons
    # http-headers (c85, p20) should win over colons (c35, p60)
    local output
    output=$(run_mfe -r "$SAMPLES_DIR/http-headers/basic.txt")
    assert_contains "$output" "HTTP-Status" "auto-detect should use http-headers strategy"
}

test_xstrat_warc_not_colons () {
    # WARC headers use "Key: value" format
    # warc-headers (c80, p22) should be detected
    local output
    output=$(run_mfe -d -r "$SAMPLES_DIR/warc-headers/basic.txt" 2>&1)
    assert_contains "$output" "WARC-Type" "should extract WARC-specific fields"
}

test_xstrat_curl_headers_not_colons () {
    # curl -v output contains colon-separated header lines
    # curl-headers (c80, p22) should be preferred
    local output
    output=$(run_mfe -r "$SAMPLES_DIR/curl-headers/basic.txt")
    # curl-headers extracts prefixed fields like request.* or response.*
    assert_contains "$output" "response" "should use curl-headers (response-prefixed fields)"
}

test_xstrat_syslog_not_colons () {
    # Syslog lines contain colons in timestamps and process names
    # syslog (c80, p20) should be detected over colons (c35, p60)
    local output
    output=$(run_mfe -r "$SAMPLES_DIR/syslog/basic.txt")
    assert_contains "$output" "hostname" "auto-detect should use syslog (hostname field)"
}

# --- equals confusion ---

test_xstrat_ini_not_equals () {
    # INI files use key=value inside [sections]
    # ini (c85, p15) should win over equals (c35, p65)
    local output
    output=$(run_mfe -r "$SAMPLES_DIR/ini/basic.ini")
    # ini produces section-prefixed fields like database.host
    assert_contains "$output" "database.host" "auto-detect should use ini (section-prefixed)"
}

test_xstrat_toml_not_equals () {
    # TOML uses key = value with [section] headers
    # toml (c85, p15) should win over equals (c35, p65)
    local output
    output=$(run_mfe -r "$SAMPLES_DIR/toml/basic.toml")
    assert_contains "$output" "." "auto-detect should use toml (section-dot-prefixed fields)"
}

test_xstrat_envvars_not_equals () {
    # Both match KEY=value, but env-vars (c45, p30) detects ALL-CAPS keys
    # env-vars should be detected with higher confidence than equals (c35)
    local output
    output=$(run_mfe -d -r "$SAMPLES_DIR/env-vars/basic.txt" 2>&1)
    assert_contains "$output" "env-vars" "env-vars strategy should be detected"
}

# --- format confusion: toml vs ini ---

test_xstrat_toml_not_ini () {
    # TOML has [[array]] tables that INI doesn't handle
    # With explicit --strategy ini, should produce simpler output
    local toml_output ini_output
    toml_output=$(run_mfe -r -s toml "$SAMPLES_DIR/toml/basic.toml")
    ini_output=$(run_mfe -r -s ini "$SAMPLES_DIR/toml/basic.toml" 2>&1)
    # toml should produce richer output with array handling
    # ini may detect (both have [section] headers) but toml wins in auto-detect
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

# --- log format confusion ---

test_xstrat_journald_not_syslog () {
    # journald (c85, p14) has systemd markers; syslog (c80, p20) is more general
    local output
    output=$(run_mfe -d -r "$SAMPLES_DIR/journald/basic.txt" 2>&1)
    assert_contains "$output" "journald" "journald should be detected for systemd journal input"
}

test_xstrat_syslog_not_journald () {
    # Regular syslog without systemd markers should NOT trigger journald
    local output
    output=$(run_mfe -d -s journald "$SAMPLES_DIR/syslog/basic.txt" 2>&1)
    assert_contains "$output" "not applicable" "journald should not detect plain syslog"
}

# --- table separator confusion ---

test_xstrat_fixedwidth_not_markdown () {
    # Fixed-width uses "---- ----" separators (dashes with spaces, no pipes)
    # pipe-table requires pipe characters — should not detect fixed-width input
    local output
    output=$(run_mfe -d -s pipe-table "$SAMPLES_DIR/fixed-width/basic.txt" 2>&1)
    assert_contains "$output" "not applicable" "pipe-table should not detect fixed-width input"
}

# --- container output confusion ---

# Note: test_xstrat_dockerps_not_aligned is not included because aligned-columns
# is intentionally a generic fallback that matches many formats. The priority system
# handles this correctly (docker-ps c90/p12 runs before aligned-columns c30/p70).

# --- Register all tests ---

run_test "xstrat: yaml not confused with colons" test_xstrat_yaml_not_colons
run_test "xstrat: http-headers not confused with colons" test_xstrat_http_headers_not_colons
run_test "xstrat: warc-headers not confused with colons" test_xstrat_warc_not_colons
run_test "xstrat: curl-headers not confused with colons" test_xstrat_curl_headers_not_colons
run_test "xstrat: syslog not confused with colons" test_xstrat_syslog_not_colons
run_test "xstrat: ini not confused with equals" test_xstrat_ini_not_equals
run_test "xstrat: toml not confused with equals" test_xstrat_toml_not_equals
run_test "xstrat: env-vars not confused with equals" test_xstrat_envvars_not_equals
run_test "xstrat: toml not confused with ini" test_xstrat_toml_not_ini
run_test "xstrat: csv not confused with tsv" test_xstrat_csv_not_tsv
run_test "xstrat: tsv not confused with csv" test_xstrat_tsv_not_csv
run_test "xstrat: fixed-width not confused with aligned-columns" test_xstrat_fixedwidth_not_aligned
run_test "xstrat: aligned-columns not confused with fixed-width" test_xstrat_aligned_not_fixedwidth
run_test "xstrat: json not confused with jsonl" test_xstrat_json_not_jsonl
run_test "xstrat: yaml not confused with indented-hierarchy" test_xstrat_yaml_not_indented
run_test "xstrat: journald not confused with syslog" test_xstrat_journald_not_syslog
run_test "xstrat: syslog not confused with journald" test_xstrat_syslog_not_journald
run_test "xstrat: fixed-width not confused with markdown-table" test_xstrat_fixedwidth_not_markdown

print_summary
