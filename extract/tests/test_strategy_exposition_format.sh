#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Strategy Tests: exposition-format
## Consolidates tests from: prometheus, openmetrics
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: exposition-format"
echo "========================================"

# --- prometheus cases ---

test_ef_prometheus_basic () {
    local output
    output=$(run_extract -r -s exposition-format "$SAMPLES_DIR/prometheus/basic.txt")
    assert_contains "$output" "metric1.name http_requests_total" "should extract first metric name"
    assert_contains "$output" "metric1.value 1027" "should extract first metric value"
    # Labels are one column each (`label_method`, `label_code`), not one
    # opaque `labels` blob — this assertion predates that change.
    assert_contains "$output" "metric1.label_method post" "should extract the method label"
    assert_contains "$output" "metric1.label_code 200" "should extract the code label"
    assert_contains "$output" "metric2.name http_requests_total" "should extract second metric name"
    assert_contains "$output" "metric2.value 3" "should extract second metric value"
    assert_contains "$output" "metric3.name process_cpu_seconds_total" "should extract bare metric name"
    assert_contains "$output" "metric3.value 0.52" "should extract bare metric value"
    assert_contains "$output" "metric4.name go_goroutines" "should extract gauge metric name"
    assert_contains "$output" "metric4.value 33" "should extract gauge metric value"
    assert_not_contains "$output" "metric3.labels" "bare metric should not have labels"
}

test_ef_prometheus_metadata () {
    local output
    output=$(run_extract -r -s exposition-format "$SAMPLES_DIR/prometheus/basic.txt")
    assert_contains "$output" "http_requests_total.help The total number of HTTP requests." "should extract help text"
    assert_contains "$output" "http_requests_total.type counter" "should extract type"
    assert_contains "$output" "process_cpu_seconds_total.type counter" "should extract cpu type"
    assert_contains "$output" "go_goroutines.type gauge" "should extract gauge type"
    assert_contains "$output" "go_goroutines.help Number of goroutines that currently exist." "should extract goroutines help"
}

# --- openmetrics cases ---

test_ef_openmetrics_basic () {
    local output
    output=$(run_extract -r -s exposition-format "$SAMPLES_DIR/openmetrics/basic.txt")
    assert_contains "$output" "http_requests_total.type counter" "should extract type"
    assert_contains "$output" "http_requests_total.unit requests" "should extract unit"
    assert_contains "$output" "http_requests_total.help Total HTTP requests" "should extract help"
    assert_contains "$output" "metric1.name http_requests_total" "should extract metric1 name"
    assert_contains "$output" "metric1.value 1234" "should extract metric1 value"
    assert_contains "$output" "metric4.name process_cpu_seconds_total" "should extract process cpu metric"
    assert_contains "$output" "metric4.value 456.78" "should extract process cpu value"
    assert_contains "$output" "metric8.name http_request_duration_seconds_count" "should extract histogram count"
}

# --- rejection tests ---

test_ef_not_detected_for_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"key": "value", "count": 42}\n' > "$tmpfile"
    local output
    output=$(run_extract -d -s exposition-format "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "exposition-format should not apply to JSON"
}

test_ef_detects_prometheus_format () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '# TYPE http_requests_total counter\nhttp_requests_total 100\n' > "$tmpfile"
    local output
    output=$(run_extract -r -s exposition-format "$tmpfile")
    rm -f "$tmpfile"
    assert_contains "$output" "http_requests_total.type counter" "should detect and extract Prometheus format"
    assert_contains "$output" "metric1.name http_requests_total" "should extract metric name"
    assert_contains "$output" "metric1.value 100" "should extract metric value"
}

test_ef_detects_openmetrics_eof () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '# TYPE requests counter\nrequests_total 42\n# EOF\n' > "$tmpfile"
    local output
    output=$(run_extract -r -s exposition-format "$tmpfile")
    rm -f "$tmpfile"
    assert_contains "$output" "requests.type counter" "should extract type from OpenMetrics"
    assert_contains "$output" "metric1.value 42" "should extract metric value"
    assert_not_contains "$output" "# EOF" "should not emit EOF line as a field"
}

run_test "exposition-format: Prometheus basic extraction" test_ef_prometheus_basic
run_test "exposition-format: Prometheus help/type metadata" test_ef_prometheus_metadata
run_test "exposition-format: OpenMetrics basic extraction" test_ef_openmetrics_basic
run_test "exposition-format: not detected for JSON" test_ef_not_detected_for_json
run_test "exposition-format: detects Prometheus format" test_ef_detects_prometheus_format
run_test "exposition-format: detects OpenMetrics EOF" test_ef_detects_openmetrics_eof

print_summary
