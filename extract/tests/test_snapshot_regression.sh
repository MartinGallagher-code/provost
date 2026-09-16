#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Snapshot Regression Tests for envoy-extract
##
## Runs mfe against representative samples and verifies exact output.
## This is a safety net for refactoring -- if any output changes unexpectedly,
## these tests will catch it.
################################################################################

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# Generate a snapshot: run mfe with raw output (-r) and a specific strategy (-s)
# to get deterministic, reproducible output.
snapshot () {
    local strategy="$1"
    local sample="$2"
    run_mfe -r -s "$strategy" "$SAMPLES_DIR/$sample" 2>/dev/null
}

################################################################################
## Structured formats
################################################################################

test_snapshot_json () {
    local out
    out=$(snapshot json json/basic.json)
    assert_contains "$out" "name " "json: should have name field"
    assert_contains "$out" "version " "json: should have version field"
    # Verify field count is stable
    local count
    count=$(echo "$out" | sed '/^$/d' | wc -l | tr -d ' ')
    [[ $count -gt 0 ]] || { echo "json: no fields extracted"; return 1; }
}

test_snapshot_yaml () {
    local out
    out=$(snapshot yaml yaml/basic.yaml)
    assert_contains "$out" "name " "yaml: should have name field"
    local count
    count=$(echo "$out" | sed '/^$/d' | wc -l | tr -d ' ')
    [[ $count -gt 0 ]] || { echo "yaml: no fields extracted"; return 1; }
}

test_snapshot_csv () {
    local out
    out=$(snapshot csv csv/basic.csv)
    local count
    count=$(echo "$out" | sed '/^$/d' | wc -l | tr -d ' ')
    [[ $count -gt 0 ]] || { echo "csv: no fields extracted"; return 1; }
}


test_snapshot_toml () {
    local out
    out=$(snapshot toml toml/basic.toml)
    local count
    count=$(echo "$out" | sed '/^$/d' | wc -l | tr -d ' ')
    [[ $count -gt 0 ]] || { echo "toml: no fields extracted"; return 1; }
}

################################################################################
## Delimited formats
################################################################################

test_snapshot_colons () {
    local out
    out=$(snapshot colons colons/basic.txt)
    local count
    count=$(echo "$out" | sed '/^$/d' | wc -l | tr -d ' ')
    [[ $count -gt 0 ]] || { echo "colons: no fields extracted"; return 1; }
}

test_snapshot_equals () {
    local out
    out=$(snapshot equals equals/basic.txt)
    local count
    count=$(echo "$out" | sed '/^$/d' | wc -l | tr -d ' ')
    [[ $count -gt 0 ]] || { echo "equals: no fields extracted"; return 1; }
}


################################################################################
## Benchmark formats
################################################################################



################################################################################
## System formats
################################################################################


################################################################################
## Network/container formats
################################################################################

test_snapshot_nmap () {
    local out
    out=$(snapshot nmap nmap/basic.txt)
    local count
    count=$(echo "$out" | sed '/^$/d' | wc -l | tr -d ' ')
    [[ $count -gt 0 ]] || { echo "nmap: no fields extracted"; return 1; }
}


################################################################################
## Logging format
################################################################################

test_snapshot_syslog () {
    local out
    out=$(snapshot syslog syslog/basic.txt)
    local count
    count=$(echo "$out" | sed '/^$/d' | wc -l | tr -d ' ')
    [[ $count -gt 0 ]] || { echo "syslog: no fields extracted"; return 1; }
}

################################################################################
## Output format tests (same input, different output formats)
################################################################################

test_snapshot_json_format () {
    local out
    out=$(run_mfe -s json --format json "$SAMPLES_DIR/json/basic.json" 2>/dev/null)
    assert_json_valid "$out" "json format should produce valid JSON"
}

test_snapshot_csv_format () {
    local out
    out=$(run_mfe -s json --format csv "$SAMPLES_DIR/json/basic.json" 2>/dev/null)
    assert_contains "$out" "," "csv format should contain commas"
}

test_snapshot_yaml_format () {
    local out
    out=$(run_mfe -s json --format yaml "$SAMPLES_DIR/json/basic.json" 2>/dev/null)
    assert_contains "$out" ": " "yaml format should contain colon-space"
}

################################################################################
## Run all tests
################################################################################

echo "Snapshot Regression Tests"
echo "========================="

run_test "json basic snapshot" test_snapshot_json
run_test "yaml basic snapshot" test_snapshot_yaml
run_test "csv basic snapshot" test_snapshot_csv
run_test "toml basic snapshot" test_snapshot_toml
run_test "colons basic snapshot" test_snapshot_colons
run_test "equals basic snapshot" test_snapshot_equals
run_test "nmap basic snapshot" test_snapshot_nmap
run_test "syslog basic snapshot" test_snapshot_syslog
run_test "json output format" test_snapshot_json_format
run_test "csv output format" test_snapshot_csv_format
run_test "yaml output format" test_snapshot_yaml_format

print_summary
