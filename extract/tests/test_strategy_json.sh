#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Strategy Tests: json
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: json"
echo "========================================"

test_json_basic () {
    local output
    output=$(run_extract -r -s json "$SAMPLES_DIR/json/basic.json")
    assert_contains "$output" "name" "should extract name"
    assert_contains "$output" "test-project" "should extract value test-project"
    assert_contains "$output" "version" "should extract version"
    assert_contains "$output" "1.2.3" "should extract value 1.2.3"
    assert_contains "$output" "count" "should extract count"
    assert_contains "$output" "42" "should extract value 42"
    assert_contains "$output" "enabled" "should extract enabled"
    assert_contains "$output" "true" "should extract value true"
}

test_json_sample1 () {
    local output
    output=$(run_extract -r -s json "$SAMPLES_DIR/json/benchmark.json")
    assert_contains "$output" "date" "should extract date"
    assert_contains "$output" "num_cpus" "should extract num_cpus"
    assert_contains "$output" "40" "should extract value 40"
    assert_contains "$output" "iterations" "should extract iterations"
}

test_json_field_selection () {
    local output
    output=$(run_extract -s json "$SAMPLES_DIR/json/basic.json" 1,3)
    assert_contains "$output" "name" "should contain field 1"
    assert_contains "$output" "count" "should contain field 3"
    assert_not_contains "$output" "version" "should not contain unselected field"
}

test_json_not_detected_for_non_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf "Name: value\nKey: data\n" > "$tmpfile"
    local output
    output=$(run_extract -d -s json "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "json should not apply to non-JSON"
}

test_json_stdin () {
    local output
    output=$(echo '{"color": "blue", "size": 10}' | run_extract -r -s json)
    assert_contains "$output" "color" "should extract color from stdin"
    assert_contains "$output" "blue" "should extract value blue"
    assert_contains "$output" "size" "should extract size"
    assert_contains "$output" "10" "should extract value 10"
}

# Without jq the json strategy reads with _json_walk, which must print what
# the jq filter prints: nested objects and arrays under their paths (arrays
# from 0), escapes and \uXXXX decoded, numbers as written, a stream of
# values each in turn. It used to stop at the first nested value.
JSON_TRICKY='{"a":1,"host":"wr01","cpu":{"count":64,"model":"EPYC 9654"},"nics":[{"name":"eth0","mtu":9000},{"name":"eth1","mtu":1500}],"tags":["a","b c"],"empty":{},"none":[],"ratio":1.50,"neg":-2,"ok":true,"gone":null,"esc":"q\"t \\ \/ \u00e9\ud83d\ude00","nl":"two\nlines"}'

test_json_walk_matches_jq () {
    if ! command -v jq >/dev/null 2>&1; then
        echo "    (jq not installed: nothing to compare against)"
        return 0
    fi
    local dir="${PROVOST_EXTRACT_SCRIPT%/*}" a b in
    for in in "$JSON_TRICKY" '{"a":1}{"b":[2,3]} junk'; do
        a="$(source "$dir/lib/_helpers.sh"; source "$dir/strategies/structured/json.sh"; _strat_json_extract_jq "$in")"
        b="$(source "$dir/lib/_helpers.sh"; _json_walk leaves "$in")"
        assert_contains "$a" "a 1" "jq read it (or the comparison means nothing)" || return 1
        assert_eq "$a" "$b" "the awk reader prints what jq prints: ${in:0:30}"
    done
}

test_json_without_jq_keeps_nested () {
    local tmp output
    tmp="$(mktemp)"
    printf '%s\n' "$JSON_TRICKY" > "$tmp"
    output=$(run_extract_nojq -r -s json -f plain "$tmp")
    rm -f "$tmp"
    assert_contains "$output" "cpu.model EPYC 9654" "a nested object's keys, dotted"
    assert_contains "$output" "nics.1.mtu 1500" "an array of objects, indexed from 0"
    assert_contains "$output" "tags.1 b c" "an array of scalars"
    assert_contains "$output" "ratio 1.50" "a number as written"
    assert_contains "$output" 'esc q"t \ / é😀' "escapes and surrogate pairs decoded"
    assert_contains "$output" "ok true" "a key after the nested ones"
}

run_test "json: the awk reader prints what jq prints" test_json_walk_matches_jq
run_test "json: without jq, nested values are kept" test_json_without_jq_keeps_nested
run_test "json: basic extraction" test_json_basic
run_test "json: sample-1 benchmark data" test_json_sample1
run_test "json: field selection" test_json_field_selection
run_test "json: not detected for non-JSON" test_json_not_detected_for_non_json
run_test "json: stdin input" test_json_stdin

print_summary
