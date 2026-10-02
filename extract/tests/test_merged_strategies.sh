#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Merged Strategy Regression Tests
##
## Tests for strategies that were merged from two or more original strategies.
## Each merged strategy must handle BOTH input styles from its predecessors.
##
## Merged strategies:
##   block-records     (blank-line-records + repeated-blocks)
##   exposition-format (prometheus + openmetrics)
##   pipe-table        (sql-result + markdown-table)
##   network-hops      (traceroute + mtr)
##   xml               (xml-elements + xml-attributes)
##   test-results      (go-test + cargo-test)
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Merged Strategy Regression Tests"
echo "========================================"

################################################################################
## block-records (blank-line-records + repeated-blocks)
################################################################################

test_block_records_blank_line_input () {
    local tmpfile output rc
    tmpfile=$(mktemp)
    # Blank-line-separated records with key:value pairs
    printf 'Name: Alice\nAge: 30\nCity: Portland\n\nName: Bob\nAge: 25\nCity: Denver\n' > "$tmpfile"
    rc=0
    output=$(run_extract -r -s block-records "$tmpfile" 2>/dev/null) || rc=$?
    rm -f "$tmpfile"
    assert_exit_zero "$rc" "block-records should handle blank-line-separated records"
    assert_contains "$output" "Name" "should extract Name field from blank-line records"
    assert_contains "$output" "Alice" "should extract Alice value"
}

test_block_records_repeated_block_input () {
    local tmpfile output rc
    tmpfile=$(mktemp)
    # Repeated blocks with key=value pairs separated by blank lines
    printf 'host=web01\nport=80\nstatus=up\n\nhost=web02\nport=443\nstatus=down\n' > "$tmpfile"
    rc=0
    output=$(run_extract -r -s block-records "$tmpfile" 2>/dev/null) || rc=$?
    rm -f "$tmpfile"
    assert_exit_zero "$rc" "block-records should handle repeated block patterns"
    assert_contains "$output" "host" "should extract host field from repeated blocks"
}

################################################################################
## exposition-format (prometheus + openmetrics)
################################################################################

test_exposition_prometheus_input () {
    local tmpfile output rc
    tmpfile=$(mktemp)
    # Prometheus exposition format
    printf '# HELP http_requests_total The total number of HTTP requests.\n# TYPE http_requests_total counter\nhttp_requests_total{method="post",code="200"} 1027\nhttp_requests_total{method="get",code="200"} 5023\n' > "$tmpfile"
    rc=0
    output=$(run_extract -r -s exposition-format "$tmpfile" 2>/dev/null) || rc=$?
    rm -f "$tmpfile"
    assert_exit_zero "$rc" "exposition-format should handle prometheus input"
    assert_contains "$output" "http_requests_total" "should extract prometheus metric name"
}

test_exposition_openmetrics_input () {
    local tmpfile output rc
    tmpfile=$(mktemp)
    # OpenMetrics format with # EOF marker and _created metric
    printf '# TYPE process_cpu_seconds counter\n# UNIT process_cpu_seconds seconds\nprocess_cpu_seconds_total 0.45\nprocess_cpu_seconds_created 1234567890.0\n# EOF\n' > "$tmpfile"
    rc=0
    output=$(run_extract -r -s exposition-format "$tmpfile" 2>/dev/null) || rc=$?
    rm -f "$tmpfile"
    assert_exit_zero "$rc" "exposition-format should handle openmetrics input"
    assert_contains "$output" "process_cpu_seconds" "should extract openmetrics metric"
}

################################################################################
## pipe-table (sql-result + markdown-table)
################################################################################



################################################################################
## network-hops (traceroute + mtr)
################################################################################



################################################################################
## xml (xml-elements + xml-attributes)
################################################################################

test_xml_elements_input () {
    local tmpfile output rc
    tmpfile=$(mktemp)
    # XML with element text content
    printf '<config>\n  <server>localhost</server>\n  <port>8080</port>\n  <debug>true</debug>\n</config>\n' > "$tmpfile"
    rc=0
    output=$(run_extract -r -s xml "$tmpfile" 2>/dev/null) || rc=$?
    rm -f "$tmpfile"
    assert_exit_zero "$rc" "xml should handle element text extraction"
    assert_contains "$output" "server" "should extract server element"
    assert_contains "$output" "localhost" "should extract localhost value"
}

test_xml_attributes_input () {
    local tmpfile output rc
    tmpfile=$(mktemp)
    # XML with attributes
    printf '<servers>\n  <server name="web01" port="80" status="active"/>\n  <server name="web02" port="443" status="standby"/>\n</servers>\n' > "$tmpfile"
    rc=0
    output=$(run_extract -r -s xml "$tmpfile" 2>/dev/null) || rc=$?
    rm -f "$tmpfile"
    assert_exit_zero "$rc" "xml should handle attribute extraction"
    assert_contains "$output" "name" "should extract name attribute"
    assert_contains "$output" "web01" "should extract web01 value"
}

################################################################################
## test-results (go-test + cargo-test)
################################################################################



################################################################################
## Run all tests
################################################################################

run_test "block-records: blank-line-separated input" test_block_records_blank_line_input
run_test "block-records: repeated-block pattern input" test_block_records_repeated_block_input
run_test "exposition-format: prometheus input" test_exposition_prometheus_input
run_test "exposition-format: openmetrics input" test_exposition_openmetrics_input
run_test "xml: element text content" test_xml_elements_input
run_test "xml: attribute key/value pairs" test_xml_attributes_input

print_summary
