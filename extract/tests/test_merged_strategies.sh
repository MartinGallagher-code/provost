#!/bin/bash
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
    output=$(run_mfe -r -s block-records "$tmpfile" 2>/dev/null) || rc=$?
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
    output=$(run_mfe -r -s block-records "$tmpfile" 2>/dev/null) || rc=$?
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
    output=$(run_mfe -r -s exposition-format "$tmpfile" 2>/dev/null) || rc=$?
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
    output=$(run_mfe -r -s exposition-format "$tmpfile" 2>/dev/null) || rc=$?
    rm -f "$tmpfile"
    assert_exit_zero "$rc" "exposition-format should handle openmetrics input"
    assert_contains "$output" "process_cpu_seconds" "should extract openmetrics metric"
}

################################################################################
## pipe-table (sql-result + markdown-table)
################################################################################

test_pipe_table_sql_result_input () {
    # +---+ box tables are now owned by psql-table (pipe-table declines them so
    # its title-banner-mangling flatten parser no longer shadows the box parser).
    local tmpfile output rc
    tmpfile=$(mktemp)
    # SQL result format with +-+ borders
    printf '+------+-----+\n| Name | Age |\n+------+-----+\n| Alice|  30 |\n| Bob  |  25 |\n+------+-----+\n' > "$tmpfile"
    rc=0
    output=$(run_mfe -r -s psql-table "$tmpfile" 2>/dev/null) || rc=$?
    rm -f "$tmpfile"
    assert_exit_zero "$rc" "psql-table should handle SQL result box format"
    assert_contains "$output" "Name" "should extract Name from SQL result"
}

test_pipe_table_markdown_input () {
    local tmpfile output rc
    tmpfile=$(mktemp)
    # Markdown table with |---| separators
    printf '| Name  | Age | City     |\n|-------|-----|----------|\n| Alice | 30  | Portland |\n| Bob   | 25  | Denver   |\n' > "$tmpfile"
    rc=0
    output=$(run_mfe -r -s pipe-table "$tmpfile" 2>/dev/null) || rc=$?
    rm -f "$tmpfile"
    assert_exit_zero "$rc" "pipe-table should handle markdown table format"
    assert_contains "$output" "Name" "should extract Name from markdown table"
}

################################################################################
## network-hops (traceroute + mtr)
################################################################################

test_network_hops_traceroute_input () {
    local tmpfile output rc
    tmpfile=$(mktemp)
    # traceroute output
    printf 'traceroute to example.com (93.184.216.34), 30 hops max, 60 byte packets\n 1  gateway (192.168.1.1)  1.234 ms  1.456 ms  1.678 ms\n 2  10.0.0.1 (10.0.0.1)  5.678 ms  5.789 ms  5.890 ms\n 3  example.com (93.184.216.34)  20.123 ms  20.456 ms  20.789 ms\n' > "$tmpfile"
    rc=0
    output=$(run_mfe -r -s network-hops "$tmpfile" 2>/dev/null) || rc=$?
    rm -f "$tmpfile"
    assert_exit_zero "$rc" "network-hops should handle traceroute output"
    assert_contains "$output" "destination" "should extract destination from traceroute"
}

test_network_hops_mtr_input () {
    local tmpfile output rc
    tmpfile=$(mktemp)
    # mtr --report output
    printf 'Start: 2024-01-15T10:00:00+0000\nHOST: server                     Loss%%   Snt   Last   Avg  Best  Wrst StDev\n  1.|-- gateway                    0.0%%    10    1.2   1.3   1.0   1.8   0.2\n  2.|-- 10.0.0.1                   0.0%%    10    5.4   5.5   5.0   6.2   0.3\n  3.|-- example.com                0.0%%    10   20.1  20.3  19.8  21.0   0.4\n' > "$tmpfile"
    rc=0
    output=$(run_mfe -r -s network-hops "$tmpfile" 2>/dev/null) || rc=$?
    rm -f "$tmpfile"
    assert_exit_zero "$rc" "network-hops should handle mtr output"
    assert_contains "$output" "hop" "should extract hop fields from mtr"
}

################################################################################
## xml (xml-elements + xml-attributes)
################################################################################

test_xml_elements_input () {
    local tmpfile output rc
    tmpfile=$(mktemp)
    # XML with element text content
    printf '<config>\n  <server>localhost</server>\n  <port>8080</port>\n  <debug>true</debug>\n</config>\n' > "$tmpfile"
    rc=0
    output=$(run_mfe -r -s xml "$tmpfile" 2>/dev/null) || rc=$?
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
    output=$(run_mfe -r -s xml "$tmpfile" 2>/dev/null) || rc=$?
    rm -f "$tmpfile"
    assert_exit_zero "$rc" "xml should handle attribute extraction"
    assert_contains "$output" "name" "should extract name attribute"
    assert_contains "$output" "web01" "should extract web01 value"
}

################################################################################
## test-results (go-test + cargo-test)
################################################################################

test_results_go_test_input () {
    local tmpfile output rc
    tmpfile=$(mktemp)
    # go test output
    printf '=== RUN   TestAdd\n--- PASS: TestAdd (0.00s)\n=== RUN   TestSubtract\n--- PASS: TestSubtract (0.01s)\n=== RUN   TestDivideByZero\n--- FAIL: TestDivideByZero (0.00s)\n    calc_test.go:42: expected error\nPASS\nok  \tgithub.com/example/calc\t0.015s\n' > "$tmpfile"
    rc=0
    output=$(run_mfe -r -s test-results "$tmpfile" 2>/dev/null) || rc=$?
    rm -f "$tmpfile"
    assert_exit_zero "$rc" "test-results should handle go test output"
    assert_contains "$output" "TestAdd" "should extract TestAdd name"
    assert_contains "$output" "PASS" "should extract PASS result"
}

test_results_cargo_test_input () {
    local tmpfile output rc
    tmpfile=$(mktemp)
    # cargo test output
    printf '\nrunning 3 tests\ntest tests::test_add ... ok\ntest tests::test_multiply ... ok\ntest tests::test_divide_by_zero ... FAILED\n\ntest result: FAILED. 2 passed; 1 failed; 0 ignored; 0 measured; 0 filtered out\n' > "$tmpfile"
    rc=0
    output=$(run_mfe -r -s test-results "$tmpfile" 2>/dev/null) || rc=$?
    rm -f "$tmpfile"
    assert_exit_zero "$rc" "test-results should handle cargo test output"
    assert_contains "$output" "test_add" "should extract test_add name (normalized to dot)"
    assert_contains "$output" "ok" "should extract ok result"
}

################################################################################
## Run all tests
################################################################################

run_test "block-records: blank-line-separated input" test_block_records_blank_line_input
run_test "block-records: repeated-block pattern input" test_block_records_repeated_block_input
run_test "exposition-format: prometheus input" test_exposition_prometheus_input
run_test "exposition-format: openmetrics input" test_exposition_openmetrics_input
run_test "pipe-table: SQL result format input" test_pipe_table_sql_result_input
run_test "pipe-table: markdown table format input" test_pipe_table_markdown_input
run_test "network-hops: traceroute output" test_network_hops_traceroute_input
run_test "network-hops: mtr output" test_network_hops_mtr_input
run_test "xml: element text content" test_xml_elements_input
run_test "xml: attribute key/value pairs" test_xml_attributes_input
run_test "test-results: go test output" test_results_go_test_input
run_test "test-results: cargo test output" test_results_cargo_test_input

print_summary
