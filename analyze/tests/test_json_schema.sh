#!/bin/bash
# ENV-064: JSON output envelope + schema validation
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

_has_jq=0
command -v jq >/dev/null 2>&1 && _has_jq=1

_produce_json () {
    local file="$1"
    run_mda --format json --all "$file"
}

test_envelope_has_schema_version () {
    local out
    out=$(_produce_json "$SAMPLES_DIR/trees.csv")
    assert_contains "$out" '"schema_version":"1.0"' "schema_version present"
    assert_contains "$out" '"envoy_analyze_version":' "tool version present"
    assert_contains "$out" '"items":[' "items array present"
}

test_item_has_required_keys () {
    local out
    out=$(_produce_json "$SAMPLES_DIR/trees.csv")
    # Every item must carry id, tag, kind, title, body
    for key in '"id":' '"tag":' '"kind":' '"title":' '"body":'; do
        assert_contains "$out" "$key" "items should include $key"
    done
}

test_multiple_samples_envelope () {
    for s in trees.csv anscombe.csv missing.csv; do
        local f="$SAMPLES_DIR/$s"
        [[ -f "$f" ]] || continue
        local out
        out=$(_produce_json "$f")
        assert_contains "$out" '"schema_version":"1.0"' "$s: envelope missing"
    done
}

test_jq_structural_check () {
    if [[ $_has_jq -ne 1 ]]; then
        echo "  (skipping — jq not installed)"
        return 0
    fi
    local out
    out=$(_produce_json "$SAMPLES_DIR/trees.csv")
    # schema_version is "1.0"
    local sv
    sv=$(printf '%s' "$out" | jq -r '.schema_version')
    [[ "$sv" == "1.0" ]] || { echo "  ASSERT FAILED: jq schema_version=$sv"; return 1; }
    # At least one item
    local n
    n=$(printf '%s' "$out" | jq '.items | length')
    (( n > 0 )) || { echo "  ASSERT FAILED: items array is empty"; return 1; }
    # Every item has required keys
    local missing
    missing=$(printf '%s' "$out" | jq '[.items[] | (has("id") and has("tag") and has("kind") and has("title") and has("body"))] | all')
    [[ "$missing" == "true" ]] || { echo "  ASSERT FAILED: some item is missing required keys"; return 1; }
    # Tag values are valid
    local bad_tags
    bad_tags=$(printf '%s' "$out" | jq '[.items[] | .tag | select(. != "GOOD" and . != "ADVANCED" and . != "DIAGNOSTIC" and . != "NOISY")] | length')
    [[ "$bad_tags" == "0" ]] || { echo "  ASSERT FAILED: invalid tag values"; return 1; }
}

test_schema_file_valid_json () {
    local schema
    schema="$(cd "$SCRIPT_DIR/.." && pwd)/schemas/envoy-analyze-output.json"
    [[ -f "$schema" ]] || { echo "  ASSERT FAILED: schema file missing: $schema"; return 1; }
    if [[ $_has_jq -eq 1 ]]; then
        jq '.' "$schema" >/dev/null || { echo "  ASSERT FAILED: schema is not valid JSON"; return 1; }
    fi
}

run_test "ENV-064 envelope has schema_version / version / items" test_envelope_has_schema_version
run_test "ENV-064 each item has required keys" test_item_has_required_keys
run_test "ENV-064 envelope present across multiple samples" test_multiple_samples_envelope
run_test "ENV-064 jq structural validation" test_jq_structural_check
run_test "ENV-064 schemas/envoy-analyze-output.json is valid JSON" test_schema_file_valid_json

print_summary
