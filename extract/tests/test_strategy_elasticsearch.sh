#!/bin/bash
################################################################################
## Strategy Tests: elasticsearch
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: elasticsearch"
echo "========================================"

test_elasticsearch_basic () {
    local output
    output=$(run_mfe -r -s elasticsearch "$SAMPLES_DIR/elasticsearch/basic.json")
    assert_contains "$output" "took 5" "should extract took"
    assert_contains "$output" "timed_out false" "should extract timed_out"
    assert_contains "$output" "_shards.total 5" "should extract _shards.total"
    assert_contains "$output" "_shards.successful 5" "should extract _shards.successful"
    assert_contains "$output" "_shards.failed 0" "should extract _shards.failed"
    assert_contains "$output" "hits.total.value 2" "should extract hits.total.value"
    assert_contains "$output" "hit1._id 1" "should extract hit1._id"
    assert_contains "$output" "hit1._source.name Widget" "should extract hit1 source name"
    assert_contains "$output" "hit2._id 2" "should extract hit2._id"
    assert_contains "$output" "hit2._source.name Gadget" "should extract hit2 source name"
}

test_elasticsearch_not_detected_for_plain_json () {
    local output
    output=$(run_mfe -d -s elasticsearch "$SAMPLES_DIR/json/basic.json" 2>&1)
    assert_contains "$output" "not applicable" "elasticsearch should not apply to plain JSON"
}

test_elasticsearch_not_detected_for_grafana () {
    local output
    output=$(run_mfe -d -s elasticsearch "$SAMPLES_DIR/grafana-dashboard/basic.json" 2>&1)
    assert_contains "$output" "not applicable" "elasticsearch should not apply to Grafana dashboard JSON"
}

run_test "elasticsearch: basic extraction" test_elasticsearch_basic
run_test "elasticsearch: not detected for plain JSON" test_elasticsearch_not_detected_for_plain_json
run_test "elasticsearch: not detected for Grafana dashboard JSON" test_elasticsearch_not_detected_for_grafana

print_summary
