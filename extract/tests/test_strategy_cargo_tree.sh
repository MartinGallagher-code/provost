#!/bin/bash
################################################################################
## Strategy Tests: cargo-tree
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: cargo-tree"
echo "========================================"

test_cargo_tree_basic () {
    local output
    output=$(run_mfe -r -s cargo-tree "$SAMPLES_DIR/cargo-tree/basic.txt")
    # Root crate and every dependency share the standard entry<N> contract
    # (entry1 = the root crate), one tidy row each.
    assert_contains "$output" "entry1.name myapp" "should extract root name"
    assert_contains "$output" "entry1.version 0.1.0" "should extract root version"
    assert_contains "$output" "entry2.name serde" "should extract first dep name"
    assert_contains "$output" "entry2.version 1.0.195" "should extract first dep version"
    assert_contains "$output" "entry3.name serde_derive" "should extract nested dep name"
    assert_contains "$output" "entry3.version 1.0.195" "should extract nested dep version"
    assert_contains "$output" "entry10.name tokio" "should extract tokio dep"
    assert_contains "$output" "entry13.name pin_project_lite" "should extract hyphenated dep"
}

test_cargo_tree_not_detected_for_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"key": "value", "count": 42}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s cargo-tree "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "should not apply to JSON"
}

test_cargo_tree_not_detected_for_npm_list () {
    local output
    output=$(run_mfe -d -s cargo-tree "$SAMPLES_DIR/npm-list/basic.txt" 2>&1)
    assert_contains "$output" "not applicable" "should not apply to npm list"
}

run_test "cargo-tree: basic extraction" test_cargo_tree_basic
run_test "cargo-tree: not detected for JSON" test_cargo_tree_not_detected_for_json
run_test "cargo-tree: not detected for npm list" test_cargo_tree_not_detected_for_npm_list

print_summary
